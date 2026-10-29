#!/usr/bin/env bash
# Pulls the latest main, reinstalls Hablamon.app, and relaunches it.
# Refuses to run over uncommitted changes rather than losing them.
set -euo pipefail

cd "$(dirname "$0")/.."
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "error: uncommitted changes; commit or stash them first" >&2
    exit 1
fi
git switch --quiet main
git pull --ff-only origin main
scripts/install.sh

if pgrep -xq Hablamon; then
    osascript -e 'quit app "Hablamon"' >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do
        pgrep -xq Hablamon || break
        sleep 0.5
    done
    # Still busy (say, mid-replay) after 10 s: stop it, or the launch below lands on a dying app.
    if pgrep -xq Hablamon; then
        pkill -x Hablamon || true
        sleep 1
    fi
fi
# Launch Services can briefly refuse an app that just quit (error -609), so retry.
for attempt in 1 2 3; do
    open "$HOME/Applications/Hablamon.app" && break
    [ "$attempt" = 3 ] && exit 1
    sleep 1
done
echo "relaunched Hablamon ($(git rev-parse --short HEAD))"
