import copy
import json
import os
import subprocess
import tempfile
from pathlib import Path, PurePosixPath


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


def deploy_catalog_service(service, app_file, previous_app):
    print(f"Deploying catalog service {service}")
    if app_exists(service):
        current = json.loads(output(["midclt", "call", "app.config", service]))
        desired = json.loads(app_file.read_text())
        previous_values = previous_app.get("values", {}) if previous_app else None
        payload = {
            "values": reconcile_values(
                current,
                previous_values,
                desired.get("values", {}),
            )
        }
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


def deploy_services():
    managed_files = json.loads(os.environ["MANAGED_FILES"])
    previous_managed_files = json.loads(os.environ["PREVIOUS_MANAGED_FILES"])

    for target_path in json.loads(os.environ["TARGET_PATHS"]):
        target = Path(target_path)
        service = target.name
        service_changed = False
        print(f"Deploying {service}")

        current_managed = managed_relative_paths(
            target,
            managed_files.get(target_path, []),
        )
        previous_managed = managed_relative_paths(
            target,
            previous_managed_files.get(target_path, []),
        )

        app_file = target / "app.json"
        if "app.json" in current_managed:
            if not app_file.is_file():
                raise FileNotFoundError(
                    f"Managed app configuration not found: {app_file}"
                )
            previous_app = load_previous_json(f"{target_path}/app.json")
            deploy_catalog_service(service, app_file, previous_app)
            service_changed = True

        compose_file = target / "compose.json"
        if "compose.json" in current_managed:
            if not compose_file.is_file():
                raise FileNotFoundError(
                    f"Managed compose configuration not found: {compose_file}"
                )
            deploy_custom_service(service, compose_file)
            service_changed = True

        current_sidecars = sidecar_paths(current_managed)
        previous_sidecars = sidecar_paths(previous_managed)

        containers = docker_containers()
        for rel_path in sorted(previous_sidecars - current_sidecars):
            validate_sidecar_path(rel_path)
            container_service = sidecar_container_service(rel_path, service)
            container = find_container(containers, service, container_service)

            if container:
                run(["docker", "exec", container, "rm", "-f", f"/{rel_path}"])
                service_changed = True
                print(f"✓ {container}:/{rel_path} removed")
            else:
                print(f"⚠ no container found to remove /{rel_path} from {service}")

        for rel_path in sorted(current_sidecars):
            validate_sidecar_path(rel_path)
            path = target / rel_path
            if not path.is_file():
                raise FileNotFoundError(f"Managed sidecar not found: {path}")

            container_service = sidecar_container_service(rel_path, service)
            container = find_container(containers, service, container_service)

            if container:
                parent = PurePosixPath(rel_path).parent.as_posix()
                if parent != ".":
                    run(
                        [
                            "docker",
                            "exec",
                            container,
                            "mkdir",
                            "-p",
                            f"/{parent}",
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


def load_previous_json(path):
    before = os.environ.get("BEFORE", "")
    if not before or set(before) == {"0"}:
        return None

    try:
        encrypted = subprocess.check_output(
            ["git", "show", f"{before}:{path}"],
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError:
        return None

    with tempfile.NamedTemporaryFile(suffix=".json") as encrypted_file:
        encrypted_file.write(encrypted)
        encrypted_file.flush()
        decrypted = subprocess.check_output(
            [
                "sops",
                "--decrypt",
                "--input-type",
                "json",
                "--output-type",
                "json",
                encrypted_file.name,
            ],
            text=True,
        )

    return json.loads(decrypted)


def managed_relative_paths(target, files):
    prefix = f"{target.as_posix()}/"
    return {
        file_path[len(prefix) :] for file_path in files if file_path.startswith(prefix)
    }


def output(command):
    return subprocess.check_output(command, text=True).strip()


def reconcile_values(current, previous, desired):
    reconciled = copy.deepcopy(current)
    if previous is not None:
        remove_stale_owned(reconciled, previous, desired)
    return deep_merge(reconciled, desired)


def remove_stale_owned(current, previous, desired):
    for key, previous_value in previous.items():
        if key not in desired:
            current_value = current.get(key)
            if isinstance(previous_value, dict) and isinstance(current_value, dict):
                remove_stale_owned(current_value, previous_value, {})
                if not current_value:
                    current.pop(key)
            else:
                current.pop(key, None)
        elif isinstance(previous_value, dict) and isinstance(desired[key], dict):
            current_value = current.get(key)
            if isinstance(current_value, dict):
                remove_stale_owned(current_value, previous_value, desired[key])


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


def run(command, **kwargs):
    return subprocess.run(command, check=True, text=True, **kwargs)


def sidecar_container_service(path, service):
    parts = PurePosixPath(path).parts
    return parts[0] if len(parts) > 1 else service


def sidecar_paths(paths):
    return {path for path in paths if path not in {"app.json", "compose.json"}}


def validate_sidecar_path(path):
    parsed = PurePosixPath(path)
    if parsed.is_absolute() or ".." in parsed.parts:
        raise ValueError(f"Invalid managed sidecar path: {path}")


if __name__ == "__main__":
    deploy_services()
