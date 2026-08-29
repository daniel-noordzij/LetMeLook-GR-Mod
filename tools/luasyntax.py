#!/usr/bin/env python3
"""Lua syntax gate.

Exits 0 only if every file named on the command line parses. Anything else is a
non-zero exit, so it can be used as `luasyntax.py f.lua && cp ...` -- the copy is
gated on the CHECKER's exit code, not on grep's.

There is no Lua interpreter on this machine; `luaparser` (a Python Lua parser)
stands in for `luac -p`.
"""
import sys

try:
    from luaparser import ast
except ImportError:
    print("FAIL: luaparser is not installed (pip install luaparser)", file=sys.stderr)
    sys.exit(2)

if len(sys.argv) < 2:
    print("usage: luasyntax.py <file.lua> [...]", file=sys.stderr)
    sys.exit(2)

bad = 0
for path in sys.argv[1:]:
    try:
        with open(path, encoding="utf-8") as handle:
            ast.parse(handle.read())
    except Exception as exc:                      # noqa: BLE001 - report anything
        bad += 1
        print(f"FAIL {path}: {type(exc).__name__}: {exc}", file=sys.stderr)
    else:
        print(f"OK   {path}")

sys.exit(1 if bad else 0)
