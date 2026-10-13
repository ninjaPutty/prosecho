"""Host-side tests for runtime selection and optional mounts; no engine is contacted."""

from pathlib import Path
import json
import re
import shutil
import shlex
import socket
import subprocess
import tempfile
import time
import unittest


SCRIPT = Path(__file__).with_name("initialize.sh").resolve()
STATE_PATHS = (".cache/opencode", ".local/share/opencode")


class InitializeTest(unittest.TestCase):
    def initialize(self, engines, override=None, logs=False, remove_logs=False,
                   agent=None, socket_override=False, secrets=None, remove_secrets=False,
                      special_home=False, logs_file=False, existing_state=False,
                       stale_state_mounts=False, context=None, docker_context=None,
                       docker_host=None, probe=None, probe_image=True, host_os="Linux",
                        shared=True, probe_id=None, image_status=0, context_status=0,
                        connection_env=None, relative=False, endpoint="unix:///var/run/docker.sock",
                        endpoint_status=0):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory) / "project with spaces"
            root = parent / "src"
            root.mkdir(parents=True)
            (root / ".devcontainer").mkdir()
            if stale_state_mounts:
                (root / ".devcontainer/compose.runtime.yaml").write_text(
                    "services:\n  app:\n    volumes:\n" + "".join(
                        f"      - ${{HOME}}/{path}:/home/vscode/{path}\n"
                        for path in STATE_PATHS))
            log_dir = parent / "work logs"
            if logs:
                log_dir.mkdir()
            elif logs_file:
                log_dir.touch()
            commands = root / "commands"
            commands.mkdir()
            for name in ("id", "mkdir", "sed", "sleep"):
                (commands / name).symlink_to(shutil.which(name))
            (commands / "uname").write_text(f"#!/bin/sh\nprintf '%s\\n' '{host_os}'\n")
            (commands / "uname").chmod(0o755)
            for name, output in engines.items():
                executable = commands / name
                executable.write_text(
                    "#!/bin/sh\n"
                    'case "$1 $2" in\n'
                    "  'context show') printf '%s\\n' default ;;\n"
                    "  'context inspect') printf '%s\\n' unix:///var/run/docker.sock ;;\n"
                    f"  *) printf '%s\\n' {shlex.quote(output)} ;;\nesac\n")
                executable.chmod(0o755)
            if context is not None or probe is not None or override in ("docker", "orbstack"):
                executable = commands / "docker"
                executable.write_text(
                    "#!/bin/sh\n"
                    'printf "%s\\n" "$*" >> "$HOME/engine-calls"\n'
                    'case "$1 $2" in\n'
                    f"  'context show') printf '%s\\n' {shlex.quote(context or 'default')}; "
                    f"exit {context_status} ;;\n"
                    f"  'context inspect') printf '%s\\n' {shlex.quote(endpoint)}; "
                    f"exit {endpoint_status} ;;\n"
                    "  'image inspect') " + (
                        "printf '%s\\n' " + shlex.quote(probe_id or "sha256:" + "a" * 64) +
                        f"; exit {image_status} ;;\n"
                        if probe_image else "exit 1 ;;\n") +
                    "  'run --rm') " + {
                        "ok": "exit 0", "missing": "exit 1",
                        "empty-agent": "exit 0", "malformed": "printf 'diagnostic'; exit 1",
                        "timeout": "exec sleep 30",
                    }.get(probe, "exit 1") + " ;;\n"
                    "  *) printf '%s\\n' 'Client: Docker Engine' ;;\nesac\n")
                executable.chmod(0o755)
            runtime_dir = parent / "runtime"
            runtime_dir.mkdir()
            agent_path = runtime_dir / "prosecho-dev-agent.sock"
            if socket_override:
                agent_path = runtime_dir / "custom agent's $socket"
            shared_agent = socket.socket(socket.AF_UNIX)
            shared_agent.bind(str(runtime_dir / "shared.sock"))
            self.addCleanup(shared_agent.close)
            shared_path = runtime_dir / "shared.sock"
            if shared in ("file", "missing"):
                shared_path = runtime_dir / "not-a-socket"
                if shared == "file":
                    shared_path.touch()
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
                   "SSH_AUTH_SOCK": str(shared_path) if shared else ""}
            if docker_context is not None:
                env["DOCKER_CONTEXT"] = docker_context
            if docker_host is not None:
                env["DOCKER_HOST"] = docker_host
            if socket_override is not False:
                env["PROSECHO_DEV_SSH_AGENT_SOCK"] = str(agent_path) if socket_override else ""
            if relative:
                variable = "PROSECHO_DEV_SSH_AGENT_SOCK" if socket_override else "SSH_AUTH_SOCK"
                # The relative path really resolves to a socket from the initializer's cwd.
                selected = agent_path if socket_override else shared_path
                env[variable] = "../runtime/" + selected.name
                self.assertTrue(selected.is_socket())
            if connection_env:
                env.update(connection_env)
            if override is not None:
                env["DEVCONTAINER_RUNTIME"] = override
            result = subprocess.run(
                ["/bin/sh", str(SCRIPT)], cwd=root, env=env,
                capture_output=True, text=True, check=False, timeout=30,
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
            calls = home / "engine-calls"
            if calls.exists():
                self.assertNotIn("ssh-add", calls.read_text())
                self.assertNotIn("createHostSourceDirs", calls.read_text())
                if "run --rm" in calls.read_text():
                    self.assertIn("--pull=never --network=none --read-only", calls.read_text())
                    self.assertIn("target=/run/developer-ssh-agent.sock,readonly", calls.read_text())
                    self.assertIn("--entrypoint /bin/sh sha256:", calls.read_text())
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
                    self.assertEqual(state.exists(), existing_state)
                    self.assertNotIn(f"target: /home/vscode/{path}", overlay.read_text())
                    if existing_state:
                        self.assertEqual((state / "preserved").read_text(), "existing state\n")
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
                                          1 + int(logs) + int(agent == "socket"))
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
                    self.assertIn("SSH_AUTH_SOCK: /run/developer-ssh-agent.sock", overlay)
                    self.assertNotIn("GIT_SSH_COMMAND", overlay)
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
                self.assertIn("selected socket unavailable", result.stderr)
                self.assertIn("SSH_AUTH_SOCK: ''", overlay)
                self.assertNotIn("GIT_SSH_COMMAND", overlay)
                self.assertIn("volumes:", overlay)

    def test_explicit_dedicated_socket_override_is_escaped(self):
        result, overlay = self.initialize({}, "podman", agent="socket", socket_override=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("custom agent''s $$socket'", overlay)

    def test_empty_socket_override_uses_shared_podman_socket(self):
        result, overlay = self.initialize({}, "podman", agent="socket", socket_override="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("agent", result.stderr)
        self.assertIn("SSH_AUTH_SOCK: /run/developer-ssh-agent.sock", overlay)
        self.assertNotIn("GIT_SSH_COMMAND", overlay)
        self.assertNotIn("runtime/prosecho-dev-agent.sock", overlay)
        self.assertIn("shared.sock", overlay)

    def test_default_agent_selection(self):
        for runtime in ("docker", "orbstack", "podman"):
            for agent in (None, "file", "socket"):
                with self.subTest(runtime=runtime, agent=agent):
                    result, overlay = self.initialize({}, runtime, agent=agent)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual("SSH agent gate" in result.stderr, runtime != "podman")
                    self.assertEqual("SSH_AUTH_SOCK: ''" in overlay, runtime != "podman")
                    self.assertNotIn("GIT_SSH_COMMAND", overlay)
                    self.assertNotIn("runtime/prosecho-dev-agent.sock", overlay)
                    self.assertEqual("shared.sock" in overlay, runtime == "podman")

    def test_missing_shared_agent_is_optional(self):
        for shared in (False, "file", "missing"):
            with self.subTest(shared=shared):
                result, overlay = self.initialize({}, "podman", shared=shared)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("SSH agent gate", result.stderr)
                self.assertIn("SSH_AUTH_SOCK: ''", overlay)
                self.assertIn("volumes: []", overlay)

    def test_orbstack_engine_side_bridge(self):
        for probe in ("ok", "empty-agent", "missing", "malformed", "timeout"):
            with self.subTest(probe=probe):
                started = time.monotonic()
                result, overlay = self.initialize(
                    {}, "orbstack", probe=probe, host_os="Darwin")
                self.assertLess(time.monotonic() - started, 12)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual("source: '/run/host-services/ssh-auth.sock'" in overlay,
                                 probe in ("ok", "empty-agent"))
                self.assertEqual("SSH_AUTH_SOCK: ''" in overlay,
                                 probe not in ("ok", "empty-agent"))

    def test_untrusted_or_unavailable_engine_probes_are_optional(self):
        for settings in ({"probe_id": "diagnostic"}, {"probe_id": "sha256:bad"},
                         {"probe_image": False}, {"image_status": 1},
                         {"context_status": 1}):
            with self.subTest(settings=settings):
                result, overlay = self.initialize(
                    {}, context="orbstack", probe="ok", host_os="Darwin", **settings)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("SSH_AUTH_SOCK: ''", overlay)

    def test_relative_socket_paths_are_rejected(self):
        for runtime, explicit in (("podman", False), ("podman", True),
                                  ("docker", True), ("orbstack", True)):
            with self.subTest(runtime=runtime, explicit=explicit):
                result, overlay = self.initialize(
                    {}, runtime, agent="socket", socket_override=explicit, relative=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("socket path must be absolute", result.stderr)
                self.assertIn("SSH_AUTH_SOCK: ''", overlay)
                self.assertNotIn("target: /run/developer-ssh-agent.sock", overlay)

    def test_remote_podman_never_mounts_client_sockets(self):
        for connection_env in ({"CONTAINER_HOST": "ssh://remote"},
                               {"CONTAINER_HOST": "unix:///run/podman/podman.sock"},
                               {"CONTAINER_CONNECTION": "remote"}):
            for explicit in (False, True):
                with self.subTest(connection_env=connection_env, explicit=explicit):
                    result, overlay = self.initialize(
                        {}, "podman", agent="socket", socket_override=explicit,
                        connection_env=connection_env)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn("agent mounts unsupported", result.stderr)
                    self.assertIn("SSH_AUTH_SOCK: ''", overlay)
                    self.assertNotIn("target: /run/developer-ssh-agent.sock", overlay)

    def test_remote_docker_and_orbstack_never_mount_client_sockets(self):
        for runtime in ("docker", "orbstack"):
            for settings in (
                {"docker_host": "tcp://remote:2376"},
                {"docker_host": "ssh://remote"},
                {"docker_context": "remote", "endpoint": "ssh://remote"},
                {"context": "remote", "endpoint": "tcp://remote:2376"},
                {"context": "orbstack", "endpoint": "ssh://remote"},
                {"docker_context": "remote", "endpoint_status": 1},
                {"context": "remote", "endpoint": "diagnostic"},
            ):
                for explicit in (False, True):
                    with self.subTest(runtime=runtime, settings=settings, explicit=explicit):
                        result, overlay = self.initialize(
                            {}, runtime, agent="socket", socket_override=explicit, **settings)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertIn("agent mounts unsupported", result.stderr)
                        self.assertIn("SSH_AUTH_SOCK: ''", overlay)
                        self.assertNotIn("target: /run/developer-ssh-agent.sock", overlay)

    def test_selected_docker_context(self):
        for context, env_context, docker_host, expected in (
            ("orbstack", None, None, True),
            ("other", None, None, False),
            ("other", "orbstack", "ssh://remote", True),
            ("orbstack", "other", None, False),
            ("orbstack", None, "ssh://remote", False),
        ):
            with self.subTest(context=context, env_context=env_context, docker_host=docker_host):
                result, overlay = self.initialize(
                    {}, context=context, docker_context=env_context,
                    docker_host=docker_host, probe="ok", host_os="Darwin")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual("source: '/run/host-services/ssh-auth.sock'" in overlay, expected)

    def test_named_state_and_editor_environment(self):
        compose = SCRIPT.with_name("compose.yaml").read_text()
        for name, path in (("data", ".local/share"), ("cache", ".cache")):
            self.assertIn(f"opencode-{name}:/home/vscode/{path}/opencode", compose)
            self.assertIn(f"  opencode-{name}:\n", compose)
        self.assertNotIn("${HOME}", compose)
        config = json.loads(SCRIPT.with_name("devcontainer.json").read_text())
        self.assertIs(config["customizations"]["vscode"]["settings"]
                      ["dev.containers.forwardSSHAgent"], False)
        self.assertEqual(config["remoteEnv"]["SSH_AUTH_SOCK"], "${containerEnv:SSH_AUTH_SOCK}")
        self.assertNotIn("workspaceFile", config)

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

    def test_opencode_state_is_not_created_or_mounted_and_existing_data_is_preserved(self):
        for runtime in ("docker", "orbstack", "podman"):
            for existing_state in (False, True):
                with self.subTest(runtime=runtime, existing_state=existing_state):
                    result, _ = self.initialize(
                        {}, runtime, special_home=True, existing_state=existing_state,
                        stale_state_mounts=True)
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
                self.assertEqual(overlay.count("      - type: bind"), 2)
                self.assertIn("target: /run/developer-ssh-agent.sock", overlay)
                self.assertIn("target: /home/vscode/.config/opencode/secrets.env", overlay)


if __name__ == "__main__":
    unittest.main()
