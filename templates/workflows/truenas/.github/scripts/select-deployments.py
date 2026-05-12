import json
import os
import re
import subprocess
from pathlib import Path


def deployment_dirs():
    return sorted(
        path.as_posix()
        for path in Path(".").glob("*/*")
        if path.is_dir() and not path.parts[0].startswith(".")
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
    input_target = os.environ.get("INPUT_TARGET", "")
    target_pattern = re.compile(r"^[a-z0-9][a-z0-9-]*(/[a-z0-9][a-z0-9-]*)?$")
    deployment_pattern = re.compile(r"^[^./][^/]*/[^/]+$")

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
        current = load_current_deployments()
        previous = load_previous_deployments()
        removals = sorted(path for path in previous if path not in current)
        targets = sorted(
            path
            for path, deployment_hash in current.items()
            if previous.get(path) != deployment_hash
        )

    grouped = {}
    for path in targets:
        if not deployment_pattern.match(path):
            continue
        server, _service = path.split("/", 1)
        grouped.setdefault(server, {"paths": [], "removals": []})
        grouped[server]["paths"].append(path)

    for path in removals:
        if not deployment_pattern.match(path):
            continue
        server, service = path.split("/", 1)
        grouped.setdefault(server, {"paths": [], "removals": []})
        grouped[server]["removals"].append(service)

    deployments = [
        {
            "paths": sorted(values["paths"]),
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
