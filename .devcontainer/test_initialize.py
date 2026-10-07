"""Host-side tests for runtime selection and state/optional mounts; no engine is contacted."""

from pathlib import Path
import json
import re
import shutil
import socket
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("initialize.sh").resolve()
STATE_PATHS = (".cache/opencode", ".local/share/opencode")


class InitializeTest(unittest.TestCase):
    def initialize(self, engines, override=None, logs=False, remove_logs=False,
                   agent=None, socket_override=False, secrets=None, remove_secrets=False,
                     special_home=False, logs_file=False, existing_state=False):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory) / "project with spaces"
            root = parent / "src"
            root.mkdir(parents=True)
            (root / ".devcontainer").mkdir()
            log_dir = parent / "work logs"
            if logs:
                log_dir.mkdir()
            elif logs_file:
                log_dir.touch()
            commands = root / "commands"
            commands.mkdir()
            for name in ("id", "mkdir", "sed"):
                (commands / name).symlink_to(shutil.which(name))
            for name, output in engines.items():
                executable = commands / name
                executable.write_text(f"#!/bin/sh\nprintf '%s\\n' '{output}'\n")
                executable.chmod(0o755)
            runtime_dir = parent / "runtime"
            runtime_dir.mkdir()
            agent_path = runtime_dir / "prosecho-dev-agent.sock"
            if socket_override:
                agent_path = runtime_dir / "custom agent's $socket"
            shared_agent = socket.socket(socket.AF_UNIX)
            shared_agent.bind(str(runtime_dir / "shared.sock"))
            self.addCleanup(shared_agent.close)
            if agent == "socket":
                dedicated_agent = socket.socket(socket.AF_UNIX)
                dedicated_agent.bind(str(agent_path))
                self.addCleanup(dedicated_agent.close)
            elif agent == "file":
                agent_path.touch()
            home = parent / ("home's $config" if special_home else "home")
            home.mkdir()
            if existing_state:
                for path in STATE_PATHS:
                    state = home / path
                    state.mkdir(parents=True)
                    (state / "preserved").write_text("existing state\n")
            secrets_path = home / ".config/opencode/secrets.env"
            if secrets is not None:
                secrets_path.parent.mkdir(parents=True)
                if secrets == "file":
                    secrets_path.touch()
                elif secrets == "directory":
                    secrets_path.mkdir()
            env = {"PATH": str(commands), "XDG_RUNTIME_DIR": str(runtime_dir),
                   "HOME": str(home),
                   "SSH_AUTH_SOCK": str(runtime_dir / "shared.sock")}
            if socket_override is not False:
                env["PROSECHO_DEV_SSH_AGENT_SOCK"] = str(agent_path) if socket_override else ""
            if override is not None:
                env["DEVCONTAINER_RUNTIME"] = override
            result = subprocess.run(
                ["/bin/sh", str(SCRIPT)], cwd=root, env=env,
                capture_output=True, text=True, check=False,
            )
            overlay = root / ".devcontainer/compose.runtime.yaml"
            workspace = root / ".devcontainer/prosecho.code-workspace"
            if existing_state:
                first_overlay = overlay.read_text()
                result = subprocess.run(
                    ["/bin/sh", str(SCRIPT)], cwd=root, env=env,
                    capture_output=True, text=True, check=False,
                )
                self.assertEqual(overlay.read_text(), first_overlay)
            if remove_secrets:
                self.assertIn("target: /home/vscode/.config/opencode/secrets.env",
                              overlay.read_text())
                secrets_path.unlink()
                result = subprocess.run(
                    ["/bin/sh", str(SCRIPT)], cwd=root, env=env,
                    capture_output=True, text=True, check=False,
                )
            if remove_logs:
                self.assertIn("target: /work-logs", overlay.read_text())
                self.assertIn({"name": "Work Logs", "path": "/work-logs"},
                              json.loads(workspace.read_text())["folders"])
                log_dir.rmdir()
                result = subprocess.run(
                    ["/bin/sh", str(SCRIPT)], cwd=root, env=env,
                    capture_output=True, text=True, check=False,
                )
            self.assertEqual(log_dir.exists(), (logs and not remove_logs) or logs_file)
            self.assertFalse((root / "work logs").exists())
            self.assertFalse((root / "work-logs").exists())
            self.assertFalse((root / "work logs").is_symlink())
            self.assertFalse((root / "work-logs").is_symlink())
            self.assertFalse(log_dir.is_relative_to(root))
            self.assertEqual(agent_path.exists(), agent in ("socket", "file"))
            self.assertEqual(secrets_path.exists(), secrets is not None and not remove_secrets)
            self.assertEqual(secrets_path.parent.exists(), secrets is not None)
            if secrets == "directory":
                self.assertTrue(secrets_path.is_dir())
                self.assertEqual(list(secrets_path.iterdir()), [])
            if result.returncode == 0:
                for path in STATE_PATHS:
                    state = home / path
                    self.assertTrue(state.is_dir())
                    source = str(state).replace("'", "''").replace("$", "$$")
                    mount = (
                        "      - type: bind\n"
                        f"        source: '{source}'\n"
                        f"        target: /home/vscode/{path}\n"
                        "        read_only: false\n"
                        "        bind:\n"
                        "          create_host_path: false\n"
                    )
                    self.assertEqual(overlay.read_text().count(mount), 1)
                    if existing_state:
                        self.assertEqual((state / "preserved").read_text(), "existing state\n")
                    else:
                        self.assertEqual(list(state.iterdir()), [])
                self.assertFalse((home / ".opencode").exists())
                self.assertEqual(overlay.read_text().count("    volumes:"), 1)
                self.assertNotIn("target: /home/vscode/.config/opencode\n", overlay.read_text())
                folders = [{"name": "Prosecho", "path": "/prosecho"}]
                if logs and not remove_logs:
                    folders.append({"name": "Work Logs", "path": "/work-logs"})
                self.assertEqual(json.loads(workspace.read_text()), {"folders": folders})
                self.assertEqual("target: /work-logs" in overlay.read_text(),
                                 len(folders) == 2)
            else:
                self.assertFalse(workspace.exists())
            return result, overlay.read_text() if overlay.exists() else None

    def test_absent_or_directory_secrets_are_optional(self):
        for runtime in ("docker", "orbstack", "podman"):
            for secrets in (None, "directory"):
                with self.subTest(runtime=runtime, secrets=secrets):
                    result, overlay = self.initialize({}, runtime, secrets=secrets)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn("Optional OpenCode secrets unavailable", result.stderr)
                    self.assertNotIn("secrets.env", overlay)
                    self.assertIn("volumes:", overlay)
                    self.assertNotIn("app: {}", overlay)

    def test_secrets_file_mount_with_other_optional_mounts(self):
        for runtime in ("docker", "orbstack", "podman"):
            for logs in (False, True):
                for agent in (None, "socket"):
                    with self.subTest(runtime=runtime, logs=logs, agent=agent):
                        result, overlay = self.initialize(
                             {}, runtime, logs=logs, agent=agent, socket_override=True,
                             secrets="file")
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertNotIn("Optional OpenCode secrets unavailable", result.stderr)
                        self.assertIn("/home/.config/opencode/secrets.env'", overlay)
                        self.assertIn(
                            "        target: /home/vscode/.config/opencode/secrets.env\n"
                            "        read_only: true\n"
                            "        bind:\n"
                            "          create_host_path: false\n", overlay)
                        self.assertEqual(overlay.count("    volumes:"), 1)
                        self.assertEqual(overlay.count("      - type: bind"),
                                          3 + int(logs) + int(agent == "socket"))
                        self.assertNotIn("app: {}", overlay)

    def test_secrets_home_path_is_escaped(self):
        result, overlay = self.initialize({}, "docker", secrets="file", special_home=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("home''s $$config/.config/opencode/secrets.env'", overlay)

    def test_removed_secrets_clear_the_stale_mount(self):
        for runtime in ("docker", "orbstack", "podman"):
            for logs in (False, True):
                with self.subTest(runtime=runtime, logs=logs):
                    result, overlay = self.initialize(
                        {}, runtime, logs=logs, secrets="file", remove_secrets=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn("Optional OpenCode secrets unavailable", result.stderr)
                    self.assertNotIn("secrets.env", overlay)
                    self.assertIn("volumes:", overlay)
                    self.assertEqual("target: /work-logs" in overlay, logs)

    def test_dedicated_socket_mount_with_optional_logs(self):
        for runtime in ("docker", "orbstack", "podman"):
            for logs in (False, True):
                with self.subTest(runtime=runtime, logs=logs):
                    result, overlay = self.initialize(
                        {}, runtime, logs=logs, agent="socket", socket_override=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn("SSH_AUTH_SOCK: /run/prosecho-dev-agent.sock", overlay)
                    self.assertIn("GIT_SSH_COMMAND: sh /prosecho/.devcontainer/git-ssh.sh", overlay)
                    self.assertIn("read_only: true", overlay)
                    self.assertIn("create_host_path: false", overlay)
                    self.assertEqual(overlay.count("    volumes:"), 1)
                    self.assertEqual("target: /work-logs" in overlay, logs)
                    self.assertNotIn("shared.sock", overlay)

    def test_missing_or_regular_file_agent_never_falls_back_to_shared(self):
        for agent in (None, "file"):
            with self.subTest(agent=agent):
                result, overlay = self.initialize(
                    {}, "podman", agent=agent, socket_override=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Explicit SSH agent socket unavailable", result.stderr)
                self.assertNotIn("SSH_AUTH_SOCK", overlay)
                self.assertNotIn("GIT_SSH_COMMAND", overlay)
                self.assertIn("volumes:", overlay)

    def test_explicit_dedicated_socket_override_is_escaped(self):
        result, overlay = self.initialize({}, "podman", agent="socket", socket_override=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("custom agent''s $$socket'", overlay)

    def test_empty_socket_override_ignores_dedicated_and_shared_sockets(self):
        result, overlay = self.initialize({}, "podman", agent="socket", socket_override="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("agent", result.stderr)
        self.assertNotIn("SSH_AUTH_SOCK", overlay)
        self.assertNotIn("GIT_SSH_COMMAND", overlay)
        self.assertNotIn("agent.sock", overlay)
        self.assertNotIn("shared.sock", overlay)

    def test_default_ignores_dedicated_and_shared_sockets(self):
        for runtime in ("docker", "orbstack", "podman"):
            for agent in (None, "file", "socket"):
                with self.subTest(runtime=runtime, agent=agent):
                    result, overlay = self.initialize({}, runtime, agent=agent)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertNotIn("agent", result.stderr)
                    self.assertNotIn("SSH_AUTH_SOCK", overlay)
                    self.assertNotIn("GIT_SSH_COMMAND", overlay)
                    self.assertNotIn("agent.sock", overlay)
                    self.assertNotIn("shared.sock", overlay)

    def test_default_services_include_postgres_without_blocking_the_shell(self):
        config = json.loads(SCRIPT.with_name("devcontainer.json").read_text())
        self.assertEqual(config["runServices"], ["app", "postgres"])
        compose = SCRIPT.with_name("compose.yaml").read_text()
        # Inspect the small base service blocks without a YAML dependency or engine.
        services = dict(re.findall(r"^  (\w+):\n((?:    .*\n|\n)+)", compose, re.M))
        self.assertNotIn("profiles:", services["postgres"])
        self.assertIn("    image: docker.io/library/postgres:17\n", services["postgres"])
        self.assertNotIn("depends_on:", services["app"])
        self.assertIn("    command: sleep infinity\n", services["app"])

    def test_absent_logs_do_not_generate_a_mount(self):
        for runtime in ("docker", "orbstack", "podman"):
            with self.subTest(runtime=runtime):
                result, overlay = self.initialize({}, runtime)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("volumes:", overlay)
                self.assertNotIn("work-logs", overlay)
                self.assertEqual("keep-id:gid=100" in overlay, runtime == "podman")

    def test_podman_docker_wrapper_is_not_a_second_engine(self):
        result, overlay = self.initialize({
            "podman": "podman version 5.8.6",
            "docker": "Client: Podman Engine\nVersion: 5.8.6",
        })
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("keep-id:gid=100", overlay)

    def test_regular_file_logs_do_not_generate_a_mount_or_folder(self):
        for runtime in ("docker", "orbstack", "podman"):
            with self.subTest(runtime=runtime):
                result, overlay = self.initialize({}, runtime, logs_file=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("work-logs", overlay)

    def test_only_podman(self):
        result, overlay = self.initialize({"podman": "podman version 5.8.6"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("keep-id:gid=100", overlay)

    def test_opencode_state_is_created_and_preserved(self):
        for runtime in ("docker", "orbstack", "podman"):
            for existing_state in (False, True):
                with self.subTest(runtime=runtime, existing_state=existing_state):
                    result, _ = self.initialize(
                        {}, runtime, special_home=True, existing_state=existing_state)
                    self.assertEqual(result.returncode, 0, result.stderr)

    def test_optional_logs_mount_is_outside_workspace(self):
        for runtime in ("docker", "orbstack", "podman"):
            with self.subTest(runtime=runtime):
                result, overlay = self.initialize({}, runtime, logs=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("- type: bind", overlay)
                self.assertIn('source: "../../work logs"', overlay)
                self.assertIn("target: /work-logs", overlay)
                self.assertIn("create_host_path: false", overlay)
                self.assertNotIn("app: {}", overlay)
                self.assertEqual("keep-id:gid=100" in overlay, runtime == "podman")

    def test_only_docker(self):
        result, overlay = self.initialize({"docker": "Client: Docker Engine"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("userns_mode", overlay)

    def test_two_real_engines_require_override(self):
        result, overlay = self.initialize({
            "podman": "podman version 5.8.6", "docker": "Client: Docker Engine",
        })
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Set DEVCONTAINER_RUNTIME", result.stderr)
        self.assertIsNone(overlay)

    def test_orbstack_override_is_preserved(self):
        result, overlay = self.initialize({
            "podman": "podman version 5.8.6", "docker": "Client: Docker Engine",
        }, "orbstack")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("userns_mode", overlay)

    def test_removed_logs_clear_the_stale_mount(self):
        for runtime in ("docker", "orbstack", "podman"):
            with self.subTest(runtime=runtime):
                result, overlay = self.initialize({}, runtime, logs=True, remove_logs=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("volumes:", overlay)
                self.assertNotIn("work-logs", overlay)
                self.assertEqual("keep-id:gid=100" in overlay, runtime == "podman")

    def test_invalid_override_fails_without_overlay(self):
        result, overlay = self.initialize({}, "invalid")
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(overlay)

    def test_removed_logs_keep_other_optional_mounts(self):
        for runtime in ("docker", "orbstack", "podman"):
            with self.subTest(runtime=runtime):
                result, overlay = self.initialize(
                    {}, runtime, logs=True, remove_logs=True, agent="socket",
                    socket_override=True, secrets="file")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("work-logs", overlay)
                self.assertEqual(overlay.count("      - type: bind"), 4)
                self.assertIn("target: /run/prosecho-dev-agent.sock", overlay)
                self.assertIn("target: /home/vscode/.config/opencode/secrets.env", overlay)


if __name__ == "__main__":
    unittest.main()
