# $Author: tv.raman.tv $
# Description:  Makefile for Emacsvox
# Keywords: Emacsvox, TTS, Makefile
###  LCD Entry:

# LCD Archive Entry:
# emacsvox| T. V. Raman |raman@cs.cornell.edu
# A speech interface to Emacs |
# Location https://github.com/bartbunting/emacsvox
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
load-source-file-function nil load-prefer-newer t)'
DEPS= -l $(SRC)/emacsvox-preamble.el -l $(SRC)/emacsvox-loaddefs.el

COMPILE =  -f batch-byte-compile
# How to compile
%.elc:  %.el
	@$(EMACS) $(BATCH)  $(DEPS)  $(COMPILE) $< &&  echo $<

###   grouping files into dependent modules

#The various modules:
VOICE_OBJECTS = \
voice-setup.elc \
voice-defs.elc \
dectalk-voices.elc \
plain-voices.elc \
espeak-voices.elc \
outloud-voices.elc \
mac-voices.elc \
swiftmac-voices.elc \
omnivox-choice-codec.elc \
omnivox-parameters-codec.elc \
omnivox-parameters.elc \
omnivox-native-codec.elc \
omnivox-library-apply.elc \
omnivox-library.elc \
omnivox-catalogue.elc \
omnivox-preview.elc \
omnivox-voices.elc

TTS_OBJECTS = \
emacsvox-version.elc \
emacsvox-paths.elc \
emacsvox-preamble.elc \
tts-queue-state.elc \
omnivox-remote.elc \
omnivox-engine-settings.elc \
omnivox-engine-configuration.elc \
omnivox-punctuation.elc \
omnivox-punctuation-profiles.elc \
omnivox-espeak-variants.elc \
tts-speak.elc \
$(VOICE_OBJECTS)

AURAL_RUNTIME_OBJECTS = \
$(TTS_OBJECTS) \
emacsvox-pronounce.elc \
emacsvox-speak.elc

AURAL_OBJECTS = \
emacsvox-aural.elc \
emacsvox-aural-concrete.elc \
emacsvox-aural-history.elc \
emacsvox-aural-spatial.elc \
emacsvox-aural-rules.elc \
emacsvox-aural-resources.elc \
emacsvox-aural-schemes.elc \
emacsvox-aural-routing-profiles.elc \
emacsvox-aural-voice-data.elc \
emacsvox-aural-voice-runtime.elc \
emacsvox-aural-voice-drafts.elc \
emacsvox-aural-voice-editing.elc \
emacsvox-aural-voice-editor.elc \
emacsvox-aural-voice-menu.elc \
emacsvox-capitalization.elc \
emacsvox-interaction.elc \
emacsvox-spelling.elc \
emacsvox-tone-editor.elc \
emacsvox-line-cues.elc \
emacsvox-output-settings.elc \
emacsvox-settings.elc \
emacsvox-settings-workflows.elc \
emacsvox-settings-integrations.elc \
emacsvox-settings-changes.elc \
emacsvox-aural-voice-bulk.elc \
emacsvox-aural-voice-engine-controls.elc \
emacsvox-aural-voice-context.elc \
emacsvox-aural-profile-service.elc \
emacsvox-aural-compatibility-voice.elc \
emacsvox-aural-providers.elc \
emacsvox-aural-compiler.elc \
emacsvox-emoji.elc \
emacsvox-aural-source.elc \
emacsvox-aural-planner.elc \
emacsvox-aural-submission.elc \
emacsvox-aural-transport.elc \
emacsvox-aural-description.elc \
emacsvox-aural-preview.elc \
emacsvox-aural-replay.elc \
emacsvox-aural-validation.elc \
emacsvox-aural-ui.elc \
emacsvox-aural-inspection.elc \
emacsvox-aural-semantics.elc \
emacsvox-aural-explanation.elc \
emacsvox-aural-tools.elc \
emacsvox-aural-recent-feedback.elc \
emacsvox-aural-feedback-details.elc \
emacsvox-aural-feature-fragments.elc \
emacsvox-omnivox-components.elc \
emacsvox-aural-home.elc \
emacsvox-aural-editor.elc \
emacsvox-aural-overrides.elc \
emacsvox-aural-doctor.elc \
emacsvox-aural-profiles.elc \
emacsvox-aural-voice-palettes.elc \
emacsvox-aural-voice-workbench.elc \
emacsvox-aural-change-feedback.elc \
emacsvox-aural-provider-org.elc \
emacsvox-aural-provider-workflows.elc \
emacsvox-aural-provider-org-srs.elc \
emacsvox-aural-provider-markdown.elc \
emacsvox-aural-provider-notmuch.elc \
emacsvox-sounds.elc \
emacsvox-aural-sound-packs.elc \
emacsvox-sound-library.elc

