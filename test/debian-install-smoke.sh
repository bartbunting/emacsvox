#!/bin/sh
# Run only inside a disposable Debian/Ubuntu container, as root.
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
package=${1:?Usage: debian-install-smoke.sh /path/to/emacsvox.deb}
test -f /.dockerenv || { echo 'This test requires a disposable Docker container.' >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive
# Minimal Ubuntu images exclude documentation by default. Exercise the complete
# package rather than treating that image-level filtering as missing payload.
printf '%s\n' 'path-include=/usr/share/doc/emacsvox/*' 'path-include=/usr/share/man/*' \
    > /etc/dpkg/dpkg.cfg.d/zz-emacsvox-test
apt-get update
apt-get install -y --no-install-recommends emacs-nox
mkdir -p /root/.emacs.d /root/.config/emacsvox
printf '%s\n' ';; preserved personal init' > /root/.emacs.d/init.el
printf '%s\n' 'preserved setting' > /root/.config/emacsvox/package-test
apt-get install -y --no-install-recommends "$package"
test "$(dpkg-query -W -f='${Status}' emacsvox)" = 'install ok installed'
test -z "$(dpkg -V emacsvox)"
test ! -e /usr/bin/omnivox
emacsvox --remote --diagnose
TTS_PROGRAM=/bin/cat emacsvox -- --batch --eval '
(progn
  (load (expand-file-name "lisp/emacsvox-loaddefs.el" emacsvox-directory))
  (require (quote eww)) (require (quote emacsvox-eww))
  (unless (and (equal emacsvox-directory "/usr/share/emacsvox/")
               (file-readable-p (expand-file-name "emacsvox.info" emacsvox-info-directory)))
    (error "Installed runtime paths failed"))
  (princ "Installed package startup passed\n"))'
emacs --batch --eval '(when (featurep (quote emacsvox)) (error "Unexpected automatic speech activation"))'
apt-get install -y --reinstall --no-install-recommends "$package"
test -z "$(dpkg -V emacsvox)"
apt-get purge -y emacsvox
test ! -e /usr/bin/emacsvox
test ! -e /usr/share/emacsvox
test "$(cat /root/.emacs.d/init.el)" = ';; preserved personal init'
test "$(cat /root/.config/emacsvox/package-test)" = 'preserved setting'
echo 'PASS: install, terminal Emacs dependency, source startup, reinstall, purge and personal settings.'
