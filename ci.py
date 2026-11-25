#!/usr/bin/env python3
"""Helpers for the CoreSVG iOS-version CI test."""
import json
import os
import subprocess
import sys


def sh(cmd, **kw):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kw)


def pick_runtime(want):
    out = sh(["xcrun", "simctl", "list", "runtimes", "-j"]).stdout
    data = json.loads(out)
    matches = [
        r for r in data["runtimes"]
        if r.get("version", "").startswith(want) and r.get("isAvailable", True)
    ]
    if not matches:
        sys.stderr.write("available runtimes:\n")
        for r in data["runtimes"]:
            sys.stderr.write(f"  {r.get('version')} {r.get('identifier')} available={r.get('isAvailable')}\n")
        raise SystemExit(f"no available runtime matching {want}")
    return matches[0]["identifier"]


def create(want):
    runtime = pick_runtime(want)
    print(f"runtime={runtime}")
    out = sh([
        "xcrun", "simctl", "create", "CoreSVGTest",
        "com.apple.CoreSimulator.SimDeviceType.iPhone-15", runtime,
    ]).stdout.strip()
    print(f"device={out}")
    sh(["xcrun", "simctl", "boot", out])
    sh(["xcrun", "simctl", "bootstatus", out, "-b"], timeout=600)
    with open(os.environ["GITHUB_OUTPUT"], "a") as f:
        f.write(f"device={out}\n")


def run(device, files):
    failed = []
    for f in files:
        print(f"===== {f} =====", flush=True)
        p = subprocess.run(
            ["xcrun", "simctl", "spawn", device, os.path.abspath("./svgtest3"), os.path.abspath(f)],
            text=True, capture_output=True,
        )
        sys.stdout.write(p.stdout)
        sys.stderr.write(p.stderr)
        print(f"EXIT {f} = {p.returncode}", flush=True)
        if p.returncode != 0 or "ALL_OK" not in p.stdout:
            failed.append((f, p.returncode))
    if failed:
        print("CRASHES: " + ", ".join(f"{f}(rc={rc})" for f, rc in failed))
        raise SystemExit(1)
    print("ALL FILES PASSED")


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "create":
        create(sys.argv[2])
    elif cmd == "run":
        run(sys.argv[2], sys.argv[3:])
    else:
        raise SystemExit(f"unknown command {cmd}")