SPEAK_OBJECTS =   \
emacsvox-pronounce.elc \
emacsvox-speak.elc  \
emacsvox-advice.elc\
emacsvox-keymap.elc\
emacsvox-indentation.elc\
emacsvox-aural-menu.elc\
emacsvox-welcome.elc\
$(AURAL_OBJECTS) \
emacsvox.elc \
emacsvox-setup.elc

CORE_OBJECTS =  \
integrations/amixer.elc \
integrations/emacsvox-2048.elc \
integrations/emacsvox-abc-mode.elc \
integrations/emacsvox-ace-window.elc \
integrations/emacsvox-add-log.elc \
integrations/emacsvox-amark.elc \
integrations/emacsvox-agent-shell-render.elc \
integrations/emacsvox-agent-shell.elc \
integrations/emacsvox-annotate.elc \
integrations/emacsvox-arc.elc \
integrations/emacsvox-avy.elc \
integrations/emacsvox-auctex.elc \
integrations/emacsvox-bbdb.elc \
integrations/emacsvox-bibtex.elc \
integrations/emacsvox-bookmark.elc \
integrations/emacsvox-bookshare.elc \
integrations/emacsvox-browse-kill-ring.elc \
integrations/emacsvox-bs.elc \
integrations/emacsvox-buff-menu.elc \
integrations/emacsvox-c.elc \
integrations/emacsvox-calc.elc \
integrations/emacsvox-calculator.elc \
integrations/emacsvox-calendar.elc \
integrations/emacsvox-calibredb.elc \
integrations/emacsvox-chess.elc \
integrations/emacsvox-cider.elc \
integrations/emacsvox-clojure.elc \
integrations/emacsvox-cmuscheme.elc \
integrations/emacsvox-combobulate.elc \
integrations/emacsvox-comint.elc \
integrations/emacsvox-company.elc \
integrations/emacsvox-compile.elc \
integrations/emacsvox-consult.elc \
integrations/emacsvox-corfu.elc \
integrations/emacsvox-cperl.elc \
integrations/emacsvox-custom.elc \
integrations/emacsvox-dbus.elc \
integrations/emacsvox-deadgrep.elc \
integrations/emacsvox-denote.elc \
integrations/emacsvox-debugger.elc \
integrations/emacsvox-desktop.elc \
integrations/emacsvox-devdocs.elc \
integrations/emacsvox-dictionary.elc \
integrations/emacsvox-diff-mode.elc \
integrations/emacsvox-dired.elc \
integrations/emacsvox-dumb-jump.elc \
integrations/emacsvox-eat-core.elc \
integrations/emacsvox-eat-input.elc \
integrations/emacsvox-eat-review.elc \
integrations/emacsvox-eat.elc \
integrations/emacsvox-embark.elc \
integrations/emacsvox-ebuku.elc \
integrations/emacsvox-ediff.elc \
integrations/emacsvox-eglot.elc \
integrations/emacsvox-ein.elc \
integrations/emacsvox-elfeed.elc \
integrations/emacsvox-elisp-refs.elc \
integrations/emacsvox-ellama.elc \
integrations/emacsvox-elpher.elc \
integrations/emacsvox-elpy.elc \
integrations/emacsvox-emms.elc \
integrations/emacsvox-empv.elc \
integrations/emacsvox-enriched.elc \
integrations/emacsvox-entertain.elc \
integrations/emacsvox-enwc.elc \
integrations/emacsvox-epa.elc \
integrations/emacsvox-epub.elc \
integrations/emacsvox-erc.elc \
integrations/emacsvox-eshell.elc \
integrations/emacsvox-ess.elc \
integrations/emacsvox-etable.elc \
integrations/emacsvox-eterm.elc \
integrations/emacsvox-eudc.elc \
integrations/emacsvox-evil.elc \
integrations/emacsvox-eww.elc \
emacsvox-extras.elc \
integrations/emacsvox-exwm.elc \
integrations/emacsvox-feeds.elc \
integrations/emacsvox-ffap.elc \
integrations/emacsvox-ffip.elc \
emacsvox-filtertext.elc \
integrations/emacsvox-flycheck.elc \
integrations/emacsvox-flymake.elc \
integrations/emacsvox-flyspell.elc \
integrations/emacsvox-folding.elc \
integrations/emacsvox-forge.elc \
integrations/emacsvox-forms.elc \
integrations/emacsvox-geiser.elc \
integrations/emacsvox-gnuplot.elc \
integrations/emacsvox-gnus.elc\
integrations/emacsvox-go-mode.elc \
integrations/emacsvox-gomoku.elc \
integrations/emacsvox-gptel.elc \
integrations/emacsvox-gptel.elc \
integrations/emacsvox-google.elc \
emacsvox-gridtext.elc \
integrations/emacsvox-gud.elc \
integrations/emacsvox-haskell.elc \
integrations/emacsvox-helm.elc \
integrations/emacsvox-helpful.elc \
integrations/emacsvox-hide-lines.elc  \
emacsvox-hide.elc \
integrations/emacsvox-hideshow.elc \
integrations/emacsvox-hydra.elc \
integrations/emacsvox-ibuffer.elc \
integrations/emacsvox-ido.elc \
integrations/emacsvox-iedit.elc \
integrations/emacsvox-info.elc\
integrations/emacsvox-ispell.elc \
integrations/emacsvox-ivy.elc \
integrations/emacsvox-journalctl.elc \
integrations/emacsvox-js2.elc \
integrations/emacsvox-kmacro.elc  \
integrations/emacsvox-librivox.elc \
integrations/emacsvox-lispy.elc \
integrations/emacsvox-lua.elc \
integrations/emacsvox-m-player.elc \
integrations/emacsvox-magit.elc \
integrations/emacsvox-make-mode.elc \
integrations/emacsvox-man.elc \
integrations/emacsvox-marginalia.elc \
integrations/emacsvox-markdown.elc \
integrations/emacsvox-maths.elc \
integrations/emacsvox-message.elc \
integrations/emacsvox-mines.elc \
integrations/emacsvox-mu4e.elc \
integrations/emacsvox-multiple-cursors.elc \
emacsvox-muggles-core.elc \
emacsvox-muggles-ui.elc \
integrations/emacsvox-net-utils.elc \
integrations/emacsvox-newsticker.elc \
integrations/emacsvox-notmuch.elc \
integrations/emacsvox-nov.elc \
integrations/emacsvox-nxml.elc \
integrations/emacsvox-ocr.elc \
integrations/emacsvox-org.elc \
integrations/emacsvox-org-srs.elc \
integrations/emacsvox-orgalist.elc \
integrations/emacsvox-outline.elc \
integrations/emacsvox-package.elc \
integrations/emacsvox-perl.elc \
integrations/emacsvox-pipewire.elc \
integrations/emacsvox-popup.elc \
integrations/emacsvox-proced.elc \
integrations/emacsvox-project.elc \
integrations/emacsvox-projectile.elc \
integrations/emacsvox-py.elc \
integrations/emacsvox-pydoc.elc \
integrations/emacsvox-python.elc \
integrations/emacsvox-racket.elc \
integrations/emacsvox-re-builder.elc \
integrations/emacsvox-reftex.elc \
integrations/emacsvox-related.elc \
integrations/emacsvox-rg.elc \
integrations/emacsvox-rmail.elc \
integrations/emacsvox-rpm-spec.elc \
integrations/emacsvox-rst.elc \
integrations/emacsvox-ruby.elc \
integrations/emacsvox-rust-mode.elc \
integrations/emacsvox-sage.elc \
integrations/emacsvox-sdcv.elc \
integrations/emacsvox-ses.elc \
integrations/emacsvox-sgml-mode.elc \
integrations/emacsvox-sh-script.elc \
integrations/emacsvox-shr.elc \
integrations/emacsvox-slime.elc \
integrations/emacsvox-smartparens.elc \
integrations/emacsvox-solitaire.elc \
integrations/emacsvox-speedbar.elc \
integrations/emacsvox-sql.elc \
integrations/emacsvox-sudoku.elc \
integrations/emacsvox-supercite.elc \
integrations/emacsvox-syslog.elc \
integrations/emacsvox-tab-bar.elc \
emacsvox-table-reader.elc \
emacsvox-table-settings.elc \
emacsvox-table-ui.elc \
emacsvox-table.elc \
emacsvox-tabulate.elc \
integrations/emacsvox-tabulated-list.elc \
integrations/emacsvox-tar.elc \
integrations/emacsvox-tcl.elc \
integrations/emacsvox-tempo.elc \
integrations/emacsvox-tetris.elc \
integrations/emacsvox-texinfo.elc \
integrations/emacsvox-todo-mode.elc \
integrations/emacsvox-transient.elc \
integrations/emacsvox-treesit.elc \
integrations/emacsvox-typo.elc \
integrations/emacsvox-url-template.elc \
integrations/emacsvox-vdiff.elc \
integrations/emacsvox-vertico.elc \
integrations/emacsvox-view.elc \
integrations/emacsvox-vterm.elc \
integrations/emacsvox-wdired.elc \
integrations/emacsvox-we.elc \
integrations/emacsvox-websearch.elc \
integrations/emacsvox-webspace.elc \
integrations/emacsvox-widget.elc \
integrations/emacsvox-which-key.elc \
integrations/emacsvox-windmove.elc \
emacsvox-windows-speech.elc \
emacsvox-wizards.elc  \
integrations/emacsvox-woman.elc \
integrations/emacsvox-xkcd.elc \
integrations/emacsvox-xref.elc \
emacsvox-xslt.elc \
integrations/emacsvox-yaml.elc \
integrations/emacsvox-yasnippet.elc \
integrations/ladspa.elc \
soundscape.elc \
sox-gen.elc \
integrations/sox.elc

