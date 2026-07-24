#!/bin/sh
#$Iid:$
EMACS=${EMACS:-emacs}
LOAD="-L . -L ./g-client -l advice.el -l cl-macs.el -l cl-lib.el -l cl.elc \
 -l emacsvox-preamble.el -l emacsvox-loaddefs.el -l elint.el"
echo "$@" | \
"$EMACS" -batch -q -f package-initialize $LOAD -f elint-file
