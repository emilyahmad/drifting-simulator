#!/usr/bin/env bash
# Download your own songs from YouTube into assets/music as loudness-normalised MP3 files.
#
#   tools/fetch_music.sh <url> [url ...]          # appended after the existing tracks
#   tools/fetch_music.sh --at 1 <url>             # insert as track 01 (others shift down)
#
# Needs: brew install yt-dlp ffmpeg
# Files are named "NN - Title.mp3"; the radio plays them in that order and shows "Title".
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="assets/music"
mkdir -p "$OUT"

at=""
if [[ "${1:-}" == "--at" ]]; then
	at="$2"; shift 2
fi
[[ $# -gt 0 ]] || { sed -n '2,8p' "$0"; exit 1; }

for cmd in yt-dlp ffmpeg; do
	command -v "$cmd" >/dev/null || { echo "missing $cmd (brew install yt-dlp ffmpeg)"; exit 1; }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

i=0
for url in "$@"; do
	i=$((i + 1))
	# Order prefix keeps the songs in the order the URLs were given.
	yt-dlp -x --audio-format best --no-playlist -o "$tmp/$(printf '%03d' "$i")__%(title)s.%(ext)s" "$url"
done

shopt -s nullglob
count=$(ls "$OUT"/*.{ogg,mp3} 2>/dev/null | wc -l | tr -d ' ')

if [[ -n "$at" ]]; then
	# Shift existing tracks >= $at down to make room.
	n_new=$(ls "$tmp" | wc -l | tr -d ' ')
	ls "$OUT"/*.{ogg,mp3} 2>/dev/null | sort -r | while IFS= read -r f; do
		base="$(basename "$f")"
		num="${base%% - *}"
		rest="${base#* - }"
		if [[ "$num" =~ ^[0-9]+$ ]] && (( 10#$num >= at )); then
			mv "$f" "$OUT/$(printf '%02d' $((10#$num + n_new))) - $rest"
			[[ -f "$f.import" ]] && rm -f "$f.import"
		fi
	done
	next=$at
else
	next=$((count + 1))
fi

for src in "$tmp"/*; do
	title="$(basename "${src%.*}")"
	title="$(printf '%s' "${title#*__}" | tr -d '/:*?"<>|')"
	dest="$OUT/$(printf '%02d' "$next") - $title.mp3"
	echo "-> $dest"
	ffmpeg -loglevel error -y -i "$src" -vn -af loudnorm=I=-14:TP=-1.5:LRA=11 \
		-ar 44100 -c:a libmp3lame -q:a 2 "$dest"
	next=$((next + 1))
done
