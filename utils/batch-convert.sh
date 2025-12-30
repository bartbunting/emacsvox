#!/bin/bash
# Batch convert multiple files

for file in "$@"; do
  echo "Converting $file..."
  emacs --batch -l utils/defadvice-to-advice-add.el --eval "(ems-convert-file \"$file\")" 2>&1 | tail -1
  sed -i.bak4 's/result result))/result))/g' "$file"
  echo "✓ $file converted"
done
