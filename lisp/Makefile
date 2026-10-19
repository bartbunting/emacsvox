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
speech/voice-setup.elc \
voices/voice-defs.elc \
speech/dectalk-voices.elc \
speech/plain-voices.elc \
speech/espeak-voices.elc \
speech/outloud-voices.elc \
speech/mac-voices.elc \
speech/swiftmac-voices.elc \
speech/omnivox-control-codec.elc \
speech/omnivox-choice-codec.elc \
speech/omnivox-parameters-codec.elc \
speech/omnivox-parameters.elc \
speech/omnivox-native-codec.elc \
speech/omnivox-library-apply.elc \
speech/omnivox-library-runtime.elc \
ui/omnivox-library.elc \
ui/omnivox-catalogue.elc \
speech/omnivox-preview.elc \
speech/omnivox-inventory.elc \
speech/omnivox-discovery.elc \
speech/omnivox-voices.elc

TTS_OBJECTS = \
emacsvox-version.elc \
emacsvox-paths.elc \
emacsvox-preamble.elc \
speech/tts-queue-state.elc \
speech/omnivox-remote.elc \
speech/omnivox-engine-settings.elc \
ui/omnivox-engine-configuration.elc \
ui/omnivox-punctuation.elc \
speech/omnivox-punctuation-profiles.elc \
ui/omnivox-espeak-variants.elc \
speech/tts-lifecycle.elc \
speech/tts-voice-api.elc \
speech/tts-speak.elc \
$(VOICE_OBJECTS)

AURAL_RUNTIME_OBJECTS = \
$(TTS_OBJECTS) \
core/emacsvox-pronounce.elc \
core/emacsvox-tracked-reading.elc \
core/emacsvox-speak-characters.elc \
core/emacsvox-speak-filters.elc \
core/emacsvox-speak.elc

AURAL_OBJECTS = \
aural/emacsvox-aural.elc \
aural/emacsvox-aural-concrete.elc \
aural/emacsvox-aural-history.elc \
aural/emacsvox-aural-spatial.elc \
aural/emacsvox-aural-rules.elc \
aural/emacsvox-aural-resources.elc \
aural/emacsvox-aural-schemes.elc \
aural/emacsvox-aural-routing-profiles.elc \
voices/emacsvox-aural-voice-data.elc \
voices/emacsvox-aural-voice-runtime.elc \
voices/emacsvox-aural-voice-drafts.elc \
voices/emacsvox-aural-voice-editing.elc \
ui/emacsvox-aural-voice-editor.elc \
ui/emacsvox-aural-voice-menu.elc \
ui/emacsvox-capitalization.elc \
ui/emacsvox-interaction.elc \
ui/emacsvox-spelling.elc \
ui/emacsvox-tone-editor.elc \
ui/emacsvox-line-cues.elc \
ui/emacsvox-output-settings.elc \
ui/emacsvox-settings.elc \
ui/emacsvox-settings-workflows.elc \
ui/emacsvox-settings-integrations.elc \
ui/emacsvox-settings-changes.elc \
ui/emacsvox-aural-voice-bulk.elc \
ui/emacsvox-aural-voice-engine-controls.elc \
ui/emacsvox-aural-voice-context.elc \
aural/emacsvox-aural-profile-service.elc \
aural/emacsvox-aural-compatibility-voice.elc \
aural/emacsvox-aural-providers.elc \
aural/emacsvox-aural-compiler.elc \
core/emacsvox-emoji.elc \
aural/emacsvox-aural-source.elc \
aural/emacsvox-aural-planner.elc \
aural/emacsvox-aural-submission.elc \
aural/emacsvox-aural-timeline-codec.elc \
aural/emacsvox-aural-transport.elc \
aural/emacsvox-aural-description.elc \
aural/emacsvox-aural-preview.elc \
aural/emacsvox-aural-replay.elc \
aural/emacsvox-aural-validation.elc \
ui/emacsvox-aural-ui.elc \
aural/emacsvox-aural-inspection.elc \
ui/emacsvox-aural-semantics.elc \
aural/emacsvox-aural-explanation.elc \
aural/emacsvox-aural-tools.elc \
ui/emacsvox-aural-recent-feedback.elc \
ui/emacsvox-aural-feedback-details.elc \
ui/emacsvox-aural-feature-fragments.elc \
ui/emacsvox-omnivox-components.elc \
ui/emacsvox-aural-home.elc \
ui/emacsvox-aural-editor.elc \
ui/emacsvox-aural-overrides.elc \
ui/emacsvox-aural-doctor.elc \
ui/emacsvox-aural-profiles.elc \
ui/emacsvox-aural-voice-palettes.elc \
ui/emacsvox-aural-voice-workbench-views.elc \
ui/emacsvox-aural-voice-workbench.elc \
ui/emacsvox-aural-change-feedback.elc \
aural/emacsvox-aural-provider-org.elc \
aural/emacsvox-aural-provider-workflows.elc \
aural/emacsvox-aural-provider-org-srs.elc \
aural/emacsvox-aural-provider-markdown.elc \
aural/emacsvox-aural-provider-notmuch.elc \
aural/emacsvox-sounds.elc \
ui/emacsvox-aural-sound-packs.elc \
ui/emacsvox-sound-library.elc

