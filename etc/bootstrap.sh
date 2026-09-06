#!/bin/bash
# Bootstrap a talking Emacsvox checkout with eSpeak on GNU/Linux.
# Usage: ./bootstrap.sh [git-ref] [destination]
# Prerequisites: Git, Emacs 30.2+, make, eSpeak NG, and its development headers.

set -euo pipefail

ref=${1:-master}
destination=${2:-emacsvox}
repository=${EMACSVOX_REPOSITORY:-https://github.com/bartbunting/emacsvox.git}
emacs=${EMACS:-emacs}

if [ ! -d "$destination/.git" ]; then
  git clone --branch "$ref" --depth 1 "$repository" "$destination"
fi

cd "$destination"
"$emacs" --batch --quick --eval \
  '(unless (version<= "30.2" emacs-version) (error "Emacsvox requires Emacs 30.2 or newer"))'

make bytecode EMACS="$emacs"
make espeak EMACS="$emacs"

export EMACSVOX_DIR=$PWD
export TTS_PROGRAM=${TTS_PROGRAM:-espeak}
exec "$emacs" -q -l "$EMACSVOX_DIR/lisp/emacsvox-setup.el" -l "$HOME/.emacs"
