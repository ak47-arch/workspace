#!/usr/bin/env python3

import os
import sys
from pathlib import Path


WORKSPACE_ROOT = Path(__file__).resolve().parents[3]
SCRIPT = WORKSPACE_ROOT / "workspace-portability" / "restore_workspace.py"
os.execvp("python3", ["python3", str(SCRIPT), *sys.argv[1:]])