SPEAK_OBJECTS =   \
core/emacsvox-pronounce.elc \
core/emacsvox-tracked-reading.elc \
core/emacsvox-speak-characters.elc \
core/emacsvox-speak-filters.elc \
core/emacsvox-speak.elc  \
core/emacsvox-advice-completion.elc \
core/emacsvox-advice-input.elc \
core/emacsvox-advice-messages.elc \
core/emacsvox-advice.elc\
core/emacsvox-keymap.elc\
ui/emacsvox-indentation.elc\
ui/emacsvox-aural-menu.elc\
ui/emacsvox-welcome.elc\
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
integrations/emacsvox-agent-shell-tables.elc \
integrations/emacsvox-agent-shell-navigation.elc \
integrations/emacsvox-agent-shell-events.elc \
integrations/emacsvox-agent-shell-interaction.elc \
integrations/emacsvox-agent-shell-presentation.elc \
integrations/emacsvox-agent-shell-motion.elc \
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
core/emacsvox-extras.elc \
integrations/emacsvox-exwm.elc \
integrations/emacsvox-feeds.elc \
integrations/emacsvox-ffap.elc \
integrations/emacsvox-ffip.elc \
core/emacsvox-filtertext.elc \
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
core/emacsvox-gridtext.elc \
integrations/emacsvox-gud.elc \
integrations/emacsvox-haskell.elc \
integrations/emacsvox-helm.elc \
integrations/emacsvox-helpful.elc \
integrations/emacsvox-hide-lines.elc  \
core/emacsvox-hide.elc \
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
core/emacsvox-muggles-core.elc \
ui/emacsvox-muggles-ui.elc \
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
core/emacsvox-table-reader.elc \
ui/emacsvox-table-settings.elc \
core/emacsvox-table-ui.elc \
core/emacsvox-table.elc \
core/emacsvox-tabulate.elc \
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
speech/emacsvox-windows-speech.elc \
core/emacsvox-wizards.elc  \
integrations/emacsvox-woman.elc \
integrations/emacsvox-xkcd.elc \
integrations/emacsvox-xref.elc \
core/emacsvox-xslt.elc \
integrations/emacsvox-yaml.elc \
integrations/emacsvox-yasnippet.elc \
integrations/ladspa.elc \
aural/soundscape.elc \
aural/sox-gen.elc \
integrations/sox.elc

ADDON_OBJECTS = \
integrations/emacsvox-nm.elc  core/dom-addons.elc integrations/light.elc speech/pip.elc  \
integrations/xbacklight.elc   integrations/tetris.elc   \
integrations/omaps.elc core/g-utils.elc core/gweb.elc integrations/gmaps.elc integrations/gm-nnir.elc

OBJECTS = $(TTS_OBJECTS) $(SPEAK_OBJECTS) $(CORE_OBJECTS)  $(ADDON_OBJECTS)

###   User level targets all

.PHONY: all aural documentation-modules config
all: $(OBJECTS)

# Canonical compiled-module inventory consumed by the generated reference.
documentation-modules:
	@for module in $(OBJECTS); do printf '%s\n' "$$module"; done | \
		LC_ALL=C sort -u

aural: $(AURAL_RUNTIME_OBJECTS) core/emacsvox-keymap.elc \
$(AURAL_OBJECTS) emacsvox.elc emacsvox-setup.elc

