#!/usr/bin/env python3
"""M0 spike: run an imported wrapper the way the MCP server will.

usage: run.py <shortcut-name-or-uuid> '<json>' | --file <path>  [--timeout 30]

stdin of the child is /dev/null (an inherited MCP stdin hangs `shortcuts`).
Prints exit code, wall time, stdout/stderr and the output file.
"""
import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def resolve(name):
    """Name -> UUID via `shortcuts list --show-identifiers` (the product runs by UUID)."""
    out = subprocess.run(["shortcuts", "list", "--show-identifiers"], stdin=subprocess.DEVNULL,
                         capture_output=True, text=True, timeout=30).stdout
    for line in out.splitlines():
        if line.startswith(name + " (") and line.endswith(")"):
            return line[len(name) + 2:-1]
    return name


def main(argv):
    timeout = 30.0
    if "--timeout" in argv:
        i = argv.index("--timeout")
        timeout = float(argv[i + 1])
        del argv[i:i + 2]
    target = resolve(argv[0])
    tmp = Path(tempfile.mkdtemp(prefix="imcp-"))
    if argv[1] == "--file":
        inp = Path(argv[2])
    else:
        inp = tmp / "in.json"
        inp.write_text(json.dumps(json.loads(argv[1]), ensure_ascii=False))
    out = tmp / "out.txt"
    cmd = ["shortcuts", "run", target, "--input-path", str(inp), "--output-path", str(out),
           "--output-type", "public.plain-text"]
    t0 = time.monotonic()
    try:
        p = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=timeout)
        code, so, se = p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        code, so, se = "TIMEOUT", "", ""
    dt = time.monotonic() - t0
    print(json.dumps({"target": target, "exit": code, "seconds": round(dt, 2), "stdout": so, "stderr": se,
                      "output": out.read_text() if out.exists() else None}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main(sys.argv[1:])
