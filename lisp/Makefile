# $Author: tv.raman.tv $
# Description:  Makefile for Emacsvox
# Keywords: Emacsvox, TTS, Makefile
###  LCD Entry:

# LCD Archive Entry:
# emacsvox| T. V. Raman |raman@cs.cornell.edu
# A speech interface to Emacs |
# Location https://github.com/robertmeta/emacsvox
#

###  Copyright:

#Copyright (C) 1995 -- 2024, T. V. Raman

# Copyright (c) 1994, 1995 by Digital Equipment Corporation.
# All Rights Reserved.
#
# This file is not part of GNU Emacs, but the same permissions apply.
#
# GNU Emacs is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# GNU Emacs is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with GNU Emacs; see the file COPYING.  If not, write to
# the Free Software Foundation, 51 Franklin Street, Fifth Floor, Boston,MA 02110-1301, USA.

### make rules

.POSIX:
# what emacs is called on your system
EMACS = emacs
SRC="../lisp"
# How to run in batch mode
BATCH = -batch -q -no-site-file     \
-f package-initialize \
--eval '(setq file-name-handler-alist nil gc-cons-threshold 64000000 \
load-source-file-function  nil)'
DEPS= -l $(SRC)/emacsvox-preamble.el -l $(SRC)/emacsvox-loaddefs.el

COMPILE =  -f batch-byte-compile
# How to compile
%.elc:  %.el
	@$(EMACS) $(BATCH)  $(DEPS)  $(COMPILE) $< &&  echo $<

###   grouping files into dependent modules

#The various modules:
TTS_OBJECTS =  \
emacsvox-preamble.elc \
emacsvox-loaddefs.elc \
tts-speak.elc		dectalk-voices.elc\
plain-voices.elc espeak-voices.elc \
outloud-voices.elc  mac-voices.elc \
swiftmac-voices.elc

AURAL_OBJECTS = \
emacsvox-aural.elc \
emacsvox-aural-spatial.elc \
emacsvox-aural-rules.elc \
emacsvox-aural-resources.elc \
emacsvox-aural-schemes.elc \
emacsvox-aural-transport.elc \
emacsvox-aural-description.elc \
emacsvox-aural-preview.elc \
emacsvox-aural-validation.elc \
emacsvox-aural-ui.elc \
emacsvox-aural-inspection.elc \
emacsvox-aural-scheme-manager.elc \
emacsvox-aural-tools.elc \
emacsvox-aural-recent-feedback.elc \
emacsvox-aural-feature-fragments.elc \
emacsvox-aural-home.elc \
emacsvox-aural-editor.elc \
emacsvox-aural-overrides.elc \
emacsvox-aural-simple-editor.elc \
emacsvox-aural-doctor.elc \
emacsvox-aural-profiles.elc \
emacsvox-aural-voice-palettes.elc \
emacsvox-aural-provider-org.elc \
emacsvox-aural-provider-workflows.elc \
emacsvox-aural-provider-markdown.elc \
emacsvox-aural-provider-notmuch.elc \
emacsvox-sounds.elc \
emacsvox-aural-sound-packs.elc

SPEAK_OBJECTS =   \
voice-setup.elc \
voice-defs.elc \
emacsvox-pronounce.elc \
emacsvox-speak.elc  \
emacsvox-advice.elc\
emacsvox-keymap.elc\
$(AURAL_OBJECTS) \
emacsvox.elc \
emacsvox-setup.elc

