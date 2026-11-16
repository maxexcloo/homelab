import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class BrowserlessCredentials(unittest.TestCase):
    def test_native_client_auth_stays_private_and_out_of_urls_and_logs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            home = root / "home"
            config_directory = home / ".agent-browser"
            config_directory.mkdir(parents=True)
            config = config_directory / "config.json"
            config.write_text(json.dumps({"timeout": 5000, "cdp": "ws://old"}))
            script = root / "prepare_browserless.py"
            shutil.copyfile(
                Path(__file__).parents[1] / "templates/proxy/prepare_browserless.py",
                script,
            )
            (root / "browserless.json").write_text(
                json.dumps({"upstream": "http://127.0.0.1:9222"})
            )
            (root / "podman").write_text(
                '#!/bin/sh\ncat > "$PROXY_TEST_INPUT"\nprintf "secret-created\\n"\n'
            )
            (root / "podman").chmod(0o700)
            token = "fixture-browserless-credential"
            result = subprocess.run(
                [sys.executable, str(script)],
                env={
                    **os.environ,
                    "BROWSERLESS_TOKEN": token,
                    "HOME": str(home),
                    "PATH": str(root) + os.pathsep + os.environ["PATH"],
                    "PROXY_TEST_INPUT": str(root / "secret-input"),
                },
                capture_output=True,
                text=True,
                check=True,
            )
            actual = json.loads(config.read_text())
            self.assertEqual(actual["cdp"], "ws://127.0.0.1:9222/chromium")
            self.assertEqual(
                json.loads(actual["cdpHeaders"]), {"Authorization": f"Bearer {token}"}
            )
            self.assertEqual(actual["timeout"], 5000)
            self.assertEqual(stat.S_IMODE(config.stat().st_mode), 0o600)
            self.assertEqual((root / "secret-input").read_text(), token)
            self.assertEqual(result.stdout, "")
            self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
