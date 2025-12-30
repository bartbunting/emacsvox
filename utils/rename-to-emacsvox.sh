#!/bin/bash
# Rename emacspeak to emacsvox throughout the codebase
# Handles multiple case variations

set -euo pipefail

echo "Step 1: Replacing in .el file contents..."

# Replace in all .el files (multiple case patterns)
find lisp -name "*.el" -type f | while read file; do
  sed -i.rename-bak \
    -e 's/EMACSPEAK/EMACSVOX/g' \
    -e 's/EmacSpeak/EmacsVox/g' \
    -e 's/Emacspeak/Emacsvox/g' \
    -e 's/emacspeak/emacsvox/g' \
    "$file"
  echo "  ✓ Updated: $file"
done

echo "Step 1 complete: Content replaced in all .el files"
