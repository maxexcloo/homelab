import json
import os
import subprocess
from pathlib import Path


def run(command, **kwargs):
    return subprocess.run(command, check=True, text=True, **kwargs)


def output(command):
    return subprocess.check_output(command, text=True).strip()


def app_exists(service):
    return (
        subprocess.run(
            ["midclt", "call", "app.get_instance", service],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode
        == 0
    )


def deep_merge(base, overlay):
    merged = dict(base)
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = value

    return merged


def deploy_catalog_service(service, app_file):
    print(f"Deploying catalog service {service}")
    if app_exists(service):
        current = json.loads(output(["midclt", "call", "app.config", service]))
        desired = json.loads(app_file.read_text())
        payload = {"values": deep_merge(current, desired.get("values", {}))}
        run(
            ["midclt", "call", "-j", "app.update", service, json.dumps(payload)],
            stdout=subprocess.DEVNULL,
        )
        print(f"✓ {service} updated")
    else:
        print(f"{service} not found; creating catalog service")
        run(
            ["midclt", "call", "-j", "app.create", app_file.read_text()],
            stdout=subprocess.DEVNULL,
        )
        print(f"✓ {service} created")


def deploy_custom_service(service, compose_file):
    print(f"Deploying custom service {service}")
    if app_exists(service):
        compose = json.loads(compose_file.read_text())
        payload = {"custom_compose_config": compose["custom_compose_config"]}
        run(
            ["midclt", "call", "-j", "app.update", service, json.dumps(payload)],
            stdout=subprocess.DEVNULL,
        )
        print(f"✓ {service} updated")
    else:
        print(f"{service} not found; creating custom service")
        run(
            ["midclt", "call", "-j", "app.create", compose_file.read_text()],
            stdout=subprocess.DEVNULL,
        )
        print(f"✓ {service} created")


def docker_containers():
    names = output(["docker", "ps", "--format", "{{.Names}}"])
    return [name for name in names.splitlines() if name]


def find_container(containers, service, container_service):
    candidates = [f"ix-{service}-{container_service}-"]
    if container_service != service:
        candidates.append(f"ix-{service}-{service}-")

    for candidate in candidates:
        for container in containers:
            if container.startswith(candidate):
                return container

    return None


def restart_service_containers(service):
    matching = [
        container
        for container in docker_containers()
        if container.startswith(f"ix-{service}-")
    ]
    if not matching:
        print(f"⚠ no running containers found matching ix-{service}-*")
        return

    for container in matching:
        run(["docker", "restart", container], stdout=subprocess.DEVNULL)
        print(f"✓ {container} restarted")


def deploy_services():
    for target_path in json.loads(os.environ["TARGET_PATHS"]):
        target = Path(target_path)
        service = target.name
        service_changed = False
        print(f"Deploying {service}")

        app_file = target / "app.json"
        if app_file.exists():
            deploy_catalog_service(service, app_file)
            service_changed = True

        compose_file = target / "compose.json"
        if compose_file.exists():
            deploy_custom_service(service, compose_file)
            service_changed = True

        containers = docker_containers()
        for path in target.rglob("*"):
            if not path.is_file() or path.name in {"app.json", "compose.json"}:
                continue

            rel_path = path.relative_to(target).as_posix()
            container_service = rel_path.split("/", 1)[0]
            container = find_container(containers, service, container_service)

            if container:
                run(
                    [
                        "docker",
                        "exec",
                        container,
                        "mkdir",
                        "-p",
                        f"/{Path(rel_path).parent.as_posix()}",
                    ]
                )
                run(["docker", "cp", path.as_posix(), f"{container}:/{rel_path}"])
                service_changed = True
                print(f"✓ {container}:/{rel_path}")
            else:
                print(
                    f"⚠ no container found matching ix-{service}-{container_service}-* or ix-{service}-{service}-*"
                )

        if service_changed:
            restart_service_containers(service)


if __name__ == "__main__":
    deploy_services()
