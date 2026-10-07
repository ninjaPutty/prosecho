"""Host-only isolated-agent tests using disposable keys; no network or real credentials."""

import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest


SCRIPT = Path(__file__).with_name("start-ssh-agent.sh").resolve()


class StartAgentTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.socket = self.root / "agent.sock"
        self.key = self.root / "github"
        self.other = self.root / "unexpected"
        for key in (self.key, self.other):
            subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(key)],
                           check=True, timeout=5)
        agent = subprocess.Popen(["ssh-agent", "-D", "-a", str(self.socket)],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(lambda: (agent.terminate(), agent.wait(timeout=5)))
        for _ in range(100):
            if self.socket.exists():
                break
            time.sleep(0.01)
        self.assertTrue(self.socket.exists())
        self.env = dict(os.environ, PROSECHO_DEV_SSH_AGENT_SOCK=str(self.socket),
                        SSH_AUTH_SOCK=str(self.socket), SSH_ASKPASS_REQUIRE="never")

    def helper(self, **env):
        return subprocess.run(["sh", str(SCRIPT), str(self.key)],
                              env=dict(self.env, SSH_AUTH_SOCK="/unused/shared.sock", **env),
                              stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=5)

    def identities(self):
        result = subprocess.run(["ssh-add", "-L"], env=self.env,
                                capture_output=True, text=True, timeout=5)
        return result.stdout

    def test_empty_and_matching_agent_load_only_selected_key(self):
        for _ in range(2):
            result = self.helper()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Lifetime set to 01:00:00", result.stderr)
            self.assertEqual(self.identities(), self.key.with_suffix(".pub").read_text())

    def test_shared_alias_and_regular_file_are_refused(self):
        result = subprocess.run(["sh", str(SCRIPT), str(self.key)], env=self.env,
                                stdin=subprocess.DEVNULL, capture_output=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        alias = self.root / "alias.sock"
        alias.symlink_to(self.socket)
        regular = self.root / "regular"
        regular.touch()
        for path in (alias, regular):
            result = self.helper(PROSECHO_DEV_SSH_AGENT_SOCK=str(path))
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.identities(), "The agent has no identities.\n")
            self.assertTrue(path.exists())

    def test_unexpected_and_multiple_identities_are_preserved(self):
        for key in (self.other, self.key):
            subprocess.run(["ssh-add", "-t", "60", str(key)], env=self.env,
                           capture_output=True, check=True, timeout=5)
            before = self.identities()
            result = self.helper()
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("refusing to change it", result.stderr)
            self.assertEqual(self.identities(), before)


if __name__ == "__main__":
    unittest.main()