integrations/emacsvox-bookshare.elc integrations/emacsvox-epub.elc integrations/emacsvox-eww.elc integrations/emacsvox-librivox.elc: core/dom-addons.elc

emacsvox-preamble.elc: emacsvox-version.elc emacsvox-paths.elc

integrations/emacsvox-agent-shell-tables.elc: integrations/emacsvox-agent-shell-render.elc core/emacsvox-table-reader.elc
integrations/emacsvox-agent-shell-navigation.elc: integrations/emacsvox-agent-shell-tables.elc integrations/emacsvox-agent-shell-render.elc
integrations/emacsvox-agent-shell-events.elc: integrations/emacsvox-agent-shell-navigation.elc
integrations/emacsvox-agent-shell-interaction.elc: integrations/emacsvox-agent-shell-events.elc
integrations/emacsvox-agent-shell-presentation.elc: integrations/emacsvox-agent-shell-events.elc
integrations/emacsvox-agent-shell-motion.elc: \
integrations/emacsvox-agent-shell-presentation.elc integrations/emacsvox-agent-shell-navigation.elc
integrations/emacsvox-agent-shell.elc: \
integrations/emacsvox-agent-shell-motion.elc integrations/emacsvox-agent-shell-presentation.elc \
integrations/emacsvox-agent-shell-interaction.elc integrations/emacsvox-agent-shell-events.elc \
integrations/emacsvox-agent-shell-tables.elc integrations/emacsvox-agent-shell-navigation.elc
integrations/emacsvox-markdown.elc integrations/emacsvox-org.elc: core/emacsvox-table-reader.elc

integrations/emacsvox-eat-input.elc: integrations/emacsvox-eat-core.elc
integrations/emacsvox-eat-review.elc: integrations/emacsvox-eat-core.elc integrations/emacsvox-eat-input.elc
integrations/emacsvox-eat.elc: \
integrations/emacsvox-eat-core.elc integrations/emacsvox-eat-input.elc integrations/emacsvox-eat-review.elc

