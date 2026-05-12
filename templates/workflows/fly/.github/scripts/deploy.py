import os
import subprocess
from pathlib import Path


def run(command, **kwargs):
    return subprocess.run(command, check=True, text=True, **kwargs)


def create_service():
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
        run(["flyctl", "apps", "create", service])


def add_certificates():
    certs_file = Path(".certs")
    if not certs_file.exists():
        return

    service = os.environ["SERVICE"]
    for hostname in certs_file.read_text().splitlines():
        hostname = hostname.strip()
        if hostname:
            run(["flyctl", "certs", "add", hostname, "--app", service])


def import_secrets():
    env_file = Path(".env")
    if not env_file.exists():
        return

    service = os.environ["SERVICE"]
    secrets = "\n".join(
        line
        for line in env_file.read_text().splitlines()
        if line and not line.startswith("sops_")
    )
    if secrets:
        subprocess.run(
            ["flyctl", "secrets", "import", "--app", service],
            check=True,
            input=f"{secrets}\n",
            text=True,
        )


def deploy():
    service = os.environ["SERVICE"]
    run(
        ["flyctl", "deploy", "--app", service, "--config", "fly.toml"],
        stdout=subprocess.DEVNULL,
    )


def scale_machines():
    count_file = Path(".machine-count")
    if not count_file.exists():
        return

    service = os.environ["SERVICE"]
    count = count_file.read_text().strip()
    if count:
        run(["flyctl", "scale", "count", count, "--app", service])


def main():
    create_service()
    add_certificates()
    import_secrets()
    deploy()
    scale_machines()


if __name__ == "__main__":
    main()