ADDON_OBJECTS = \
integrations/emacsvox-nm.elc  dom-addons.elc integrations/light.elc pip.elc  \
integrations/xbacklight.elc   integrations/tetris.elc   \
integrations/omaps.elc g-utils.elc gweb.elc integrations/gmaps.elc integrations/gm-nnir.elc

OBJECTS = $(TTS_OBJECTS) $(SPEAK_OBJECTS) $(CORE_OBJECTS)  $(ADDON_OBJECTS)

###   User level targets all

.PHONY: all aural documentation-modules config
all: $(OBJECTS)

# Canonical compiled-module inventory consumed by the generated reference.
documentation-modules:
	@for module in $(OBJECTS); do printf '%s\n' "$$module"; done | \
		LC_ALL=C sort -u

aural: $(AURAL_RUNTIME_OBJECTS) emacsvox-keymap.elc \
$(AURAL_OBJECTS) emacsvox.elc emacsvox-setup.elc

integrations/emacsvox-bookshare.elc integrations/emacsvox-epub.elc integrations/emacsvox-eww.elc integrations/emacsvox-librivox.elc: dom-addons.elc

emacsvox-preamble.elc: emacsvox-version.elc emacsvox-paths.elc

integrations/emacsvox-agent-shell.elc: integrations/emacsvox-agent-shell-render.elc emacsvox-table-reader.elc
integrations/emacsvox-markdown.elc integrations/emacsvox-org.elc: emacsvox-table-reader.elc

