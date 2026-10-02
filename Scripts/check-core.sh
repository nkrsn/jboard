#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/jboard-check.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT HUP INT TERM
swiftc -swift-version 5 -D JBOARD_STANDALONE_CHECKS \
  -module-cache-path "$check_dir/module-cache" \
  "$project_dir"/Core/*.swift \
  "$project_dir/Tests/CoreTests/InputControllerTests.swift" \
  "$project_dir/Tests/CommandLineChecks/main.swift" \
  -o "$check_dir/core-checks"
"$check_dir/core-checks"
