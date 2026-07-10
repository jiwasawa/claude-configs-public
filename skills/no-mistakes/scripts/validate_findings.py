#!/usr/bin/env python3
"""Validate reviewer findings against the no-mistakes schema (strict)."""
import json
import sys

SEVERITY = {"error", "warning", "info"}
ACTION = {"auto-fix", "ask-user", "no-op"}
FIELDS = {"id", "severity", "file", "line", "action", "description"}


def main() -> int:
    raw = open(sys.argv[1]).read() if len(sys.argv) > 1 else sys.stdin.read()
    try:
        data = json.loads(raw)
    except Exception as e:
        print(f"invalid JSON: {e}", file=sys.stderr)
        return 1
    if not isinstance(data, list):
        print("findings must be a JSON array", file=sys.stderr)
        return 1
    seen = set()
    for i, f in enumerate(data):
        if not isinstance(f, dict):
            print(f"finding {i} is not an object", file=sys.stderr)
            return 1
        if set(f.keys()) != FIELDS:
            print(f"finding {i} fields must be exactly {sorted(FIELDS)}", file=sys.stderr)
            return 1
        if not isinstance(f["id"], str) or not f["id"]:
            print(f"finding {i} bad id", file=sys.stderr)
            return 1
        if f["id"] in seen:
            print(f"duplicate id: {f['id']}", file=sys.stderr)
            return 1
        seen.add(f["id"])
        if not isinstance(f["severity"], str) or f["severity"] not in SEVERITY:
            print(f"finding {i} bad severity", file=sys.stderr)
            return 1
        if not isinstance(f["action"], str) or f["action"] not in ACTION:
            print(f"finding {i} bad action", file=sys.stderr)
            return 1
        if f["file"] is not None and not isinstance(f["file"], str):
            print(f"finding {i} bad file", file=sys.stderr)
            return 1
        if f["line"] is not None and (type(f["line"]) is not int or f["line"] < 1):
            print(f"finding {i} bad line", file=sys.stderr)
            return 1
        if not isinstance(f["description"], str) or not f["description"]:
            print(f"finding {i} bad description", file=sys.stderr)
            return 1
    print(f"valid: {len(data)} findings")
    return 0


if __name__ == "__main__":
    sys.exit(main())
