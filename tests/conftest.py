import os
import sys

# Make the bundled helpers (packaged under resources/home/dnanexus/atlas, imported by
# code.sh as top-level modules) importable for the unit tests.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "resources", "home", "dnanexus", "atlas"))
