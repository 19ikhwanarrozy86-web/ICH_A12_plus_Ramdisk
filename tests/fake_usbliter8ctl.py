#!/usr/bin/env python3
"""Safe fixture: validates command shape but never opens USB."""
import sys

if len(sys.argv) == 3 and sys.argv[1] == "boot":
    print(f"fake usbliter8ctl would boot {sys.argv[2]}")
    raise SystemExit(0)
raise SystemExit("unexpected fake usbliter8ctl invocation")