aural/emacsvox-aural-spatial.elc: aural/emacsvox-aural.elc
aural/emacsvox-aural-rules.elc: aural/emacsvox-aural.elc aural/emacsvox-aural-spatial.elc
aural/emacsvox-aural-resources.elc: aural/emacsvox-aural.elc aural/emacsvox-aural-rules.elc
aural/emacsvox-aural-schemes.elc: aural/emacsvox-aural-resources.elc
aural/emacsvox-aural-routing-profiles.elc: aural/emacsvox-aural.elc
voices/emacsvox-aural-voice-data.elc: aural/emacsvox-aural-resources.elc aural/emacsvox-aural-routing-profiles.elc
voices/emacsvox-aural-voice-runtime.elc: voices/emacsvox-aural-voice-data.elc aural/emacsvox-aural-schemes.elc
voices/emacsvox-aural-voice-drafts.elc: voices/emacsvox-aural-voice-runtime.elc
voices/emacsvox-aural-voice-editing.elc: voices/emacsvox-aural-voice-drafts.elc aural/emacsvox-aural-compiler.elc
ui/emacsvox-aural-voice-editor.elc: voices/emacsvox-aural-voice-editing.elc ui/emacsvox-aural-voice-workbench.elc
ui/emacsvox-aural-voice-menu.elc: ui/emacsvox-aural-voice-editor.elc ui/emacsvox-aural-menu.elc
ui/emacsvox-capitalization.elc: ui/emacsvox-aural-menu.elc ui/emacsvox-aural-editor.elc ui/emacsvox-tone-editor.elc
ui/emacsvox-settings-changes.elc: ui/emacsvox-aural-menu.elc ui/emacsvox-aural-home.elc
ui/emacsvox-settings-integrations.elc: ui/emacsvox-settings.elc
ui/emacsvox-settings-workflows.elc: ui/emacsvox-aural-menu.elc
ui/emacsvox-table-settings.elc: core/emacsvox-table-reader.elc ui/emacsvox-aural-menu.elc aural/emacsvox-aural-preview.elc
ui/emacsvox-settings.elc: ui/emacsvox-aural-menu.elc
ui/emacsvox-output-settings.elc: ui/emacsvox-aural-menu.elc aural/emacsvox-aural-spatial.elc aural/emacsvox-aural-preview.elc
ui/emacsvox-line-cues.elc: ui/emacsvox-tone-editor.elc ui/emacsvox-aural-menu.elc ui/emacsvox-aural-editor.elc aural/emacsvox-aural-preview.elc aural/emacsvox-aural-tools.elc
ui/emacsvox-interaction.elc: ui/emacsvox-aural-menu.elc
ui/emacsvox-tone-editor.elc: ui/emacsvox-aural-menu.elc
ui/emacsvox-spelling.elc: ui/emacsvox-aural-menu.elc integrations/emacsvox-flyspell.elc ui/emacsvox-tone-editor.elc
ui/emacsvox-aural-voice-bulk.elc: ui/emacsvox-aural-voice-editor.elc
ui/emacsvox-aural-voice-engine-controls.elc: ui/emacsvox-aural-voice-editor.elc speech/omnivox-parameters.elc
ui/emacsvox-aural-voice-context.elc: ui/emacsvox-aural-voice-editor.elc ui/emacsvox-aural-editor.elc aural/emacsvox-aural-tools.elc
speech/omnivox-choice-codec.elc: speech/omnivox-control-codec.elc aural/emacsvox-aural-rules.elc aural/emacsvox-aural-routing-profiles.elc
speech/omnivox-parameters-codec.elc: speech/omnivox-choice-codec.elc
speech/omnivox-parameters.elc: speech/omnivox-parameters-codec.elc speech/omnivox-native-codec.elc speech/tts-queue-state.elc
speech/omnivox-native-codec.elc: speech/omnivox-parameters-codec.elc
speech/omnivox-preview.elc: speech/omnivox-control-codec.elc speech/tts-queue-state.elc speech/omnivox-choice-codec.elc speech/omnivox-native-codec.elc
speech/omnivox-inventory.elc: speech/omnivox-control-codec.elc
speech/omnivox-discovery.elc: speech/omnivox-inventory.elc
speech/omnivox-voices.elc: speech/omnivox-discovery.elc speech/omnivox-control-codec.elc voices/voice-defs.elc voices/emacsvox-aural-voice-runtime.elc speech/omnivox-choice-codec.elc speech/omnivox-preview.elc speech/omnivox-parameters.elc
aural/emacsvox-aural-profile-service.elc: \
aural/emacsvox-aural-schemes.elc aural/emacsvox-aural-spatial.elc
aural/emacsvox-aural-compatibility-voice.elc: aural/emacsvox-aural.elc
aural/emacsvox-aural-history.elc: \
aural/emacsvox-aural.elc aural/emacsvox-aural-concrete.elc
aural/emacsvox-aural-providers.elc: aural/emacsvox-aural-schemes.elc
aural/emacsvox-aural-compiler.elc: \
voices/emacsvox-aural-voice-runtime.elc \
aural/emacsvox-aural-concrete.elc aural/emacsvox-aural-providers.elc \
aural/emacsvox-aural-schemes.elc aural/emacsvox-aural-spatial.elc
aural/emacsvox-aural-source.elc: \
core/emacsvox-emoji.elc aural/emacsvox-aural-history.elc aural/emacsvox-aural-schemes.elc
aural/emacsvox-aural-planner.elc: \
aural/emacsvox-aural-compiler.elc aural/emacsvox-aural-concrete.elc \
aural/emacsvox-aural-schemes.elc aural/emacsvox-aural-source.elc
aural/emacsvox-aural-timeline-codec.elc: aural/emacsvox-aural-concrete.elc speech/omnivox-choice-codec.elc
aural/emacsvox-aural-transport.elc: \
aural/emacsvox-aural-timeline-codec.elc \
aural/emacsvox-aural-compiler.elc aural/emacsvox-aural-concrete.elc \
aural/emacsvox-aural-history.elc aural/emacsvox-aural-planner.elc \
aural/emacsvox-aural-schemes.elc aural/emacsvox-aural-source.elc
aural/emacsvox-aural-submission.elc: \
aural/emacsvox-aural-concrete.elc aural/emacsvox-aural-planner.elc \
aural/emacsvox-aural-source.elc
speech/tts-lifecycle.elc: aural/emacsvox-aural-transport.elc speech/tts-queue-state.elc
speech/tts-speak.elc: speech/tts-voice-api.elc speech/tts-lifecycle.elc aural/emacsvox-aural-transport.elc
speech/voice-setup.elc: \
speech/tts-speak.elc aural/emacsvox-aural-compatibility-voice.elc
voices/voice-defs.elc: speech/voice-setup.elc
speech/dectalk-voices.elc speech/plain-voices.elc speech/espeak-voices.elc \
speech/outloud-voices.elc speech/mac-voices.elc speech/swiftmac-voices.elc: voices/voice-defs.elc
core/emacsvox-advice-completion.elc core/emacsvox-advice-input.elc \
core/emacsvox-advice-messages.elc: emacsvox-preamble.elc
core/emacsvox-advice-messages.elc: aural/emacsvox-aural-submission.elc
core/emacsvox-advice.elc: core/emacsvox-advice-completion.elc \
core/emacsvox-advice-input.elc core/emacsvox-advice-messages.elc
core/emacsvox-speak-characters.elc: speech/tts-speak.elc
core/emacsvox-speak-filters.elc: speech/tts-speak.elc
core/emacsvox-speak.elc: core/emacsvox-speak-characters.elc core/emacsvox-tracked-reading.elc core/emacsvox-speak-filters.elc \
speech/tts-speak.elc speech/voice-setup.elc voices/voice-defs.elc core/emacsvox-pronounce.elc \
aural/emacsvox-aural-submission.elc emacsvox-version.elc
aural/emacsvox-aural-description.elc: \
aural/emacsvox-aural-concrete.elc aural/emacsvox-aural-rules.elc
aural/emacsvox-aural-preview.elc: aural/emacsvox-aural-transport.elc
aural/emacsvox-aural-replay.elc: aural/emacsvox-aural-preview.elc speech/tts-speak.elc speech/omnivox-voices.elc
aural/emacsvox-aural-validation.elc: aural/emacsvox-aural-transport.elc
aural/emacsvox-aural-inspection.elc: \
aural/emacsvox-aural-concrete.elc aural/emacsvox-aural-rules.elc \
aural/emacsvox-aural-source.elc ui/emacsvox-aural-ui.elc
ui/emacsvox-aural-semantics.elc: \
aural/emacsvox-aural-schemes.elc ui/emacsvox-aural-ui.elc \
aural/emacsvox-aural-inspection.elc aural/emacsvox-aural-description.elc \
aural/emacsvox-aural-validation.elc
aural/emacsvox-aural-explanation.elc: \
ui/emacsvox-aural-ui.elc aural/emacsvox-aural-transport.elc \
aural/emacsvox-aural-description.elc aural/emacsvox-aural-validation.elc \
aural/emacsvox-aural-inspection.elc ui/emacsvox-aural-semantics.elc
aural/emacsvox-aural-tools.elc: \
aural/emacsvox-aural-schemes.elc aural/emacsvox-aural-transport.elc \
aural/emacsvox-aural-description.elc aural/emacsvox-aural-preview.elc \
aural/emacsvox-aural-inspection.elc ui/emacsvox-aural-semantics.elc \
aural/emacsvox-aural-explanation.elc
ui/emacsvox-aural-recent-feedback.elc: \
aural/emacsvox-aural-tools.elc aural/emacsvox-aural-explanation.elc
ui/emacsvox-aural-feedback-details.elc: \
ui/emacsvox-aural-recent-feedback.elc aural/emacsvox-aural-planner.elc
ui/emacsvox-aural-change-feedback.elc: ui/emacsvox-aural-feedback-details.elc
ui/emacsvox-aural-feature-fragments.elc: \
aural/emacsvox-aural-schemes.elc ui/emacsvox-aural-ui.elc \
aural/emacsvox-aural-inspection.elc aural/emacsvox-aural-preview.elc \
aural/emacsvox-aural-validation.elc aural/emacsvox-aural-description.elc
ui/emacsvox-omnivox-components.elc: \
ui/emacsvox-aural-ui.elc aural/emacsvox-aural-inspection.elc
ui/emacsvox-aural-home.elc: \
aural/emacsvox-aural-tools.elc aural/emacsvox-aural-explanation.elc \
ui/emacsvox-aural-recent-feedback.elc \
ui/emacsvox-aural-feature-fragments.elc \
aural/emacsvox-aural-compatibility-voice.elc
ui/emacsvox-aural-editor.elc: \
ui/emacsvox-aural-semantics.elc aural/emacsvox-aural-explanation.elc \
ui/emacsvox-aural-feature-fragments.elc aural/emacsvox-aural-preview.elc
ui/emacsvox-aural-overrides.elc: \
aural/emacsvox-aural-schemes.elc ui/emacsvox-aural-ui.elc \
aural/emacsvox-aural-inspection.elc aural/emacsvox-aural-preview.elc \
aural/emacsvox-aural-validation.elc aural/emacsvox-aural-description.elc \
ui/emacsvox-aural-editor.elc
ui/emacsvox-aural-doctor.elc: \
ui/emacsvox-aural-ui.elc aural/emacsvox-aural-explanation.elc \
aural/emacsvox-aural-profile-service.elc
ui/emacsvox-aural-profiles.elc: \
aural/emacsvox-aural-schemes.elc ui/emacsvox-aural-ui.elc \
aural/emacsvox-aural-inspection.elc aural/emacsvox-aural-description.elc \
aural/emacsvox-aural-profile-service.elc
ui/emacsvox-aural-voice-palettes.elc: \
voices/emacsvox-aural-voice-editing.elc \
aural/emacsvox-aural-schemes.elc ui/emacsvox-aural-ui.elc \
aural/emacsvox-aural-inspection.elc aural/emacsvox-aural-description.elc \
aural/emacsvox-aural-preview.elc
ui/emacsvox-aural-voice-workbench.elc: \
aural/emacsvox-aural-resources.elc aural/emacsvox-aural-schemes.elc \
aural/emacsvox-aural-routing-profiles.elc ui/emacsvox-aural-ui.elc \
ui/emacsvox-aural-voice-palettes.elc
aural/emacsvox-aural-provider-org.elc: aural/emacsvox-aural-schemes.elc
aural/emacsvox-aural-provider-workflows.elc: aural/emacsvox-aural-schemes.elc
aural/emacsvox-aural-provider-org-srs.elc: aural/emacsvox-aural-provider-workflows.elc
aural/emacsvox-aural-provider-markdown.elc: aural/emacsvox-aural-provider-workflows.elc
aural/emacsvox-aural-provider-notmuch.elc: aural/emacsvox-aural-provider-workflows.elc
integrations/emacsvox-org-srs.elc: aural/emacsvox-aural-provider-org-srs.elc
aural/emacsvox-sounds.elc: aural/emacsvox-aural-resources.elc aural/emacsvox-aural-transport.elc
ui/emacsvox-sound-library.elc: ui/emacsvox-aural-sound-packs.elc
ui/emacsvox-aural-sound-packs.elc: \
ui/emacsvox-aural-ui.elc aural/emacsvox-aural-inspection.elc \
aural/emacsvox-aural-description.elc \
aural/emacsvox-aural-preview.elc aural/emacsvox-sounds.elc
emacsvox.elc: \
emacsvox-version.elc emacsvox-preamble.elc core/emacsvox-keymap.elc $(AURAL_OBJECTS)
emacsvox-setup.elc: emacsvox-preamble.elc emacsvox.elc

