#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"

test_dir=$(mktemp -d "${TMPDIR:-/tmp}/chimpodoro-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -swift-version 5 -O Sources/Pomodoro.swift Tests/main.swift -o "$test_dir/pomodoro-tests"
"$test_dir/pomodoro-tests"
