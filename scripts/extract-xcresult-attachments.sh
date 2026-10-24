#!/usr/bin/env bash
# Copy XCTAttachments out of an xcresult so CI can upload PNGs.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <result.xcresult> <output-dir>" >&2
  exit 1
fi

result="$1"
output="$2"
mkdir -p "$output"

if [[ ! -d "$result" ]]; then
  echo "missing xcresult: $result" >&2
  exit 1
fi

if xcrun xcresulttool export attachments --path "$result" --output-path "$output" 2>/dev/null; then
  :
elif xcrun xcresulttool export --type attachments --path "$result" --output-path "$output" 2>/dev/null; then
  :
else
  # Fallback: attachments are stored as files inside the bundle.
  while IFS= read -r file; do
    name="$(basename "$file")"
    cp "$file" "$output/$name"
  done < <(find "$result" -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' \) -print)
fi

count="$(find "$output" -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' \) | wc -l | tr -d ' ')"
echo "extracted $count screenshot files into $output"
if [[ "$count" -lt 4 ]]; then
  echo "expected at least 4 App Clip screenshots" >&2
  find "$output" -type f -print >&2
  exit 1
fi