integrations/emacsvox-eat-input.elc: integrations/emacsvox-eat-core.elc
integrations/emacsvox-eat-review.elc: integrations/emacsvox-eat-core.elc integrations/emacsvox-eat-input.elc
integrations/emacsvox-eat.elc: \
integrations/emacsvox-eat-core.elc integrations/emacsvox-eat-input.elc integrations/emacsvox-eat-review.elc

emacsvox-aural-spatial.elc: emacsvox-aural.elc
emacsvox-aural-rules.elc: emacsvox-aural.elc emacsvox-aural-spatial.elc
emacsvox-aural-resources.elc: emacsvox-aural.elc emacsvox-aural-rules.elc
emacsvox-aural-schemes.elc: emacsvox-aural-resources.elc
emacsvox-aural-routing-profiles.elc: emacsvox-aural.elc
emacsvox-aural-voice-data.elc: emacsvox-aural-resources.elc emacsvox-aural-routing-profiles.elc
emacsvox-aural-voice-runtime.elc: emacsvox-aural-voice-data.elc emacsvox-aural-schemes.elc
emacsvox-aural-voice-drafts.elc: emacsvox-aural-voice-runtime.elc
emacsvox-aural-voice-editing.elc: emacsvox-aural-voice-drafts.elc emacsvox-aural-compiler.elc
emacsvox-aural-voice-editor.elc: emacsvox-aural-voice-editing.elc emacsvox-aural-voice-workbench.elc
emacsvox-aural-voice-menu.elc: emacsvox-aural-voice-editor.elc emacsvox-aural-menu.elc
emacsvox-capitalization.elc: emacsvox-aural-menu.elc emacsvox-aural-editor.elc emacsvox-tone-editor.elc
emacsvox-settings-changes.elc: emacsvox-aural-menu.elc emacsvox-aural-home.elc
emacsvox-settings-integrations.elc: emacsvox-settings.elc
emacsvox-settings-workflows.elc: emacsvox-aural-menu.elc
emacsvox-table-settings.elc: emacsvox-table-reader.elc emacsvox-aural-menu.elc emacsvox-aural-preview.elc
emacsvox-settings.elc: emacsvox-aural-menu.elc
emacsvox-output-settings.elc: emacsvox-aural-menu.elc emacsvox-aural-spatial.elc emacsvox-aural-preview.elc
emacsvox-line-cues.elc: emacsvox-tone-editor.elc emacsvox-aural-menu.elc emacsvox-aural-editor.elc emacsvox-aural-preview.elc emacsvox-aural-tools.elc
emacsvox-interaction.elc: emacsvox-aural-menu.elc
emacsvox-tone-editor.elc: emacsvox-aural-menu.elc
emacsvox-spelling.elc: emacsvox-aural-menu.elc integrations/emacsvox-flyspell.elc emacsvox-tone-editor.elc
emacsvox-aural-voice-bulk.elc: emacsvox-aural-voice-editor.elc
emacsvox-aural-voice-engine-controls.elc: emacsvox-aural-voice-editor.elc omnivox-parameters.elc
emacsvox-aural-voice-context.elc: emacsvox-aural-voice-editor.elc emacsvox-aural-editor.elc emacsvox-aural-tools.elc
omnivox-choice-codec.elc: emacsvox-aural-rules.elc emacsvox-aural-routing-profiles.elc
omnivox-parameters-codec.elc: omnivox-choice-codec.elc
omnivox-parameters.elc: omnivox-parameters-codec.elc omnivox-native-codec.elc tts-queue-state.elc
omnivox-native-codec.elc: omnivox-parameters-codec.elc
omnivox-preview.elc: tts-queue-state.elc omnivox-choice-codec.elc omnivox-native-codec.elc
omnivox-voices.elc: voice-defs.elc emacsvox-aural-voice-runtime.elc omnivox-choice-codec.elc omnivox-preview.elc omnivox-parameters.elc
emacsvox-aural-profile-service.elc: \
emacsvox-aural-schemes.elc emacsvox-aural-spatial.elc
emacsvox-aural-compatibility-voice.elc: emacsvox-aural.elc
emacsvox-aural-history.elc: \
emacsvox-aural.elc emacsvox-aural-concrete.elc
emacsvox-aural-providers.elc: emacsvox-aural-schemes.elc
emacsvox-aural-compiler.elc: \
emacsvox-aural-voice-runtime.elc \
emacsvox-aural-concrete.elc emacsvox-aural-providers.elc \
emacsvox-aural-schemes.elc emacsvox-aural-spatial.elc
emacsvox-aural-source.elc: \
emacsvox-emoji.elc emacsvox-aural-history.elc emacsvox-aural-schemes.elc
emacsvox-aural-planner.elc: \
emacsvox-aural-compiler.elc emacsvox-aural-concrete.elc \
emacsvox-aural-schemes.elc emacsvox-aural-source.elc
emacsvox-aural-transport.elc: \
emacsvox-aural-compiler.elc emacsvox-aural-concrete.elc \
emacsvox-aural-history.elc emacsvox-aural-planner.elc \
emacsvox-aural-schemes.elc emacsvox-aural-source.elc
emacsvox-aural-submission.elc: \
emacsvox-aural-concrete.elc emacsvox-aural-planner.elc \
emacsvox-aural-source.elc
tts-speak.elc: emacsvox-aural-transport.elc
voice-setup.elc: \
tts-speak.elc emacsvox-aural-compatibility-voice.elc
voice-defs.elc: voice-setup.elc
dectalk-voices.elc plain-voices.elc espeak-voices.elc \
outloud-voices.elc mac-voices.elc swiftmac-voices.elc: voice-defs.elc
emacsvox-speak.elc: \
tts-speak.elc voice-setup.elc voice-defs.elc emacsvox-pronounce.elc \
emacsvox-aural-submission.elc emacsvox-version.elc
emacsvox-aural-description.elc: \
emacsvox-aural-concrete.elc emacsvox-aural-rules.elc
emacsvox-aural-preview.elc: emacsvox-aural-transport.elc
emacsvox-aural-replay.elc: emacsvox-aural-preview.elc tts-speak.elc omnivox-voices.elc
emacsvox-aural-validation.elc: emacsvox-aural-transport.elc
emacsvox-aural-inspection.elc: \
emacsvox-aural-concrete.elc emacsvox-aural-rules.elc \
emacsvox-aural-source.elc emacsvox-aural-ui.elc
emacsvox-aural-semantics.elc: \
emacsvox-aural-schemes.elc emacsvox-aural-ui.elc \
emacsvox-aural-inspection.elc emacsvox-aural-description.elc \
emacsvox-aural-validation.elc
emacsvox-aural-explanation.elc: \
emacsvox-aural-ui.elc emacsvox-aural-transport.elc \
emacsvox-aural-description.elc emacsvox-aural-validation.elc \
emacsvox-aural-inspection.elc emacsvox-aural-semantics.elc
emacsvox-aural-tools.elc: \
emacsvox-aural-schemes.elc emacsvox-aural-transport.elc \
emacsvox-aural-description.elc emacsvox-aural-preview.elc \
emacsvox-aural-inspection.elc emacsvox-aural-semantics.elc \
emacsvox-aural-explanation.elc
emacsvox-aural-recent-feedback.elc: \
emacsvox-aural-tools.elc emacsvox-aural-explanation.elc
emacsvox-aural-feedback-details.elc: \
emacsvox-aural-recent-feedback.elc emacsvox-aural-planner.elc
emacsvox-aural-change-feedback.elc: emacsvox-aural-feedback-details.elc
emacsvox-aural-feature-fragments.elc: \
emacsvox-aural-schemes.elc emacsvox-aural-ui.elc \
emacsvox-aural-inspection.elc emacsvox-aural-preview.elc \
emacsvox-aural-validation.elc emacsvox-aural-description.elc
emacsvox-omnivox-components.elc: \
emacsvox-aural-ui.elc emacsvox-aural-inspection.elc
emacsvox-aural-home.elc: \
emacsvox-aural-tools.elc emacsvox-aural-explanation.elc \
emacsvox-aural-recent-feedback.elc \
emacsvox-aural-feature-fragments.elc \
emacsvox-aural-compatibility-voice.elc
emacsvox-aural-editor.elc: \
emacsvox-aural-semantics.elc emacsvox-aural-explanation.elc \
emacsvox-aural-feature-fragments.elc emacsvox-aural-preview.elc
emacsvox-aural-overrides.elc: \
emacsvox-aural-schemes.elc emacsvox-aural-ui.elc \
emacsvox-aural-inspection.elc emacsvox-aural-preview.elc \
emacsvox-aural-validation.elc emacsvox-aural-description.elc \
emacsvox-aural-editor.elc
emacsvox-aural-doctor.elc: \
emacsvox-aural-ui.elc emacsvox-aural-explanation.elc \
emacsvox-aural-profile-service.elc
emacsvox-aural-profiles.elc: \
emacsvox-aural-schemes.elc emacsvox-aural-ui.elc \
emacsvox-aural-inspection.elc emacsvox-aural-description.elc \
emacsvox-aural-profile-service.elc
emacsvox-aural-voice-palettes.elc: \
emacsvox-aural-voice-editing.elc \
emacsvox-aural-schemes.elc emacsvox-aural-ui.elc \
emacsvox-aural-inspection.elc emacsvox-aural-description.elc \
emacsvox-aural-preview.elc
emacsvox-aural-voice-workbench.elc: \
emacsvox-aural-resources.elc emacsvox-aural-schemes.elc \
emacsvox-aural-routing-profiles.elc emacsvox-aural-ui.elc \
emacsvox-aural-voice-palettes.elc
emacsvox-aural-provider-org.elc: emacsvox-aural-schemes.elc
emacsvox-aural-provider-workflows.elc: emacsvox-aural-schemes.elc
emacsvox-aural-provider-org-srs.elc: emacsvox-aural-provider-workflows.elc
emacsvox-aural-provider-markdown.elc: emacsvox-aural-provider-workflows.elc
emacsvox-aural-provider-notmuch.elc: emacsvox-aural-provider-workflows.elc
integrations/emacsvox-org-srs.elc: emacsvox-aural-provider-org-srs.elc
emacsvox-sounds.elc: emacsvox-aural-resources.elc emacsvox-aural-transport.elc
emacsvox-sound-library.elc: emacsvox-aural-sound-packs.elc
emacsvox-aural-sound-packs.elc: \
emacsvox-aural-ui.elc emacsvox-aural-inspection.elc \
emacsvox-aural-description.elc \
emacsvox-aural-preview.elc emacsvox-sounds.elc
emacsvox.elc: \
emacsvox-version.elc emacsvox-preamble.elc emacsvox-keymap.elc $(AURAL_OBJECTS)
emacsvox-setup.elc: emacsvox-preamble.elc emacsvox.elc

