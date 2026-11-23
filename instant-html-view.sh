#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Open Clipboard HTML
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🌐
# @raycast.packageName Utilities
# @raycast.description Saves clipboard HTML to a file and opens it in the browser

set -euo pipefail

dir="${TMPDIR:-/tmp}/clipboard-html"

has_html_tag() {
  # true only if a real <html ...> opening tag exists (case-insensitive)
  printf '%s' "$1" | perl -0777 -ne 'exit(/<html\b[^>]*>/si ? 0 : 1)'
}

# 1) Plain text clipboard (HTML source copied from an editor, ChatGPT, etc.)
content="$(pbpaste)"

# 2) If the plain text isn't a full HTML document, try the rich HTML clipboard type
if ! has_html_tag "$content"; then
  rich="$(osascript -e 'the clipboard as «class HTML»' 2>/dev/null || true)"
  if [[ -n "$rich" ]]; then
    content="$(printf '%s' "$rich" | sed -e 's/«data HTML//' -e 's/»//' | xxd -r -p)"
  fi
fi

# --- Hard requirement: clipboard must contain an <html> tag -----------------
if ! has_html_tag "${content:-}"; then
  echo "No <html> in clipboard"
  exit 1
fi

# --- Derive the title -------------------------------------------------------

extract_tag() {
  # $1 = tag name; prints inner text of the first matching tag
  printf '%s' "$content" \
    | tr '\n' ' ' \
    | perl -0777 -ne "print \$1 if /<$1\\b[^>]*>(.*?)<\\/$1\\s*>/si"
}

title="$(extract_tag title)"
[[ -z "${title// }" ]] && title="$(extract_tag h1)"
[[ -z "${title// }" ]] && title="$(extract_tag h2)"

# Strip tags, decode the most common entities, collapse whitespace
title="$(printf '%s' "$title" \
  | perl -pe 's/<[^>]*>//g' \
  | perl -pe 's/&nbsp;/ /g; s/&amp;/&/g; s/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&#39;/'"'"'/g' \
  | tr '\n\t' '  ' \
  | sed -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//')"

# Filesystem-safe: drop / : and other awkward characters, trim length
title="$(printf '%s' "$title" | tr '/:\\*?"<>|' '-' | cut -c1-80 | sed -e 's/ *$//')"

[[ -z "$title" ]] && title="clip"

# --- Build the filename: "title - shortdate - shorttime" --------------------

mkdir -p "$dir"

shortdate="$(date +%Y-%m-%d)"
shorttime="$(date +%H.%M)"
file="$dir/$title - $shortdate - $shorttime.html"

# Avoid clobbering an existing file
n=2
while [[ -e "$file" ]]; do
  file="$dir/$title - $shortdate - $shorttime ($n).html"
  ((n++))
done

# The UTF-8 BOM makes browsers read umlauts/emoji correctly without breaking <!DOCTYPE>
{ printf '\xEF\xBB\xBF'; printf '%s' "$content"; } > "$file"

open "$file"          # default browser
# open -a "Google Chrome" "$file"   # or a specific browser

echo "Opened $(basename "$file")"
