#!/usr/bin/env python3
"""Read a minimal no-mistakes config: commands.{test,lint,format} and reviewer."""
import re
import sys


def unquote(v: str) -> str:
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ("'", '"'):
        return v[1:-1]
    h = v.find(" #")
    if h != -1:
        v = v[:h]
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ("'", '"'):
        return v[1:-1]
    return v


def main() -> int:
    if len(sys.argv) < 2:
        return 0
    try:
        lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
    except OSError:
        return 0
    out: dict[str, str] = {}
    in_cmds = False
    for ln in lines:
        if not ln.strip() or ln.lstrip().startswith("#"):
            continue
        if re.match(r"^\S", ln):  # top-level key
            in_cmds = bool(re.match(r"^commands:\s*$", ln))
            m = re.match(r"^reviewer:\s*(.+)$", ln)
            if m:
                out["reviewer"] = unquote(m.group(1))
            continue
        if in_cmds:
            m = re.match(r"^\s+(test|lint|format):\s*(.+)$", ln)
            if m:
                out[m.group(1)] = unquote(m.group(2))
    for k in ("test", "lint", "format", "reviewer"):
        if out.get(k):
            print(f"{k}={out[k]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