muggles: emacsvox-muggles.elc
muggle-org-navigation: integrations/emacsvox-muggle-org-navigation.elc
extra-muggles.elc: emacsvox-muggles-core.elc integrations/emacsvox-muggle-org-navigation.elc
extra-muggles: extra-muggles.elc
maths: integrations/emacsvox-maths.elc

lint:
	$(EMACS) $(BATCH) $(DEPS) --eval \
	  '(progn (require (quote elint)) (dolist (file (emacsvox-paths--files default-directory ".el")) (elint-file file)))'

### build time target --loaddefs

# Configuration always rescans the source inventory, including removed files.
emacsvox-loaddefs.el: config

config:
	@$(EMACS) $(BATCH)  -l ./emacsvox-preamble.el  \
	-l ./emacsvox-autoload.el  \
	--eval '(emacsvox-paths--validate-modules default-directory (split-string "$(OBJECTS)"))' \
	-f emacsvox-auto-generate-autoloads

# Read only declared source directories; relative names contain no shell syntax.
LISP_SOURCES = $(shell $(EMACS) -Q --batch -l ./emacsvox-paths.el --eval '(progn (emacsvox-paths--check-sources default-directory) (dolist (file (emacsvox-paths--files default-directory ".el")) (princ (concat (file-relative-name file default-directory) " "))))')

