#!/usr/bin/env python3
"""Create isolated Docker fixtures, run live Swift checks, and clean up only those IDs."""
import json
import os
from pathlib import Path
import socket
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
NONCE = str(uuid.uuid4())
created = []


def run(args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True, timeout=180, **kwargs).stdout.strip()


try:
    # Docker context is checked before doing anything mutable; no remote engine.
    context = run(["docker", "context", "inspect"])
    endpoint = json.loads(context)[0]["Endpoints"]["docker"]["Host"]
    expected = "unix://" + str(Path.home() / ".docker/run/docker.sock")
    if endpoint != expected:
        raise RuntimeError("Live Docker tests require the local Docker Desktop Unix socket")
    # No host mounts, credentials, published non-loopback ports or extra capabilities.
    image = "busybox:1.37.0"
    run(["docker", "pull", image])
    digest = json.loads(run(["docker", "image", "inspect", image]))[0]["RepoDigests"][0]
    for role in ["target", "sentinel"]:
        with socket.socket() as reserve:
            reserve.bind(("127.0.0.1", 0))
            port = reserve.getsockname()[1]
        args = ["docker", "run", "-d", "--name", f"wtp-audit-{role}-{NONCE}",
                "--label", f"com.devdock.audit={NONCE}", "--read-only", "--cap-drop=ALL",
                "--security-opt=no-new-privileges", "--user", "65534:65534", "--memory", "32m", "--cpus", "0.25",
                "-p", f"127.0.0.1:{port}:8080", digest, "httpd", "-f", "-p", "8080"]
        created.append(run(args))
    env = dict(os.environ, WTP_RUN_LIVE_TESTS="1", WTP_AUDIT_DOCKER_ID=created[0],
               WTP_AUDIT_DOCKER_SENTINEL_ID=created[1], WTP_AUDIT_NONCE=NONCE)
    result = subprocess.run(["swift", "test", "--package-path", "DevDock", "-j", "4", "--filter", "LiveIntegrationTests"],
                            cwd=ROOT, env=env, text=True, timeout=240)
    print(f"Fixture image digest: {digest}")
    raise SystemExit(result.returncode)
finally:
    for container_id in created:
        try:
            info = json.loads(run(["docker", "inspect", container_id]))[0]
            if info["Config"]["Labels"].get("com.devdock.audit") == NONCE:
                run(["docker", "rm", "-f", container_id])
        except (subprocess.SubprocessError, ValueError, KeyError) as error:
            print(f"Fixture cleanup needs attention: {type(error).__name__}")