CORE_OBJECTS =  \
amixer.elc \
emacsvox-2048.elc \
emacsvox-abc-mode.elc \
emacsvox-ace-window.elc \
emacsvox-add-log.elc \
emacsvox-amark.elc \
emacsvox-agent-shell.elc \
emacsvox-annotate.elc \
emacsvox-arc.elc \
emacsvox-avy.elc \
emacsvox-auctex.elc \
emacsvox-bbdb.elc \
emacsvox-bibtex.elc \
emacsvox-bookmark.elc \
emacsvox-bookshare.elc \
emacsvox-browse-kill-ring.elc \
emacsvox-bs.elc \
emacsvox-buff-menu.elc \
emacsvox-c.elc \
emacsvox-calc.elc \
emacsvox-calculator.elc \
emacsvox-calendar.elc \
emacsvox-calibredb.elc \
emacsvox-chess.elc \
emacsvox-cider.elc \
emacsvox-clojure.elc \
emacsvox-cmuscheme.elc \
emacsvox-combobulate.elc \
emacsvox-comint.elc \
emacsvox-company.elc \
emacsvox-compile.elc \
emacsvox-consult.elc \
emacsvox-corfu.elc \
emacsvox-cperl.elc \
emacsvox-custom.elc \
emacsvox-dbus.elc \
emacsvox-deadgrep.elc \
emacsvox-denote.elc \
emacsvox-debugger.elc \
emacsvox-desktop.elc \
emacsvox-devdocs.elc \
emacsvox-dictionary.elc \
emacsvox-diff-mode.elc \
emacsvox-dired.elc \
emacsvox-dumb-jump.elc \
emacsvox-eat.elc \
emacsvox-embark.elc \
emacsvox-ebuku.elc \
emacsvox-ediff.elc \
emacsvox-eglot.elc \
emacsvox-ein.elc \
emacsvox-elfeed.elc \
emacsvox-elisp-refs.elc \
emacsvox-ellama.elc \
emacsvox-elpher.elc \
emacsvox-elpy.elc \
emacsvox-emms.elc \
emacsvox-empv.elc \
emacsvox-enriched.elc \
emacsvox-entertain.elc \
emacsvox-enwc.elc \
emacsvox-epa.elc \
emacsvox-epub.elc \
emacsvox-erc.elc \
emacsvox-eshell.elc \
emacsvox-ess.elc \
emacsvox-etable.elc \
emacsvox-eterm.elc \
emacsvox-eudc.elc \
emacsvox-evil.elc \
emacsvox-eww.elc \
emacsvox-extras.elc \
emacsvox-exwm.elc \
emacsvox-feeds.elc \
emacsvox-ffap.elc \
emacsvox-ffip.elc \
emacsvox-filtertext.elc \
emacsvox-flycheck.elc \
emacsvox-flymake.elc \
emacsvox-flyspell.elc \
emacsvox-folding.elc \
emacsvox-forge.elc \
emacsvox-forms.elc \
emacsvox-geiser.elc \
emacsvox-github-explorer.elc \
emacsvox-gnuplot.elc \
emacsvox-gnus.elc\
emacsvox-go-mode.elc \
emacsvox-gomoku.elc \
emacsvox-gptel.elc \
emacsvox-gptel.elc \
emacsvox-google.elc \
emacsvox-gridtext.elc \
emacsvox-gud.elc \
emacsvox-haskell.elc \
emacsvox-helm.elc \
emacsvox-helpful.elc \
emacsvox-hide-lines.elc  \
emacsvox-hide.elc \
emacsvox-hideshow.elc \
emacsvox-hydra.elc \
emacsvox-ibuffer.elc \
emacsvox-ido.elc \
emacsvox-iedit.elc \
emacsvox-info.elc\
emacsvox-ispell.elc \
emacsvox-ivy.elc \
emacsvox-journalctl.elc \
emacsvox-js2.elc \
emacsvox-kmacro.elc  \
emacsvox-librivox.elc \
emacsvox-lispy.elc \
emacsvox-lua.elc \
emacsvox-m-player.elc \
emacsvox-magit.elc \
emacsvox-make-mode.elc \
emacsvox-man.elc \
emacsvox-marginalia.elc \
emacsvox-markdown.elc \
emacsvox-maths.elc \
emacsvox-message.elc \
emacsvox-mines.elc \
emacsvox-mu4e.elc \
emacsvox-multiple-cursors.elc \
emacsvox-muse.elc \
emacsvox-net-utils.elc \
emacsvox-newsticker.elc \
emacsvox-notmuch.elc \
emacsvox-nov.elc \
emacsvox-nxml.elc \
emacsvox-ocr.elc \
emacsvox-org.elc \
emacsvox-orgalist.elc \
emacsvox-outline.elc \
emacsvox-package.elc \
emacsvox-paradox.elc \
emacsvox-perl.elc \
emacsvox-pipewire.elc \
emacsvox-popup.elc \
emacsvox-proced.elc \
emacsvox-project.elc \
emacsvox-projectile.elc \
emacsvox-py.elc \
emacsvox-pydoc.elc \
emacsvox-python.elc \
emacsvox-racket.elc \
emacsvox-re-builder.elc \
emacsvox-reftex.elc \
emacsvox-related.elc \
emacsvox-rg.elc \
emacsvox-rmail.elc \
emacsvox-rpm-spec.elc \
emacsvox-rst.elc \
emacsvox-ruby.elc \
emacsvox-rust-mode.elc \
emacsvox-sage.elc \
emacsvox-sdcv.elc \
emacsvox-ses.elc \
emacsvox-sgml-mode.elc \
emacsvox-sh-script.elc \
emacsvox-slime.elc \
emacsvox-smartparens.elc \
emacsvox-solitaire.elc \
emacsvox-speedbar.elc \
emacsvox-sql.elc \
emacsvox-sudoku.elc \
emacsvox-supercite.elc \
emacsvox-syslog.elc \
emacsvox-tab-bar.elc \
emacsvox-table-ui.elc \
emacsvox-table.elc \
emacsvox-tabulate.elc \
emacsvox-tabulated-list.elc \
emacsvox-tar.elc \
emacsvox-tcl.elc \
emacsvox-tempo.elc \
emacsvox-tetris.elc \
emacsvox-texinfo.elc \
emacsvox-threes.elc \
emacsvox-todo-mode.elc \
emacsvox-transient.elc \
emacsvox-treesit.elc \
emacsvox-typo.elc \
emacsvox-url-template.elc \
emacsvox-vdiff.elc \
emacsvox-vertico.elc \
emacsvox-view.elc \
emacsvox-vterm.elc \
emacsvox-wdired.elc \
emacsvox-we.elc \
emacsvox-websearch.elc \
emacsvox-webspace.elc \
emacsvox-widget.elc \
emacsvox-which-key.elc \
emacsvox-windmove.elc \
emacsvox-windows-speech.elc \
emacsvox-wizards.elc  \
emacsvox-woman.elc \
emacsvox-xkcd.elc \
emacsvox-xref.elc \
emacsvox-xslt.elc \
emacsvox-yaml.elc \
emacsvox-yasnippet.elc \
ladspa.elc \
soundscape.elc \
sox-gen.elc \
sox.elc

