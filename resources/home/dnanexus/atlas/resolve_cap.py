#!/usr/bin/env python3
"""
Resolve the ploidy-cap decision and print shell-eval-able variable assignments.

Reads environment variables:
    max_ploidy                   (int, optional)
    ploidy_cap_purity_threshold  (float, optional)
    ploidy_cap_value             (int, default 2)

Prints to stdout (suitable for `eval` in bash):
    FIRST_ARGS_JSON=<quoted-JSON-string>
    CONDITIONAL=yes|no
    MODE=none|static|conditional
"""
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from ploidy_gate import decide

d = decide(
    max_ploidy=(int(os.environ["max_ploidy"]) if os.environ.get("max_ploidy") else None),
    threshold=(float(os.environ["ploidy_cap_purity_threshold"]) if os.environ.get("ploidy_cap_purity_threshold") else None),
    cap_value=int(os.environ.get("ploidy_cap_value", "2")),
)
print("FIRST_ARGS_JSON=" + json.dumps(json.dumps(d.first_pass_args)))  # quoted JSON string
print("CONDITIONAL=" + ("yes" if d.conditional else "no"))
print("MODE=" + d.mode.value)
