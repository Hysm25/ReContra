#!/usr/bin/env python3
import sys
import os
import shutil
import stat
import subprocess

if len(sys.argv) < 2:
    print("Usage: test_runner.py <binary_path> [args...]", file=sys.stderr)
    sys.exit(1)

bin_path = sys.argv[1]
args = sys.argv[2:]

target_bin = bin_path
# If not directly executable (e.g. on noexec Android storage mounts), execute via /tmp copy
if not os.access(bin_path, os.X_OK):
    tmp_bin = os.path.join("/tmp", os.path.basename(bin_path))
    shutil.copyfile(bin_path, tmp_bin)
    os.chmod(tmp_bin, stat.S_IRWXU | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
    target_bin = tmp_bin

res = subprocess.run([target_bin] + args)
sys.exit(res.returncode)
