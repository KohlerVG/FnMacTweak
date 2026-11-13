#!/usr/bin/env python3
"""Verify actual startup responder marshaling and synchronous return semantics."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'src/Tweak.xm').read_text()
start = source.index('static BOOL fnPerformResponderChangeOnMain(')
end = source.index('%hook UIResponder', start)
fixture = r'''
#import <Foundation/Foundation.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include "responder-under-test.inc"
int main(void) { @autoreleasepool {
    __block int calls = 0;
    BOOL result = fnPerformResponderChangeOnMain(^BOOL {
        assert([NSThread isMainThread]); ++calls; return YES;
    });
    assert(result && calls == 1);
    result = fnPerformResponderChangeOnMain(^BOOL {
        assert([NSThread isMainThread]); ++calls; return NO;
    });
    assert(!result && calls == 2);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL accepted = fnPerformResponderChangeOnMain(^BOOL {
            assert([NSThread isMainThread]); ++calls; return YES;
        });
        assert(accepted && calls == 3);
        BOOL rejected = fnPerformResponderChangeOnMain(^BOOL {
            assert([NSThread isMainThread]); ++calls; return NO;
        });
        assert(!rejected && calls == 4);
        dispatch_async(dispatch_get_main_queue(), ^{
            puts("Responder tests passed: main-thread execution, exactly-once calls, synchronous YES/NO results.");
            exit(0);
        });
    });
    // Run a Cocoa main run loop, as UIKitMacHelper expects on macOS.
    [[NSRunLoop mainRunLoop] run];
    return 1;
} }
'''
with tempfile.TemporaryDirectory(prefix='fn-responder-tests-') as directory:
    build = Path(directory)
    (build / 'responder-under-test.inc').write_text(source[start:end])
    (build / 'responder-tests.m').write_text(fixture)
    executable = build / 'responder-tests'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fblocks', '-Wall', '-Wextra',
                    str(build / 'responder-tests.m'), '-o', str(executable),
                    '-framework', 'Foundation'], check=True)
    subprocess.run([str(executable)], check=True, timeout=20)
