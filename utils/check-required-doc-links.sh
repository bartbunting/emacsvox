#!/bin/sh

set -eu

links_file=${1:-etc/docs-required-links.txt}

if ! command -v curl >/dev/null 2>&1; then
  echo "External documentation check requires curl." >&2
  exit 2
fi

failed=0
while IFS= read -r url; do
  case $url in
    ''|'#'*) continue ;;
  esac
  printf 'Checking %s\n' "$url"
  if ! curl --proto '=https' --location --fail --silent --show-error \
      --output /dev/null --max-time 30 --retry 2 --retry-delay 1 \
      --retry-all-errors "$url"
  then
    failed=1
  fi
done < "$links_file"

if [ "$failed" -ne 0 ]; then
  echo "One or more required documentation links failed." >&2
  exit 1
fi

echo "Required external documentation links are reachable."
