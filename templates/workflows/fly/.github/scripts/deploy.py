import json
import os
import subprocess
from pathlib import Path


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


def deploy():
    service = os.environ["SERVICE"]
    run(
        ["flyctl", "deploy", "--app", service, "--config", "fly.toml"],
        stdout=subprocess.DEVNULL,
    )


def json_rows(command):
    data = json.loads(output(command) or "[]")
    if isinstance(data, dict):
        for key in ("data", "items", "results"):
            if isinstance(data.get(key), list):
                return data[key]
        return []
    return data


def output(command):
    return subprocess.check_output(command, text=True).strip()


def row_value(row, *keys):
    for key in keys:
        value = row.get(key)
        if value:
            return value
    return None


def run(command, **kwargs):
    return subprocess.run(command, check=True, text=True, **kwargs)


def scale_machines():
    count_file = Path(".machine-count")
    if not count_file.exists():
        return

    service = os.environ["SERVICE"]
    count = count_file.read_text().strip()
    if count:
        run(["flyctl", "scale", "count", count, "--app", service])


def sync_certificates():
    certs_file = Path(".certs")
    service = os.environ["SERVICE"]
    desired = (
        {
            hostname
            for line in certs_file.read_text().splitlines()
            if (hostname := line.strip())
        }
        if certs_file.exists()
        else set()
    )
    current = {
        hostname
        for row in json_rows(["flyctl", "certs", "list", "--app", service, "--json"])
        if (hostname := row_value(row, "Hostname", "hostname"))
    }

    for hostname in sorted(current - desired):
        run(["flyctl", "certs", "remove", hostname, "--app", service, "--yes"])
    for hostname in sorted(desired - current):
        run(["flyctl", "certs", "add", hostname, "--app", service])


def sync_secrets():
    env_file = Path(".env")
    service = os.environ["SERVICE"]
    secret_lines = (
        [
            line
            for line in env_file.read_text().splitlines()
            if line and not line.startswith("sops_")
        ]
        if env_file.exists()
        else []
    )
    desired = {line.split("=", 1)[0] for line in secret_lines if "=" in line}
    current = {
        name
        for row in json_rows(["flyctl", "secrets", "list", "--app", service, "--json"])
        if (name := row_value(row, "Name", "name"))
    }
    stale = sorted(current - desired)

    if stale:
        run(["flyctl", "secrets", "unset", *stale, "--app", service, "--stage"])
    if secret_lines:
        secrets = "\n".join(secret_lines)
        subprocess.run(
            ["flyctl", "secrets", "import", "--app", service, "--stage"],
            check=True,
            input=f"{secrets}\n",
            text=True,
        )


def main():
    os.chdir(os.environ["SERVICE"])
    create_service()
    sync_certificates()
    sync_secrets()
    deploy()
    scale_machines()


if __name__ == "__main__":
    main()