ADDON_OBJECTS = \
emacsvox-nm.elc  dom-addons.elc light.elc pip.elc  \
xbacklight.elc   tetris.elc   \
omaps.elc g-utils.elc gweb.elc gmaps.elc gm-nnir.elc

OBJECTS = $(TTS_OBJECTS) $(SPEAK_OBJECTS) $(CORE_OBJECTS)  $(ADDON_OBJECTS)

###   User level targets all

.PHONY: all aural
all: $(OBJECTS)

aural: emacsvox-preamble.elc emacsvox-loaddefs.elc emacsvox-keymap.elc \
$(AURAL_OBJECTS) emacsvox.elc emacsvox-setup.elc

emacsvox-aural-spatial.elc: emacsvox-aural.elc
emacsvox-aural-rules.elc: emacsvox-aural.elc emacsvox-aural-spatial.elc
emacsvox-aural-resources.elc: emacsvox-aural.elc emacsvox-aural-rules.elc
emacsvox-aural-schemes.elc: emacsvox-aural-resources.elc
emacsvox-aural-transport.elc: \
emacsvox-aural-schemes.elc emacsvox-aural-spatial.elc
emacsvox-aural-description.elc: emacsvox-aural-transport.elc
emacsvox-aural-preview.elc: emacsvox-aural-transport.elc
emacsvox-aural-validation.elc: emacsvox-aural-transport.elc
emacsvox-aural-inspection.elc: \
emacsvox-aural-ui.elc emacsvox-aural-transport.elc
emacsvox-aural-scheme-manager.elc: \
emacsvox-aural-inspection.elc emacsvox-aural-description.elc \
emacsvox-aural-preview.elc emacsvox-aural-validation.elc
emacsvox-aural-tools.elc: \
emacsvox-aural-inspection.elc emacsvox-aural-preview.elc \
emacsvox-aural-validation.elc emacsvox-aural-description.elc \
emacsvox-aural-scheme-manager.elc
emacsvox-aural-recent-feedback.elc: emacsvox-aural-tools.elc
emacsvox-aural-feature-fragments.elc: emacsvox-aural-tools.elc
emacsvox-aural-home.elc: \
emacsvox-aural-tools.elc emacsvox-aural-recent-feedback.elc \
emacsvox-aural-feature-fragments.elc emacsvox-aural-scheme-manager.elc
emacsvox-aural-editor.elc: \
emacsvox-aural-tools.elc emacsvox-aural-feature-fragments.elc
emacsvox-aural-overrides.elc: \
emacsvox-aural-tools.elc emacsvox-aural-editor.elc
emacsvox-aural-simple-editor.elc: \
emacsvox-aural-editor.elc emacsvox-aural-scheme-manager.elc
emacsvox-aural-doctor.elc: emacsvox-aural-tools.elc
emacsvox-aural-profiles.elc: emacsvox-aural-tools.elc
emacsvox-aural-voice-palettes.elc: emacsvox-aural-tools.elc
emacsvox-aural-provider-org.elc: emacsvox-aural-schemes.elc
emacsvox-aural-provider-workflows.elc: emacsvox-aural-schemes.elc
emacsvox-aural-provider-markdown.elc: emacsvox-aural-provider-workflows.elc
emacsvox-aural-provider-notmuch.elc: emacsvox-aural-provider-workflows.elc
emacsvox-sounds.elc: emacsvox-aural-resources.elc emacsvox-aural-transport.elc
emacsvox-aural-sound-packs.elc: \
emacsvox-aural-tools.elc emacsvox-sounds.elc
emacsvox.elc: emacsvox-preamble.elc emacsvox-keymap.elc $(AURAL_OBJECTS)
emacsvox-setup.elc: emacsvox-preamble.elc emacsvox.elc

