#!/usr/bin/env python3
"""
Parse a PURPLE purity TSV and print JSON scalars to stdout.

Usage: python3 parse_purity_scalars.py <purity_tsv>

Prints to stdout:
    {"purity": <float>, "ploidy": <int>, "sex": "male"|"female"|"unknown"}
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from purity import read_purity_ploidy

f = read_purity_ploidy(sys.argv[1])
sex = f.sample_sex if f.sample_sex in ("male", "female") else "unknown"
print(json.dumps({"purity": f.purity, "ploidy": f.ploidy_int(), "sex": sex}))
