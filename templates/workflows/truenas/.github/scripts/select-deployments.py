import json
import os
import re
import subprocess
from pathlib import Path


def deployment_changes(current_request, previous_request):
    current = current_request.get("deployments", {})
    previous = previous_request.get("deployments", {})
    removals = sorted(path for path in previous if path not in current)

    if current_request.get("workflow_revision") != previous_request.get(
        "workflow_revision"
    ):
        return sorted(current), removals

    targets = sorted(
        path
        for path, deployment in current.items()
        if deployment_hash(previous.get(path)) != deployment_hash(deployment)
    )
    return targets, removals


def deployment_dirs():
    return sorted(
        path.as_posix()
        for path in Path(".").glob("*/*")
        if path.is_dir() and not path.parts[0].startswith(".")
    )


def deployment_files(deployment):
    return deployment.get("files", []) if isinstance(deployment, dict) else []


def deployment_hash(deployment):
    return deployment.get("hash") if isinstance(deployment, dict) else deployment


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


def main():
    event_name = os.environ["EVENT_NAME"]
    input_target = os.environ.get("INPUT_TARGET", "")
    target_pattern = re.compile(r"^[a-z0-9][a-z0-9-]*(/[a-z0-9][a-z0-9-]*)?$")
    deployment_pattern = re.compile(r"^[^./][^/]*/[^/]+$")
    current_request = load_current_request()
    current = current_request.get("deployments", {})
    previous_request = (
        load_previous_request() if event_name != "workflow_dispatch" else {}
    )
    previous = previous_request.get("deployments", {})

    if (
        event_name == "workflow_dispatch"
        and input_target
        and not target_pattern.match(input_target)
    ):
        raise SystemExit(f"Invalid target: {input_target}")

    removals = []
    targets = []

    if event_name == "workflow_dispatch":
        if not input_target:
            targets = deployment_dirs()
        elif "/" in input_target:
            if not Path(input_target).is_dir():
                raise SystemExit(f"No deployment found for target: {input_target}")
            targets = [input_target]
        elif Path(input_target).is_dir():
            targets = sorted(
                path.as_posix()
                for path in Path(input_target).iterdir()
                if path.is_dir()
            )
        else:
            targets = [
                path
                for path in deployment_dirs()
                if path.split("/", 1)[1] == input_target
            ]
    else:
        targets, removals = deployment_changes(
            current_request,
            previous_request,
        )

    grouped = {}
    for path in targets:
        if not deployment_pattern.match(path):
            continue
        server, _service = path.split("/", 1)
        grouped.setdefault(
            server,
            {"files": {}, "paths": [], "previous_files": {}, "removals": []},
        )
        grouped[server]["files"][path] = deployment_files(current.get(path))
        grouped[server]["paths"].append(path)
        grouped[server]["previous_files"][path] = deployment_files(previous.get(path))

    for path in removals:
        if not deployment_pattern.match(path):
            continue
        server, service = path.split("/", 1)
        grouped.setdefault(
            server,
            {"files": {}, "paths": [], "previous_files": {}, "removals": []},
        )
        grouped[server]["removals"].append(service)

    deployments = [
        {
            "files": values["files"],
            "paths": sorted(values["paths"]),
            "previous_files": values["previous_files"],
            "removals": sorted(values["removals"]),
            "secret_name": f"AGE_KEY_{server.upper().replace('-', '_')}",
            "server": server,
        }
        for server, values in sorted(grouped.items())
    ]

    with open(os.environ["GITHUB_OUTPUT"], "a") as output_file:
        output_file.write(
            f"deployments={json.dumps(deployments, separators=(',', ':'))}\n"
        )


if __name__ == "__main__":
    main()
