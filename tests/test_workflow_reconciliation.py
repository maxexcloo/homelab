import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_module(name, relative_path):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


truenas = load_module(
    "truenas_deploy",
    "templates/workflows/truenas/.github/scripts/deploy.py",
)


class TrueNASReconciliationTests(unittest.TestCase):
    def test_reconcile_values_preserves_unmanaged_values(self):
        current = {
            "app": {
                "managed": "old",
                "user_owned": "keep",
            },
            "unmanaged": True,
        }
        previous = {
            "app": {
                "managed": "old",
                "removed": "stale",
            }
        }
        desired = {
            "app": {
                "managed": "new",
            }
        }

        self.assertEqual(
            truenas.reconcile_values(current, previous, desired),
            {
                "app": {
                    "managed": "new",
                    "user_owned": "keep",
                },
                "unmanaged": True,
            },
        )

    def test_reconcile_values_removes_empty_owned_objects(self):
        current = {
            "managed": {
                "removed": "stale",
            }
        }
        previous = {
            "managed": {
                "removed": "stale",
            }
        }

        self.assertEqual(truenas.reconcile_values(current, previous, {}), {})

    def test_managed_relative_paths_filters_other_services(self):
        target = Path("au-truenas/example")
        files = [
            "au-truenas/example/app.json",
            "au-truenas/example/app/config.yml",
            "au-truenas/other/app.json",
        ]

        self.assertEqual(
            truenas.managed_relative_paths(target, files),
            {
                "app.json",
                "app/config.yml",
            },
        )

    def test_validate_sidecar_path_rejects_unsafe_paths(self):
        for path in ("/absolute/config.yml", "../config.yml", "app/../../config.yml"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                truenas.validate_sidecar_path(path)

        truenas.validate_sidecar_path("app/config.yml")


if __name__ == "__main__":
    unittest.main()
