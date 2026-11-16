import json
import os
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

token = os.environ["BROWSERLESS_TOKEN"]
subprocess.run(
    ["podman", "secret", "create", "--replace", "browserless-token", "-"],
    input=token,
    text=True,
    stdout=subprocess.DEVNULL,
    check=True,
)

upstream = urlsplit(
    json.loads(Path(__file__).with_name("browserless.json").read_text())["upstream"]
)
directory = Path.home() / ".agent-browser"
directory.mkdir(mode=0o700, exist_ok=True)
path = directory / "config.json"
config = json.loads(path.read_text()) if path.exists() else {}
config["cdp"] = urlunsplit(
    ("ws", upstream.netloc, "/chromium", "", "")
)
config["cdpHeaders"] = json.dumps({"Authorization": f"Bearer {token}"})
descriptor, temporary = tempfile.mkstemp(dir=directory)
with os.fdopen(descriptor, "w") as target:
    json.dump(config, target)
    target.write("\n")
os.replace(temporary, path)
