import json
import os
import subprocess


def app_exists(service):
    return (
        subprocess.run(
            ["midclt", "call", "app.get_instance", service],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode
        == 0
    )


def main():
    for service in json.loads(os.environ["REMOVALS"]):
        if app_exists(service):
            subprocess.run(
                ["midclt", "call", "-j", "app.delete", service],
                check=True,
                stdout=subprocess.DEVNULL,
            )
            print(f"✓ {service} deleted")
        else:
            print(f"⚠ {service} not found, skipping deletion")


if __name__ == "__main__":
    main()
