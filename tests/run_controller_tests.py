#!/usr/bin/env python3
"""Run production controller dispatch/lifecycle functions against macOS device fixtures."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'src/Tweak.xm').read_text()
header = (root / 'src/globals.h').read_text()

def between(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]

parts = [
    between(header, 'typedef NS_ENUM(NSInteger, FnVirtualControllerMode)', 'extern FnVirtualControllerMode'),
    between(header, 'typedef NS_ENUM(NSInteger, FnControllerButton)', '// --- GLOBAL STATE ---'),
    between(source, 'static id g_virtualGamepad =', '@implementation FnInputPulse'),
    between(source, 'static BOOL dpadState[4]', '// Synthesise a keyboard key event'),
    between(source, 'static void dispatchControllerButton(NSInteger idx, BOOL pressed, BOOL isSync) {', '// ── Mapping Helpers'),
]
with tempfile.TemporaryDirectory(prefix='fn-controller-tests-') as directory:
    build = Path(directory)
    for i, part in enumerate(parts):
        (build / f'controller-part-{i}.inc').write_text(part)
    executable = build / 'controller-tests'
    subprocess.run([
        'xcrun', 'clang++', '-std=c++17', '-fobjc-arc', '-fblocks', '-Wall', '-Wextra',
        '-Wno-unused-parameter', '-Wno-unused-variable', '-I', str(build),
        str(root / 'tests/controller_tests.mm'), '-o', str(executable),
        '-framework', 'Foundation',
    ], check=True)
    subprocess.run([str(executable)], check=True)
