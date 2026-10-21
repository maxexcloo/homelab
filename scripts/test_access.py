"""Exercise the restricted native rsync pull and required client settings."""

import json
import os
import shlex
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WRAPPER = ROOT / "hosts/bento/ai-sync-rsync.sh"


class AccessTests(unittest.TestCase):
    def test_native_archive_pulls_keep_source_and_remove_only_destination_extras(self):
        version = subprocess.check_output(["rsync", "--version"], text=True)
        if "openrsync" in version:
            self.skipTest("Uses Bento/TrueNAS GNU rsync; put GNU rsync on PATH")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            models = root / "home/ai/models"
            models.mkdir(parents=True)
            (models / "sample model").write_text("model data")
            destination = root / "mirror"
            destination.mkdir()
            transport = root / "transport"
            transport.write_text(
                '#!/bin/sh\nshift\nexport SSH_ORIGINAL_COMMAND="$*"\nexec sh '
                + shlex.quote(str(WRAPPER))
                + "\n"
            )
            transport.chmod(0o700)
            binary = root / "bin"
            binary.mkdir()
            (binary / "rsync").symlink_to(shutil.which("rsync"))
            environment = dict(
                os.environ,
                HOME=str(root / "home"),
                PATH=str(binary) + os.pathsep + os.environ["PATH"],
            )
            for options in [[], ["--compress"], ["--numeric-ids"]]:
                with self.subTest(options=options):
                    (destination / "removed").write_text("old model")
                    result = subprocess.run(
                        [
                            "rsync",
                            "-a",
                            "--delete",
                            *options,
                            "-e",
                            str(transport),
                            "fixture:ai/models/",
                            str(destination),
                        ],
                        env=environment,
                        capture_output=True,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr.decode())
                    self.assertEqual(
                        (destination / "sample model").read_text(), "model data"
                    )
                    self.assertFalse((destination / "removed").exists())
                    self.assertEqual(
                        (models / "sample model").read_text(), "model data"
                    )

    def test_unsafe_commands_cannot_write_outside_or_remove_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            outside = root / "outside"
            outside.write_text("untouched")
            source = root / "ai/models/model"
            source.parent.mkdir(parents=True)
            source.write_text("model data")
            prefix = "rsync --server --sender -logDtpre.iLsfxCIvu "
            commands = [
                prefix + option + " . ai/models/"
                for option in [
                    "--log-file=" + str(outside),
                    "--only-write-batch=" + str(outside),
                    "--remove-source-files",
                    "--remove-sent-files",
                    "--files-from=" + str(outside),
                    "-M--log-file=" + str(outside),
                    "-T" + str(root),
                    "-L",
                    "-eunsafe",
                    "--daemon",
                ]
            ]
            commands += [
                "rsync --server -logDtpre.iLsfxCIvu . ai/models/",
                prefix + ". /etc/",
                prefix + ". ai/models/../outside",
                prefix + ". ai/models/;touch " + str(outside),
            ]
            for command in commands:
                with self.subTest(command=command):
                    result = subprocess.run(
                        ["sh", str(WRAPPER)],
                        env=dict(
                            os.environ, HOME=str(root), SSH_ORIGINAL_COMMAND=command
                        ),
                        capture_output=True,
                    )
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(b"ai-sync-rsync: refused", result.stderr)
                    self.assertEqual(outside.read_text(), "untouched")
                    self.assertEqual(source.read_text(), "model data")

    def test_required_settings_fail_with_their_names_before_writing(self):
        for script, setting in [
            ("render_ssh_config.sh", ".ssh.identity_agent"),
            ("render_ssh_config.sh", ".domains.infrastructure"),
            ("sync_client_configs.sh", ".onepassword.cluster_vault_prefix"),
        ]:
            for value in [None, ""]:
                with (
                    self.subTest(setting=setting, value=value),
                    tempfile.TemporaryDirectory() as temporary,
                ):
                    root = Path(temporary)
                    (root / "scripts").mkdir()
                    (root / "data").mkdir()
                    shutil.copy2(ROOT / "scripts" / script, root / "scripts" / script)
                    data = {
                        "domains": {"infrastructure": "example.invalid"},
                        "onepassword": {"cluster_vault_prefix": "Cluster "},
                        "ssh": {"identity_agent": "/fixture/agent"},
                    }
                    group, key = setting.lstrip(".").split(".")
                    data[group][key] = value
                    for filename in ["access.yaml", "domains.yaml"]:
                        (root / "data" / filename).write_text(json.dumps(data))
                    for tool in ["kubectl", "op", "talosctl"]:
                        path = root / tool
                        path.write_text("#!/bin/sh\nexit 0\n")
                        path.chmod(0o700)
                    destination = root / "configuration"
                    result = subprocess.run(
                        [str(root / "scripts" / script), str(destination)],
                        env=dict(
                            os.environ,
                            HOME=str(root),
                            PATH=str(root) + os.pathsep + os.environ["PATH"],
                        ),
                        capture_output=True,
                    )
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(setting.encode(), result.stderr)
                    self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main()
