import json
import os
import re
import subprocess
from pathlib import Path


def deployment_changes(current_request, previous_request):
    current = current_request.get("deployments", {})
    previous = previous_request.get("deployments", {})
    removals = sorted(service for service in previous if service not in current)

    if current_request.get("workflow_revision") != previous_request.get(
        "workflow_revision"
    ):
        return sorted(current), removals

    targets = sorted(
        service
        for service, deployment_hash in current.items()
        if previous.get(service) != deployment_hash
    )
    return targets, removals


def load_current_request():
    with open(".github/deploy-request.json") as file:
        return json.load(file)


def load_previous_request():
    before = os.environ["BEFORE"]
    try:
        previous = subprocess.check_output(
            ["git", "show", f"{before}:.github/deploy-request.json"],
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except subprocess.CalledProcessError:
        return {}

    return json.loads(previous)


def service_dirs():
    return sorted(
        path.name
        for path in Path(".").iterdir()
        if path.is_dir() and not path.name.startswith(".")
    )


def main():
    event_name = os.environ["EVENT_NAME"]
    input_service = os.environ.get("INPUT_SERVICE", "")
    service_pattern = re.compile(r"^[a-z0-9][a-z0-9-]*$")
    removals = []

    if event_name == "workflow_dispatch" and input_service:
        if not service_pattern.match(input_service):
            raise SystemExit(f"Invalid service: {input_service}")
        if not Path(input_service).is_dir():
            raise SystemExit(f"No deployment found for service: {input_service}")
        targets = [input_service]
    elif event_name == "workflow_dispatch":
        targets = service_dirs()
    else:
        targets, removals = deployment_changes(
            load_current_request(),
            load_previous_request(),
        )

    deployments = [
        {"action": "deploy", "service": service}
        for service in targets
        if service_pattern.match(service)
    ]
    deployments.extend(
        {"action": "delete", "service": service}
        for service in removals
        if service_pattern.match(service)
    )

    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"deployments={json.dumps(deployments, separators=(',', ':'))}\n")


if __name__ == "__main__":
    main()
