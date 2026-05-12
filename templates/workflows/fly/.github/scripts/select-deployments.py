import json
import os
import re
import subprocess
from pathlib import Path


def service_dirs():
    return sorted(
        path.name
        for path in Path(".").iterdir()
        if path.is_dir() and not path.name.startswith(".")
    )


def load_current_deployments():
    with open(".github/deploy-request.json") as file:
        return json.load(file).get("deployments", {})


def load_previous_deployments():
    before = os.environ["BEFORE"]
    try:
        previous = subprocess.check_output(
            ["git", "show", f"{before}:.github/deploy-request.json"],
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except subprocess.CalledProcessError:
        return {}

    return json.loads(previous).get("deployments", {})


def main():
    event_name = os.environ["EVENT_NAME"]
    input_service = os.environ.get("INPUT_SERVICE", "")
    service_pattern = re.compile(r"^[a-z0-9][a-z0-9-]*$")

    if event_name == "workflow_dispatch" and input_service:
        if not service_pattern.match(input_service):
            raise SystemExit(f"Invalid service: {input_service}")
        targets = [input_service]
    elif event_name == "workflow_dispatch":
        targets = service_dirs()
    else:
        current = load_current_deployments()
        previous = load_previous_deployments()
        targets = sorted(
            service
            for service, deployment_hash in current.items()
            if previous.get(service) != deployment_hash
        )

    deployments = [service for service in targets if service_pattern.match(service)]

    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"deployments={json.dumps(deployments, separators=(',', ':'))}\n")


if __name__ == "__main__":
    main()
