#!/usr/bin/env bash
# Runs every check and writes a summary to reports/verify.md.
# Add a step per test layer as it lands (see "Testing plan" in docs/plans/init.md).
set -uo pipefail

cd "$(dirname "$0")/.."
mkdir -p reports
report=reports/verify.md
log_dir=reports/logs
mkdir -p "$log_dir"

failed=0
rows=()

step() {
    local name=$1
    shift
    local log="$log_dir/${name// /-}.log"
    echo "==> $name"
    if "$@" >"$log" 2>&1; then
        rows+=("| $name | pass |")
    else
        rows+=("| $name | **FAIL** (see \`$log\`) |")
        failed=1
        tail -n 40 "$log"
    fi
}

step "lint" swift format lint --recursive --strict Package.swift Sources Tests
step "photo privacy" python3 -I scripts/photo-privacy.py check Tests/Fixtures
step "build" swift build
step "test" swift test --disable-xctest

{
    echo "# Verify report"
    echo
    echo "- Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "- Commit: $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "- Platform: $(uname -sm)"
    echo "- Swift: $(swift --version 2>/dev/null | head -n 1)"
    echo
    echo "| Step | Result |"
    echo "| --- | --- |"
    printf '%s\n' "${rows[@]}"
} >"$report"

cat "$report"
exit "$failed"
