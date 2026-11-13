#!/usr/bin/env python3
"""Compile and run the actual motion hooks with deterministic host fixtures (macOS)."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'src/ue_reflection.m').read_text()
start = source.index('void ue_apply_gyro_velocity(')
end = source.index('// Button reflection (Existing)')
with tempfile.TemporaryDirectory(prefix='fn-motion-tests-') as directory:
    build = Path(directory)
    (build / 'motion-under-test.inc').write_text(source[start:end])
    executable = build / 'motion-tests'
    subprocess.run([
        'xcrun', 'clang', '-fobjc-arc', '-fblocks', '-Wall', '-Wextra',
        '-Wno-unused-parameter', '-I', str(build),
        str(root / 'tests/motion_tests.m'), '-o', str(executable),
        '-framework', 'Foundation', '-framework', 'GameController',
        '-framework', 'CoreMotion',
    ], check=True)
    subprocess.run([str(executable)], check=True)
