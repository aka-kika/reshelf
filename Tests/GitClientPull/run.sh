#!/bin/bash
# Compiles GitClient.swift with main.swift and runs the Pull (syncToUpstream)
# cases against throwaway git repos in a temp folder.
set -eu
cd "$(dirname "$0")"
out_dir="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}"
binary="$out_dir/GitClientPull"
swiftc -o "$binary" \
    ../../OpenSourceShelf/Services/Git/GitClient.swift \
    main.swift
"$binary"
