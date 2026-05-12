import base64
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def previous_output():
    data = sys.stdin.read()
    if not data:
        return "", ""

    try:
        previous_hash = json.loads(data).get("hash", "")
    except json.JSONDecodeError:
        previous_hash = ""

    return data, previous_hash


def sops_args(content_type):
    output_type = "json" if content_type == "binary" else content_type
    args = [
        "sops",
        "encrypt",
        "--age",
        os.environ["AGE_PUBLIC_KEY"],
        "--input-type",
        content_type,
        "--output-type",
        output_type,
    ]
    if os.environ.get("FILENAME"):
        args.extend(["--filename-override", os.environ["FILENAME"]])

    return args


def main():
    plaintext = base64.b64decode(os.environ["CONTENT"], validate=True)
    plaintext_hash = hashlib.sha256(plaintext).hexdigest()
    previous_data, previous_hash = previous_output()

    debug_path = os.environ.get("DEBUG_PATH", "")
    if debug_path:
        Path(debug_path).parent.mkdir(parents=True, exist_ok=True)
        Path(debug_path).write_bytes(plaintext)

    if previous_data and previous_hash == plaintext_hash:
        sys.stdout.write(previous_data)
        return

    with tempfile.TemporaryDirectory() as temp_dir:
        plaintext_path = Path(temp_dir) / "plaintext"
        encrypted_path = Path(temp_dir) / "encrypted"
        plaintext_path.write_bytes(plaintext)

        with encrypted_path.open("wb") as encrypted_file:
            subprocess.run(
                [*sops_args(os.environ["CONTENT_TYPE"]), str(plaintext_path)],
                check=True,
                stdout=encrypted_file,
            )

        json.dump(
            {
                "encrypted_content": encrypted_path.read_text(),
                "hash": plaintext_hash,
            },
            sys.stdout,
        )


if __name__ == "__main__":
    main()