muggles: emacsvox-muggles.elc
extra-muggles: extra-muggles.elc
maths: emacsvox-maths.elc

config: emacsvox-loaddefs.el
lint:
	echo "." |\
emacs -batch -q \
-f package-initialize \
-l advice.el -l emacsvox-preamble.el  -l emacsvox-loaddefs.el \
-f elint-directory

### build time target --loaddefs

emacsvox-loaddefs.el:
	@$(EMACS) $(BATCH)  -l ./emacsvox-preamble.el  \
	-l ./emacsvox-autoload.el  \
	-f emacsvox-auto-generate-autoloads

### Development  target: indent, tags, relint
indent:
	$(EMACS) -batch -q -no-site-file -l ../utils/indent-files.el

#identify long lines:
ll:
	wc -L *.el | sort -n

list-execs:
	grep executable-find *.el | cut -d '"' -f 2 | sort  | uniq
spell:
	codespell -I .codespell *.el
elint:
	$(EMACS) -batch -q -no-site-file -l ../utils/elint-files.el

relint:
	$(EMACS) -batch -f package-initialize -l relint.el -f relint-batch ./*.el

tags:
	etags *.el

###   user level target-- clean

clean:
	@rm -f *.elc  emacsvox-loaddefs.el

###  end of file

#local variables:
#mode: makefile
#fill-column: 90
#outline-regexp: "^### "
#end:
