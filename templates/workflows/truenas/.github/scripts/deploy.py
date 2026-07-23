import copy
import json
import os
import subprocess
import tempfile
from pathlib import Path, PurePosixPath

IX_VOLUME_ROOT = PurePosixPath("/mnt/.ix-apps/app_mounts")


def app_containers(service):
    app = json.loads(output(["midclt", "call", "app.get_instance", service]))
    return app["active_workloads"]["container_details"]


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
        print(f"Deploying {service}")

        current_managed = managed_relative_paths(
            target,
            managed_files.get(target_path, []),
        )
        previous_managed = managed_relative_paths(
            target,
            previous_managed_files.get(target_path, []),
        )
        removed_sidecars = sidecar_paths(previous_managed) - sidecar_paths(
            current_managed
        )
        if removed_sidecars and app_exists(service):
            remove_sidecars(service, removed_sidecars)

        app_file = target / "app.json"
        if "app.json" in current_managed:
            if not app_file.is_file():
                raise FileNotFoundError(
                    f"Managed app configuration not found: {app_file}"
                )
            previous_app = load_previous_json(f"{target_path}/app.json")
            deploy_catalog_service(service, app_file, previous_app)

        compose_file = target / "compose.json"
        if "compose.json" in current_managed:
            if not compose_file.is_file():
                raise FileNotFoundError(
                    f"Managed compose configuration not found: {compose_file}"
                )
            deploy_custom_service(service, compose_file)

        current_sidecars = sidecar_paths(current_managed)
        if current_sidecars:
            write_sidecars(service, target, current_sidecars)
            run(
                ["midclt", "call", "-j", "app.redeploy", service],
                stdout=subprocess.DEVNULL,
            )
            print(f"✓ {service} redeployed")


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


def managed_storage_mount(mount, service):
    if mount["type"] == "volume":
        return True
    if mount["type"] != "bind":
        return False

    source = PurePosixPath(mount["source"])
    return source.is_relative_to(IX_VOLUME_ROOT / service)


def output(command):
    return subprocess.check_output(command, text=True).strip()


def reconcile_values(current, previous, desired):
    reconciled = copy.deepcopy(current)
    if previous is not None:
        remove_stale_owned(reconciled, previous, desired)
    return deep_merge(reconciled, desired)


def remove_sidecars(service, sidecars):
    containers = app_containers(service)
    for rel_path in sorted(sidecars):
        validate_sidecar_path(rel_path)
        try:
            container = volume_container(containers, rel_path, service)
        except RuntimeError:
            print(f"⚠ {service}:/{rel_path} was not stored in managed storage")
            continue
        destination = f"/{rel_path}"
        run(["docker", "exec", container, "rm", "-f", destination])
        print(f"✓ {service}:{destination} removed")


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


def run(command, **kwargs):
    return subprocess.run(command, check=True, text=True, **kwargs)


def sidecar_paths(paths):
    return {path for path in paths if path not in {"app.json", "compose.json"}}


def validate_sidecar_path(path):
    parsed = PurePosixPath(path)
    if parsed.is_absolute() or ".." in parsed.parts:
        raise ValueError(f"Invalid managed sidecar path: {path}")


def volume_container(containers, path, service):
    target = PurePosixPath("/") / path
    candidates = []

    for container in containers:
        if container["state"] not in {"running", "starting"}:
            continue
        for mount in container["volume_mounts"]:
            destination = PurePosixPath(mount["destination"])
            if (
                "ro" not in mount["mode"].split(",")
                and managed_storage_mount(mount, service)
                and destination in target.parents
            ):
                candidates.append((len(destination.parts), container["id"]))

    if not candidates:
        raise RuntimeError(
            f"Managed sidecar /{path} is not backed by writable managed storage"
        )

    return max(candidates)[1]


def write_sidecars(service, target, sidecars):
    containers = app_containers(service)
    for rel_path in sorted(sidecars):
        validate_sidecar_path(rel_path)
        source = target / rel_path
        if not source.is_file():
            raise FileNotFoundError(f"Managed sidecar not found: {source}")

        container = volume_container(containers, rel_path, service)
        destination = PurePosixPath("/") / rel_path
        run(["docker", "exec", container, "mkdir", "-p", str(destination.parent)])
        run(["docker", "cp", source.as_posix(), f"{container}:{destination}"])
        print(f"✓ {service}:{destination}")


if __name__ == "__main__":
    deploy_services()
