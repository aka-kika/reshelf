#!/bin/bash
# Runs every logic test in Tests/<Name>/run.sh. Each one compiles the app
# sources it needs plus its own main.swift with swiftc and runs the result.
# No Xcode test target: a hosted test would launch reshelf against the real
# catalog in ~/reshelf. Tests use in-memory stores and temp folders only.
set -u
cd "$(dirname "$0")"
export TEST_BUILD_DIR="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}"
failed=0
for t in */run.sh; do
    name="${t%/run.sh}"
    echo "== $name"
    if ! bash "$t"; then
        echo "FAILED: $name"
        failed=$((failed + 1))
    fi
done
[ "$failed" -eq 0 ] && echo "All tests passed." || echo "$failed test group(s) failed."
exit "$failed"
