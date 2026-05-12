import json
import os
import subprocess
from pathlib import Path


def is_binary_sops_json(content):
    try:
        payload = json.loads(content)
    except json.JSONDecodeError:
        return False

    if set(payload) != {"data", "sops"}:
        return False

    data = payload["data"]
    return isinstance(data, str) and data.startswith("ENC[AES256_GCM")


def decrypt_files(root):
    for path in Path(root).rglob("*"):
        if not path.is_file():
            continue

        content = path.read_text(errors="ignore")
        if (
            "BEGIN AGE ENCRYPTED FILE" not in content
            and "ENC[AES256_GCM" not in content
        ):
            continue

        if is_binary_sops_json(content):
            decrypted = subprocess.check_output(
                [
                    "sops",
                    "--decrypt",
                    "--input-type",
                    "json",
                    "--output-type",
                    "binary",
                    path,
                ]
            )
            path.write_bytes(decrypted)
        else:
            subprocess.run(["sops", "--decrypt", "--in-place", path], check=True)


if __name__ == "__main__":
    decrypt_files(os.environ.get("DECRYPT_ROOT", "."))
