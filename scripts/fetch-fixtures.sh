#!/usr/bin/env bash
# Downloads fixture videos that are too large for git into Tests/Fixtures/videos/.
# Each file is pinned by SHA-256; a file that's already present and matches is skipped.
# A failed download only warns, because tests skip when a fixture is missing.
set -uo pipefail

cd "$(dirname "$0")/.."
dir=Tests/Fixtures/videos
mkdir -p "$dir"

# name | Google Drive file ID | sha256
fixtures=(
    "far.mp4|11XuOSuHXMJdC45W4ioz11gpULz8NeaVs|81471a532436685dc4d24ad78a8830f128712da301a5094e5d6762a033d6c57b"
    "academy-lobby_far.mp4|1DnN4SZqv3ZNo_5WC9dcY1cjAChy7ZGWJ|9275cdaba69ac224e7a06e527e7230cce832f44943c1570fd8f9656a97cbbb38"
    "classroom_far.mp4|1XPnHCGWO7Gh8lXArpE2Ae6FScE3JQ3i2|cb9792039f7810c7a4a4e1865454bf131d0aba7cd6e289b69fbc0b6a6d2c6eb3"
)

sha256() {
    if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

status=0
for entry in "${fixtures[@]}"; do
    IFS='|' read -r name id expected <<<"$entry"
    path="$dir/$name"
    if [ -f "$path" ] && [ "$(sha256 "$path")" = "$expected" ]; then
        echo "ok      $path"
        continue
    fi
    echo "fetch   $path"
    url="https://drive.usercontent.google.com/download?id=$id&export=download&confirm=t"
    if curl -fsSL --retry 3 -o "$path.part" "$url" && [ "$(sha256 "$path.part")" = "$expected" ]; then
        mv "$path.part" "$path"
    else
        rm -f "$path.part"
        echo "warning: could not fetch $name (download failed or checksum mismatch)" >&2
        status=1
    fi
done
[ "${1:-}" = "--strict" ] && exit "$status"
exit 0
