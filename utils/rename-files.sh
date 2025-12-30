#!/bin/bash
# Rename emacspeak-*.el files to emacsvox-*.el

cd lisp

for file in emacspeak-*.el; do
  if [ -f "$file" ]; then
    newname=$(echo "$file" | sed 's/emacspeak/emacsvox/')
    git mv "$file" "$newname"
    echo "✓ $file → $newname"
  fi
done

# Also rename emacspeak.el to emacsvox.el
if [ -f "emacspeak.el" ]; then
  git mv "emacspeak.el" "emacsvox.el"
  echo "✓ emacspeak.el → emacsvox.el"
fi

echo "File renaming complete!"