### Development  target: indent, tags, relint
indent:
	$(EMACS) -batch -q -no-site-file -l ../utils/indent-files.el

#identify long lines:
ll:
	wc -L $(LISP_SOURCES) | sort -n

list-execs:
	grep executable-find $(LISP_SOURCES) | cut -d '"' -f 2 | sort  | uniq
spell:
	codespell -I .codespell $(LISP_SOURCES)
elint:
	$(EMACS) -batch -q -no-site-file -l ../utils/elint-files.el

relint:
	$(EMACS) -batch -f package-initialize -l relint.el -f relint-batch $(LISP_SOURCES)

tags:
	etags $(LISP_SOURCES)

###   user level target-- clean

clean:
	@$(EMACS) -Q --batch -l ./emacsvox-paths.el \
	  --eval '(emacsvox-paths--clean-bytecode default-directory)'
	@rm -f emacsvox-loaddefs.el


# Queue descriptors and records must precede compiled consumers.
omnivox-remote.elc omnivox-voices.elc emacsvox-aural-transport.elc tts-speak.elc: tts-queue-state.elc

###  end of file

#local variables:
#mode: makefile
#fill-column: 90
#outline-regexp: "^### "
#end:

# EWW shares HTML link feedback with mail and other SHR clients.
integrations/emacsvox-eww.elc: integrations/emacsvox-shr.elc