muggles: ui/emacsvox-muggles.elc
muggle-org-navigation: integrations/emacsvox-muggle-org-navigation.elc
ui/extra-muggles.elc: core/emacsvox-muggles-core.elc integrations/emacsvox-muggle-org-navigation.elc
extra-muggles: ui/extra-muggles.elc
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
speech/omnivox-remote.elc speech/omnivox-voices.elc aural/emacsvox-aural-transport.elc speech/tts-speak.elc: speech/tts-queue-state.elc

###  end of file

#local variables:
#mode: makefile
#fill-column: 90
#outline-regexp: "^### "
#end:

# EWW shares HTML link feedback with mail and other SHR clients.
integrations/emacsvox-eww.elc: integrations/emacsvox-shr.elc

speech/omnivox-library-runtime.elc: speech/tts-queue-state.elc speech/omnivox-engine-settings.elc speech/omnivox-library-apply.elc
ui/omnivox-library.elc speech/tts-speak.elc speech/omnivox-remote.elc: speech/omnivox-library-runtime.elc

ui/emacsvox-aural-voice-workbench-views.elc: ui/emacsvox-aural-voice-palettes.elc ui/emacsvox-aural-ui.elc aural/emacsvox-aural-routing-profiles.elc
ui/emacsvox-aural-voice-workbench.elc: ui/emacsvox-aural-voice-workbench-views.elc
