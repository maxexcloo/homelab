import os
import subprocess


def main():
    service = os.environ["SERVICE"]
    exists = (
        subprocess.run(
            ["flyctl", "apps", "info", service],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode
        == 0
    )
    if not exists:
        print(f"{service} not found, skipping deletion")
        return

    subprocess.run(
        ["flyctl", "apps", "destroy", service, "--yes"],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    print(f"{service} deleted")


if __name__ == "__main__":
    main()
