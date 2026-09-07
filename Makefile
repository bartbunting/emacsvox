# $Author: tv.raman.tv $
# Description:  Makefile for Emacsvox
# Keywords: Emacsvox,  TTS,Makefile
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

###  Configuration
.POSIX:
MAKE=make
MAKEFLAGS=--no-print-directory
-include local.mk
EMACS ?= emacs
MAKEINFO ?= makeinfo
INSTALL_INFO ?= install-info
DOCS_PUBLISH_DIR ?=
DOCS_MANUAL ?= emacsvox
DOCS_PREVIEW_DIR ?= $(CURDIR)/.docs-preview
DOCS_ORG_SOURCE ?= $(CURDIR)/docs/manual/emacsvox.org
DOCS_ORG_BODY ?= $(CURDIR)/info/emacsvox-body.texi
DOCS_ORG_NODES ?= $(CURDIR)/docs/manual/nodes.txt
DOCS_ORG_PREVIEW_DIR ?= $(DOCS_PREVIEW_DIR)/org-manual
DOCS_ORG_HTMLXREF ?= $(CURDIR)/info/htmlxref.cnf
VERSION_FILE ?= $(CURDIR)/VERSION
VERSION = $(shell sed -n '1p' "$(VERSION_FILE)" 2>/dev/null)
DIST_DIR ?= $(CURDIR)/dist
RELEASE_PREFIX = emacsvox-$(VERSION)
RELEASE_ARCHIVE = $(abspath $(DIST_DIR))/$(RELEASE_PREFIX).tar.bz2
RELEASE_CHECKSUM = $(RELEASE_ARCHIVE).sha256
RELEASE_PROVENANCE = $(RELEASE_ARCHIVE).source
RELEASE_REMOTE ?= origin

### Tests

TRACE_GOLDEN=test/golden/emacsvox-core.eld
EMACSPEAK_TRACE_GOLDEN=test/golden/emacspeak-core.eld
TEST_DEPS_DIR ?= $(CURDIR)/.test-deps
TEST_DEPS_CACHE ?= $(CURDIR)/.test-deps-cache

.PHONY: version version-check headers-check test unit-test notmuch-test compiled-notmuch-test
.PHONY: compiled-aural-test build-aural-test trace trace-test compat-test core-test
.PHONY: test-deps test-deps-test integration-test
.PHONY: reference-test advice-audit name-audit tts-audit
.PHONY: check-emacs bytecode bytecode-check bytecode-rebuild generated-reference
.PHONY: docs-preview docs-update docs-reference docs-generate
.PHONY: docs-org-export docs-org-preview docs-org-generate docs-org-check
.PHONY: docs-check docs-release-check docs-check-external
.PHONY: docs-publish docs-publish-pages
.PHONY: aural-audit aural-reference windows-speech windows-audio windows-outloud windows-dtk windows-omnivox
.PHONY: windows-omnivox-dev windows-omnivox-piper-dev windows-omnivox-main-dev
.PHONY: verify-windows-omnivox-toolchain verify-windows-omnivox-helpers prepare-windows-omnivox-piper verify-windows-omnivox-runtime verify-windows-omnivox-live
.PHONY: verify-windows-omnivox-main-live
.PHONY: clean-windows-speech clean-windows-audio clean-windows-outloud clean-windows-dtk clean-windows-omnivox
.PHONY: dist release release-source-check release-check release-artifact
.PHONY: release-artifact-check source-archive-check source-archive-test
.PHONY: release-tag release-publish
.PHONY: deb deb-test release-deb
.PHONY: windows-staging-test

version:
	@cat "$(VERSION_FILE)"

version-check:
	@utils/emacsvox-version-check --check

headers-check:
	@utils/emacsvox-header-check

# Development builds preserve and identify work in progress. Release packages
# require the already checked source archive; neither target tags or publishes.
deb: check-emacs version-check headers-check
	python3 utils/emacsvox-package-deb.py --development --emacs "$(EMACS)" --output-dir "$(DIST_DIR)"

deb-test: check-emacs
	EMACS="$(EMACS)" python3 -m unittest discover -s test -p 'test_package_deb.py' -v

release-deb: check-emacs
	python3 utils/emacsvox-package-deb.py --release --emacs "$(EMACS)" --output-dir "$(DIST_DIR)"

test: version-check headers-check source-archive-test windows-staging-test unit-test compiled-notmuch-test compiled-aural-test build-aural-test trace-test

windows-staging-test:
	python3 -m unittest discover -s test -p 'test_windows_staging.py' -v

compat-test: check-emacs config
	$(EMACS) -Q --batch -l test/run-compat-tests.el

core-test: check-emacs
	$(EMACS) -Q --batch -l test/run-core-tests.el

test-deps: check-emacs
	python3 test/prepare-dependencies.py --emacs "$(EMACS)" \
		--directory "$(TEST_DEPS_DIR)" --cache "$(TEST_DEPS_CACHE)"

test-deps-test: check-emacs
	EMACS="$(EMACS)" python3 -m unittest discover -s test -p 'test_integration_dependencies.py' -v

integration-test: check-emacs
	EMACSVOX_TEST_DEPS_DIR="$(TEST_DEPS_DIR)" \
	$(EMACS) -Q --batch -l test/run-integration-tests.el

unit-test:
	$(EMACS) -Q --batch -l test/run-tests.el

notmuch-test:
	EMACSVOX_NOTMUCH_TEST_LOAD=source \
	$(EMACS) -Q --batch -l test/run-notmuch-tests.el

compiled-notmuch-test: bytecode-check
	EMACSVOX_NOTMUCH_TEST_LOAD=compiled \
	$(EMACS) -Q --batch -l test/run-notmuch-tests.el

check-emacs:
	@$(EMACS) -Q --batch --eval \
		'(unless (version<= "30.2" emacs-version) (error "Emacsvox requires Emacs 30.2 or newer; got %s from %s" emacs-version invocation-directory))'

# Keep ignored in-tree byte-code explicit: ordinary edits can use the
# incremental target, while branch changes should discard every old .elc.
bytecode: check-emacs config
	$(MAKE) -C lisp EMACS="$(EMACS)" all
	$(MAKE) EMACS="$(EMACS)" bytecode-check

bytecode-check: check-emacs
	@set -eu; \
		if ! $(MAKE) -C lisp EMACS="$(EMACS)" --question all; then \
			echo "Emacsvox byte-code is missing or stale; run make bytecode." >&2; \
			exit 1; \
		fi; \
		selected_version="$$($(EMACS) -Q --batch --eval '(princ emacs-version)')"; \
		for compiled in lisp/*.elc; do \
			if [ ! -e "$$compiled" ]; then continue; fi; \
			source=$${compiled%c}; \
			if [ ! -e "$$source" ]; then \
				echo "Orphaned Emacsvox byte-code: $$compiled" >&2; \
				echo "Run make bytecode-rebuild after branch changes." >&2; \
				exit 1; \
			fi; \
			compiled_version="$$(sed -n \
				'3s/^;;; in Emacs version //p' "$$compiled")"; \
			if [ "$$compiled_version" != "$$selected_version" ]; then \
				echo "Byte-code compiler mismatch: $$compiled" >&2; \
				echo "Built by Emacs $$compiled_version; selected Emacs is $$selected_version." >&2; \
				echo "Run make bytecode-rebuild." >&2; \
				exit 1; \
			fi; \
		done; \
		echo "Emacsvox byte-code is current."

bytecode-rebuild:
	$(MAKE) clean
	$(MAKE) EMACS="$(EMACS)" bytecode

generated-reference: bytecode-check
	cd info && $(EMACS) -Q --batch \
		--eval '(setq file-name-handler-alist nil gc-cons-threshold 128000000)' \
		-l ../utils/self-document.el -f self-document-all-modules-batch

# Keep the manual authoring loop independent of Emacsvox byte-code.  Preview
# one complete manual as a single HTML file so included Texinfo chapters are
# checked in their real context.
docs-preview:
	@set -eu; \
		case "$(DOCS_MANUAL)" in \
			emacsvox|emacsvox-reference|emacsvox-heritage|introducing-emacspeak) \
				source="$(DOCS_MANUAL).texi" ;; \
			*) \
				echo "Unknown DOCS_MANUAL: $(DOCS_MANUAL)" >&2; \
				echo "Choose emacsvox, emacsvox-reference, emacsvox-heritage, or introducing-emacspeak." >&2; \
				exit 2 ;; \
		esac; \
		mkdir -p "$(DOCS_PREVIEW_DIR)"; \
		cd info; \
		$(MAKEINFO) --error-limit=0 --html --no-split \
			-c HTMLXREF_MODE=file -c HTMLXREF_FILE=htmlxref.cnf \
			--css-ref=https://www.w3.org/StyleSheets/Core/Modernist \
			--output="$(DOCS_PREVIEW_DIR)/$(DOCS_MANUAL).html" "$$source"; \
		echo "Previewed $(DOCS_MANUAL) at $(DOCS_PREVIEW_DIR)/$(DOCS_MANUAL).html"

# Export the canonical maintained prose without loading or compiling Emacsvox.
docs-org-export: check-emacs
	@mkdir -p "$(DOCS_ORG_PREVIEW_DIR)"
	EMACSVOX_ORG_SOURCE="$(DOCS_ORG_SOURCE)" \
	EMACSVOX_ORG_OUTPUT="$(DOCS_ORG_PREVIEW_DIR)/emacsvox-org.texi" \
	$(EMACS) -Q --batch -L utils -l utils/emacsvox-org-export.el \
		-f emacsvox-org-export-batch

docs-org-preview: docs-org-export
	@set -eu; \
		cd "$(DOCS_ORG_PREVIEW_DIR)"; \
		$(MAKEINFO) --error-limit=0 -I "$(CURDIR)/info" \
			--output=emacsvox-org.info \
			emacsvox-org.texi; \
		$(MAKEINFO) --error-limit=0 --html --no-split \
			-I "$(CURDIR)/info" \
			-c HTMLXREF_MODE=file \
			-c HTMLXREF_FILE="$(DOCS_ORG_HTMLXREF)" \
			--css-ref=https://www.w3.org/StyleSheets/Core/Modernist \
			--output=emacsvox-org.html emacsvox-org.texi; \
		echo "Previewed Org manual at $(DOCS_ORG_PREVIEW_DIR)/emacsvox-org.html"; \
		echo "Built Org Info at $(DOCS_ORG_PREVIEW_DIR)/emacsvox-org.info"

# Update the tracked Texinfo body consumed by the release wrapper.  This is an
# explicit authoring action, analogous to updating tracked Info output.
docs-org-generate: check-emacs
	EMACSVOX_ORG_SOURCE="$(DOCS_ORG_SOURCE)" \
	EMACSVOX_ORG_OUTPUT="$(DOCS_ORG_BODY)" \
	EMACSVOX_ORG_BODY_ONLY=1 \
	$(EMACS) -Q --batch -L utils -l utils/emacsvox-org-export.el \
		-f emacsvox-org-export-batch

docs-org-check: docs-org-preview
	@set -eu; \
		EMACSVOX_ORG_SOURCE="$(DOCS_ORG_SOURCE)" \
		EMACSVOX_ORG_OUTPUT="$(DOCS_ORG_PREVIEW_DIR)/emacsvox-body.texi" \
		EMACSVOX_ORG_BODY_ONLY=1 \
		$(EMACS) -Q --batch -L utils -l utils/emacsvox-org-export.el \
			-f emacsvox-org-export-batch; \
		if ! cmp -s "$(DOCS_ORG_BODY)" \
			"$(DOCS_ORG_PREVIEW_DIR)/emacsvox-body.texi"; then \
			echo "Tracked info/emacsvox-body.texi is stale; run make docs-org-generate." >&2; \
			exit 1; \
		fi; \
		actual_nodes="$$(sed -n 's/^@node //p' \
			"$(DOCS_ORG_PREVIEW_DIR)/emacsvox-body.texi" | paste -sd '|' -)"; \
		expected_nodes="$$(paste -sd '|' "$(DOCS_ORG_NODES)")"; \
		if test "$$actual_nodes" != "$$expected_nodes"; then \
			echo "Org manual changed the accepted Info node topology." >&2; \
			echo "Expected: $$expected_nodes" >&2; \
			echo "Actual:   $$actual_nodes" >&2; \
			exit 1; \
		fi; \
		echo "Org-generated Texinfo is current and its Info node topology is compatible."

# Update only checked Info files whose hand-written Texinfo inputs changed.
# Generated Lisp references have their own explicit, byte-code-aware target.
docs-update: docs-org-generate
	$(MAKE) -C info MAKEINFO="$(MAKEINFO)" all heritage-standalone

docs-reference: generated-reference
	$(MAKE) -C info MAKEINFO="$(MAKEINFO)" emacsvox-reference.info

# Retain the comprehensive generation target for Lisp/public-interface
# changes and release preparation.
docs-generate: docs-reference
	$(MAKE) docs-update

docs-release-check: version-check bytecode-check docs-org-check
	EMACSVOX_MAKEINFO="$(MAKEINFO)" \
	EMACSVOX_INSTALL_INFO="$(INSTALL_INFO)" \
	$(EMACS) -Q --batch -L utils -l utils/emacsvox-docs-check.el \
		-f emacsvox-docs-check-batch

docs-check: docs-release-check

docs-check-external: docs-release-check
	utils/check-required-doc-links.sh etc/docs-required-links.txt

docs-publish: bytecode-check docs-org-check
	@if test -z "$(DOCS_PUBLISH_DIR)"; then \
		echo "Set DOCS_PUBLISH_DIR to an existing publication directory." >&2; \
		exit 2; \
	fi
	EMACSVOX_MAKEINFO="$(MAKEINFO)" \
	EMACSVOX_INSTALL_INFO="$(INSTALL_INFO)" \
	EMACSVOX_DOCS_PUBLISH_DIR="$(DOCS_PUBLISH_DIR)" \
	$(EMACS) -Q --batch -L utils -l utils/emacsvox-docs-check.el \
		-f emacsvox-docs-publish-batch

docs-publish-pages: bytecode-check docs-org-check
	@if test -z "$(DOCS_PUBLISH_DIR)"; then \
		echo "Set DOCS_PUBLISH_DIR to an existing gh-pages worktree." >&2; \
		exit 2; \
	fi
	EMACSVOX_MAKEINFO="$(MAKEINFO)" \
	EMACSVOX_INSTALL_INFO="$(INSTALL_INFO)" \
	EMACSVOX_DOCS_PUBLISH_DIR="$(DOCS_PUBLISH_DIR)" \
	$(EMACS) -Q --batch -L utils -l utils/emacsvox-docs-check.el \
		-f emacsvox-docs-publish-pages-batch

compiled-aural-test:
	$(EMACS) -Q --batch -l test/run-compiled-aural-tests.el

build-aural-test:
	$(MAKE) -C lisp EMACS="$(EMACS)" aural
	$(EMACS) -Q --batch -l test/verify-build-tree-aural.el

trace:
	EMACSVOX_TRACE_IMPLEMENTATION=emacsvox \
	EMACSVOX_TRACE_ROOT="$(CURDIR)" \
	$(EMACS) -Q --batch -l test/run-scenarios.el

trace-test:
	EMACSVOX_TRACE_IMPLEMENTATION=emacsvox \
	EMACSVOX_TRACE_ROOT="$(CURDIR)" \
	EMACSVOX_TRACE_EXPECTED="$(CURDIR)/$(TRACE_GOLDEN)" \
	$(EMACS) -Q --batch -l test/run-scenarios.el

reference-test:
	@if test -z "$(EMACSPEAK_DIR)"; then \
		echo "Set EMACSPEAK_DIR to the pinned Emacspeak checkout."; \
		exit 2; \
	fi
	EMACSVOX_TRACE_IMPLEMENTATION=emacspeak \
	EMACSVOX_TRACE_ROOT="$(EMACSPEAK_DIR)" \
	EMACSVOX_TRACE_EXPECTED="$(CURDIR)/$(EMACSPEAK_TRACE_GOLDEN)" \
	$(EMACS) -Q --batch -l test/run-scenarios.el

advice-audit:
	$(EMACS) -Q --batch -l utils/advice-audit.el \
		--eval '(ems-advice-audit-batch "lisp")'

name-audit:
	$(EMACS) -Q --batch -l utils/emacsvox-name-audit.el \
		--eval '(ems-name-audit-batch ".")'

tts-audit:
	$(EMACS) -Q --batch -l utils/tts-audit.el \
		--eval '(ems-tts-audit-batch "lisp")'

aural-audit:
	$(EMACS) -Q --batch --eval '(setq load-prefer-newer t)' \
		-L lisp -L utils -l utils/emacsvox-aural-audit.el \
		--eval '(emacsvox-aural-audit-batch "$(CURDIR)")'

aural-reference:
	$(EMACS) -Q --batch --eval '(setq load-prefer-newer t)' \
		-L lisp -L utils -l utils/emacsvox-aural-audit.el \
		--eval '(emacsvox-aural-write-reference "$(CURDIR)")'

###   User level targets emacsvox   outloud espeak 

emacsvox: check-emacs config
	@cd lisp && $(MAKE) EMACS="$(EMACS)" $(MAKEFLAGS)
	@echo "See the NEWS file for a  summary of new features — Control e cap n in Emacs"
	@echo "See Emacsvox Customizations for customizations — control e cap C in Emacs"
	@echo  "Read the Emacsvox Manual — Control e TAB in Emacs"
	@make install

swiftmac:
	$(MAKE) -C servers/mac-swiftmac

outloud: 
	$(MAKE) -C servers/linux-outloud

espeak: 
	$(MAKE) -C servers/native-espeak

dtk: 
	$(MAKE) -C servers/software-dtk

windows-speech: windows-audio windows-outloud windows-dtk

windows-audio:
	$(MAKE) -C servers/windows-audio

windows-outloud:
	$(MAKE) -C servers/windows-eloquence

windows-dtk:
	$(MAKE) -C servers/windows-dectalk

OMNIVOX_DIR ?= $(abspath ../omnivox)
OMNIVOX_TARGET ?= x86_64-pc-windows-gnu
OMNIVOX_RUNTIME_DIR = $(CURDIR)/servers/omnivox-bin
OMNIVOX_RELEASE_DIR = $(CURDIR)/servers/omnivox-release
OMNIVOX_RELEASE_IMAGE ?= emacsvox-omnivox-windows-gnu:rust-1.97.1
OMNIVOX_RELEASE_TARGET_DIR = $(OMNIVOX_DIR)/target/emacsvox-release
OMNIVOX_HELPER_DIR = $(OMNIVOX_DIR)/windows-helpers
OMNIVOX_ALLOW_DIRTY ?= 0
OMNIVOX_BUILD_KIND ?= release-clean-worktree
OMNIVOX_INCLUDE_PINNED_PIPER ?= 1
OMNIVOX_PIPER_PREPARED ?= 0
OMNIVOX_PIPER_DEVELOPMENT_ARCHIVE ?=
OMNIVOX_PIPER_DEVELOPMENT_ARCHIVE_SHA256 ?=
OMNIVOX_INCLUDE_TGSPEECHBOX ?= 0
OMNIVOX_TGSPEECHBOX_CXX ?= x86_64-w64-mingw32-g++-posix
OMNIVOX_RECORD_RHVOICE ?= 0
# Make include paths need escaped spaces even after variable expansion.
emacsvox_make_empty :=
emacsvox_make_space := $(emacsvox_make_empty) $(emacsvox_make_empty)
include $(subst $(emacsvox_make_space),\ ,$(OMNIVOX_RELEASE_DIR)/toolchain.lock)
OMNIVOX_CSC = $(OMNIVOX_RELEASE_DIR)/cache/roslyn-$(roslyn_version)/tasks/net472/csc.exe
OMNIVOX_REFERENCE_DIR = $(OMNIVOX_RELEASE_DIR)/cache/net40-reference-assemblies-$(reference_assemblies_version)/build/.NETFramework/v4.0
OMNIVOX_PIPER_DIR = $(OMNIVOX_RELEASE_DIR)/cache/piper-$(omnivox_piper_version)/companion-$(omnivox_piper_archive_sha256)/piper
OMNIVOX_PIPER_COMPANION_STATE ?= official-omnivox-release
OMNIVOX_PIPER_COMPANION_VERSION ?= $(omnivox_piper_version)
OMNIVOX_PIPER_COMPANION_COMMIT ?= $(omnivox_piper_commit)
OMNIVOX_PIPER_COMPANION_ARCHIVE_SHA256 ?= $(omnivox_piper_archive_sha256)

verify-windows-omnivox-toolchain:
	OMNIVOX_RELEASE_IMAGE="$(OMNIVOX_RELEASE_IMAGE)" \
		"$(OMNIVOX_RELEASE_DIR)/verify-toolchain.sh"

verify-windows-omnivox-helpers:
	"$(OMNIVOX_RELEASE_DIR)/verify-helper-determinism.sh" \
		"$(OMNIVOX_DIR)" "$(OMNIVOX_CSC)" "$(OMNIVOX_REFERENCE_DIR)"

prepare-windows-omnivox-piper:
	"$(OMNIVOX_RELEASE_DIR)/prepare-piper-companion.sh" \
		"$(OMNIVOX_RELEASE_DIR)" "$(OMNIVOX_DIR)"

windows-omnivox-dev:
	$(MAKE) OMNIVOX_ALLOW_DIRTY=1 \
		OMNIVOX_BUILD_KIND=local-dirty-worktree \
		OMNIVOX_RECORD_RHVOICE=1 \
		OMNIVOX_INCLUDE_TGSPEECHBOX=1 \
		OMNIVOX_INCLUDE_PINNED_PIPER=0 windows-omnivox

windows-omnivox-piper-dev:
	@set -eu; \
		if [ -z "$(OMNIVOX_PIPER_DEVELOPMENT_ARCHIVE)" ] || \
			[ -z "$(OMNIVOX_PIPER_DEVELOPMENT_ARCHIVE_SHA256)" ]; then \
			echo "Set OMNIVOX_PIPER_DEVELOPMENT_ARCHIVE and OMNIVOX_PIPER_DEVELOPMENT_ARCHIVE_SHA256" >&2; \
			exit 1; \
		fi; \
		if [ -z "$${OMNIVOX_PIPER_MODEL:-}" ]; then \
			echo "Set OMNIVOX_PIPER_MODEL to a reviewed Piper .onnx voice" >&2; \
			exit 1; \
		fi; \
		piper_dir="$$("$(OMNIVOX_RELEASE_DIR)/prepare-piper-development-companion.sh" \
			"$(OMNIVOX_RELEASE_DIR)" "$(OMNIVOX_DIR)" \
			"$(OMNIVOX_PIPER_DEVELOPMENT_ARCHIVE)" \
			"$(OMNIVOX_PIPER_DEVELOPMENT_ARCHIVE_SHA256)")"; \
		omnivox_commit="$$(git -C "$(OMNIVOX_DIR)" rev-parse HEAD)"; \
		$(MAKE) OMNIVOX_ALLOW_DIRTY=1 \
			OMNIVOX_BUILD_KIND=local-dirty-worktree \
			OMNIVOX_RECORD_RHVOICE=1 \
			OMNIVOX_INCLUDE_TGSPEECHBOX=1 \
			OMNIVOX_INCLUDE_PINNED_PIPER=1 \
			OMNIVOX_PIPER_PREPARED=1 \
			OMNIVOX_PIPER_DIR="$$piper_dir" \
			OMNIVOX_PIPER_COMPANION_STATE=github-actions-native-development-build \
			OMNIVOX_PIPER_COMPANION_VERSION=development-ci \
			OMNIVOX_PIPER_COMPANION_COMMIT="$$omnivox_commit" \
			OMNIVOX_PIPER_COMPANION_ARCHIVE_SHA256="$(OMNIVOX_PIPER_DEVELOPMENT_ARCHIVE_SHA256)" \
			windows-omnivox

windows-omnivox-main-dev:
	"$(OMNIVOX_RELEASE_DIR)/stage-main-dev.sh" \
		"$(CURDIR)" "$(OMNIVOX_DIR)" "$(OMNIVOX_RUNTIME_DIR)" \
		"$(OMNIVOX_RELEASE_DIR)" "$(OMNIVOX_RELEASE_IMAGE)" \
		"$(OMNIVOX_TARGET)"
	$(MAKE) verify-windows-omnivox-main-live

windows-omnivox:
	@set -eu; \
		case "$(OMNIVOX_INCLUDE_PINNED_PIPER)" in \
			0 | 1) ;; \
			*) echo "OMNIVOX_INCLUDE_PINNED_PIPER must be 0 or 1" >&2; exit 1 ;; \
		esac; \
		case "$(OMNIVOX_PIPER_PREPARED)" in \
			0 | 1) ;; \
			*) echo "OMNIVOX_PIPER_PREPARED must be 0 or 1" >&2; exit 1 ;; \
		esac; \
		case "$(OMNIVOX_PIPER_COMPANION_STATE)" in \
			official-omnivox-release | github-actions-native-development-build) ;; \
			*) echo "Unknown OMNIVOX_PIPER_COMPANION_STATE" >&2; exit 1 ;; \
		esac; \
		if [ "$(OMNIVOX_PIPER_COMPANION_STATE)" = \
			github-actions-native-development-build ] && \
			{ [ "$(OMNIVOX_ALLOW_DIRTY)" != 1 ] || \
			  [ "$(OMNIVOX_INCLUDE_PINNED_PIPER)" != 1 ] || \
			  [ "$(OMNIVOX_PIPER_PREPARED)" != 1 ]; }; then \
			echo "Native development Piper requires its guarded development target" >&2; \
			exit 1; \
		fi; \
		case "$(OMNIVOX_INCLUDE_TGSPEECHBOX)" in \
			0 | 1) ;; \
			*) echo "OMNIVOX_INCLUDE_TGSPEECHBOX must be 0 or 1" >&2; exit 1 ;; \
		esac; \
		case "$(OMNIVOX_RECORD_RHVOICE)" in \
			0 | 1) ;; \
			*) echo "OMNIVOX_RECORD_RHVOICE must be 0 or 1" >&2; exit 1 ;; \
		esac; \
		if [ "$(OMNIVOX_ALLOW_DIRTY)" != 1 ] && \
			[ "$(OMNIVOX_INCLUDE_PINNED_PIPER)" != 1 ]; then \
			echo "The clean Windows runtime must include its matching Piper companion" >&2; \
			exit 1; \
		fi; \
		if [ "$(OMNIVOX_ALLOW_DIRTY)" != 1 ] && \
			[ "$(OMNIVOX_INCLUDE_TGSPEECHBOX)" != 0 ]; then \
			echo "TGSpeechBox is experimental and may only be staged by windows-omnivox-dev" >&2; \
			exit 1; \
		fi; \
		if [ "$(OMNIVOX_ALLOW_DIRTY)" != 1 ]; then \
			for repository in "$(CURDIR)" "$(OMNIVOX_DIR)"; do \
				if ! git -C "$$repository" diff --quiet --ignore-submodules -- || \
					! git -C "$$repository" diff --cached --quiet --ignore-submodules --; then \
					echo "Refusing to stage Omnivox from tracked changes in $$repository" >&2; \
					echo "Use make windows-omnivox-dev for a provenance-labelled development build." >&2; \
					exit 1; \
				fi; \
			done; \
		fi
	$(MAKE) verify-windows-omnivox-toolchain
	$(MAKE) verify-windows-omnivox-helpers
	@if [ "$(OMNIVOX_INCLUDE_TGSPEECHBOX)" = 1 ]; then \
		command -v "$(OMNIVOX_TGSPEECHBOX_CXX)" >/dev/null || { \
			echo "TGSpeechBox requires the MinGW POSIX C++ compiler: $(OMNIVOX_TGSPEECHBOX_CXX)" >&2; \
			exit 1; \
		}; \
		cd "$(OMNIVOX_DIR)" && \
			CXX_x86_64_pc_windows_gnu="$(OMNIVOX_TGSPEECHBOX_CXX)" \
			python3 tools/build_tgspeechbox.py --release \
				--target $(OMNIVOX_TARGET); \
	fi
	@if [ "$(OMNIVOX_INCLUDE_PINNED_PIPER)" = 1 ] && \
		[ "$(OMNIVOX_PIPER_PREPARED)" != 1 ]; then \
		$(MAKE) prepare-windows-omnivox-piper; \
	fi
	docker run --rm --platform linux/amd64 \
		--user "$$(id -u):$$(id -g)" \
		--env HOME=/workspace/omnivox/target/emacsvox-home \
		--env CARGO_HOME=/workspace/omnivox/target/emacsvox-cargo-home \
		--env CARGO_TARGET_DIR=/workspace/omnivox/target/emacsvox-release \
		--volume "$(OMNIVOX_DIR):/workspace/omnivox" \
		--workdir /workspace/omnivox \
		"$(OMNIVOX_RELEASE_IMAGE)" sh -eu -c ' \
			mkdir -p "$$HOME" "$$CARGO_HOME"; \
			if [ "$$CARGO_TARGET_DIR" != \
				/workspace/omnivox/target/emacsvox-release ]; then \
				echo "Refusing to clean unexpected release target: $$CARGO_TARGET_DIR" >&2; \
				exit 1; \
			fi; \
			if [ "$$(readlink -f -- "$${CARGO_TARGET_DIR%/*}")" != \
				/workspace/omnivox/target ]; then \
				echo "Refusing to clean through a redirected target parent" >&2; \
				exit 1; \
			fi; \
			if [ -L "$$CARGO_TARGET_DIR" ]; then \
				echo "Refusing to clean symlinked release target: $$CARGO_TARGET_DIR" >&2; \
				exit 1; \
			fi; \
			rm -rf -- "$$CARGO_TARGET_DIR"; \
			mkdir -p "$$CARGO_TARGET_DIR"; \
			cargo build --locked --release -p omnivox-cli; \
			export CC_x86_64_pc_windows_gnu=x86_64-w64-mingw32-gcc-win32; \
			export CXX_x86_64_pc_windows_gnu=x86_64-w64-mingw32-g++-win32; \
			export AR_x86_64_pc_windows_gnu=x86_64-w64-mingw32-ar; \
			export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=x86_64-w64-mingw32-gcc-win32; \
			export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_RUSTFLAGS="-C link-arg=-Wl,--no-insert-timestamp"; \
			if [ "$(OMNIVOX_INCLUDE_PINNED_PIPER)" = 1 ]; then \
				cargo build --locked --release -p omnivox-cli --features piper \
					--target $(OMNIVOX_TARGET); \
			else \
				cargo build --locked --release -p omnivox-cli \
					--target $(OMNIVOX_TARGET); \
			fi; \
			python3 tools/build_rhvoice.py --release \
				--target $(OMNIVOX_TARGET); \
			python3 tools/build_flite.py --release \
				--target $(OMNIVOX_TARGET); \
			python3 tools/build_rutts.py --release \
				--target $(OMNIVOX_TARGET); \
			if [ "$(OMNIVOX_INCLUDE_TGSPEECHBOX)" = 1 ]; then \
				tgspeechbox_source="/workspace/omnivox/target/$(OMNIVOX_TARGET)/release/tgspeechbox"; \
				tgspeechbox_destination="$$CARGO_TARGET_DIR/$(OMNIVOX_TARGET)/release/tgspeechbox"; \
				if [ ! -f "$$tgspeechbox_source/omnivox-tgspeechbox-helper.exe" ] || \
					[ ! -f "$$tgspeechbox_source/VOICE-INVENTORY.json" ] || \
					[ ! -f "$$tgspeechbox_source/VOICE-INVENTORY-22050.json" ] || \
					[ ! -f "$$tgspeechbox_source/VOICE-INVENTORY-44100.json" ]; then \
					echo "Host-built TGSpeechBox companion is incomplete: $$tgspeechbox_source" >&2; \
					exit 1; \
				fi; \
				cp -a "$$tgspeechbox_source" "$$tgspeechbox_destination"; \
			fi; \
			cp "$$CARGO_TARGET_DIR/$(OMNIVOX_TARGET)/release/omnivox.exe" \
				"$$CARGO_TARGET_DIR/$(OMNIVOX_TARGET)/release/omnivox.unstripped.exe"; \
			SOURCE_DATE_EPOCH=0 x86_64-w64-mingw32-strip --strip-all \
				"$$CARGO_TARGET_DIR/$(OMNIVOX_TARGET)/release/omnivox.exe" \
				"$$CARGO_TARGET_DIR/$(OMNIVOX_TARGET)/release/rhvoice/omnivox-rhvoice-helper.exe" \
				"$$CARGO_TARGET_DIR/$(OMNIVOX_TARGET)/release/flite/omnivox-flite-helper.exe" \
				"$$CARGO_TARGET_DIR/$(OMNIVOX_TARGET)/release/rutts/omnivox-rutts-helper.exe"; \
			flite_dir="$$CARGO_TARGET_DIR/$(OMNIVOX_TARGET)/release/flite"; \
			flite_manifest="$$CARGO_TARGET_DIR/$(OMNIVOX_TARGET)/release/flite-SHA256SUMS"; \
			(cd "$$flite_dir" && \
				find . -type f ! -name SHA256SUMS -print0 | LC_ALL=C sort -z | \
				xargs -0 sha256sum) > "$$flite_manifest"; \
			mv "$$flite_manifest" "$$flite_dir/SHA256SUMS"; \
			rutts_dir="$$CARGO_TARGET_DIR/$(OMNIVOX_TARGET)/release/rutts"; \
			rutts_manifest="$$CARGO_TARGET_DIR/$(OMNIVOX_TARGET)/release/rutts-SHA256SUMS"; \
			(cd "$$rutts_dir" && \
				find . -type f ! -name SHA256SUMS -print0 | LC_ALL=C sort -z | \
				xargs -0 sha256sum) > "$$rutts_manifest"; \
			mv "$$rutts_manifest" "$$rutts_dir/SHA256SUMS"; \
			if [ "$(OMNIVOX_INCLUDE_TGSPEECHBOX)" = 1 ]; then \
				tgspeechbox_dir="$$CARGO_TARGET_DIR/$(OMNIVOX_TARGET)/release/tgspeechbox"; \
				SOURCE_DATE_EPOCH=0 x86_64-w64-mingw32-strip --strip-all \
					"$$tgspeechbox_dir/omnivox-tgspeechbox-helper.exe"; \
				tgspeechbox_manifest="$$CARGO_TARGET_DIR/$(OMNIVOX_TARGET)/release/tgspeechbox-SHA256SUMS"; \
				(cd "$$tgspeechbox_dir" && \
					find . -type f ! -name SHA256SUMS -print0 | LC_ALL=C sort -z | \
					xargs -0 sha256sum) > "$$tgspeechbox_manifest"; \
				mv "$$tgspeechbox_manifest" "$$tgspeechbox_dir/SHA256SUMS"; \
			fi; \
			mkdir -p "$$CARGO_TARGET_DIR/windows-runtime"; \
			cp "$$(x86_64-w64-mingw32-g++-win32 -print-file-name=libstdc++-6.dll)" \
				"$$CARGO_TARGET_DIR/windows-runtime/libstdc++-6.dll"; \
			cp "$$(x86_64-w64-mingw32-g++-win32 -print-file-name=libgcc_s_seh-1.dll)" \
				"$$CARGO_TARGET_DIR/windows-runtime/libgcc_s_seh-1.dll"; \
		'
	EMACSVOX_STAGE_ROOT="$(CURDIR)" \
		OMNIVOX_BUILD_KIND="$(OMNIVOX_BUILD_KIND)" \
		OMNIVOX_CSC="$(OMNIVOX_CSC)" \
		OMNIVOX_DIR="$(OMNIVOX_DIR)" \
		OMNIVOX_HELPER_DIR="$(OMNIVOX_HELPER_DIR)" \
		OMNIVOX_INCLUDE_PINNED_PIPER="$(OMNIVOX_INCLUDE_PINNED_PIPER)" \
		OMNIVOX_INCLUDE_TGSPEECHBOX="$(OMNIVOX_INCLUDE_TGSPEECHBOX)" \
		OMNIVOX_PIPER_COMPANION_ARCHIVE_SHA256="$(OMNIVOX_PIPER_COMPANION_ARCHIVE_SHA256)" \
		OMNIVOX_PIPER_COMPANION_COMMIT="$(OMNIVOX_PIPER_COMPANION_COMMIT)" \
		OMNIVOX_PIPER_COMPANION_STATE="$(OMNIVOX_PIPER_COMPANION_STATE)" \
		OMNIVOX_PIPER_COMPANION_VERSION="$(OMNIVOX_PIPER_COMPANION_VERSION)" \
		OMNIVOX_PIPER_DIR="$(OMNIVOX_PIPER_DIR)" \
		OMNIVOX_RECORD_RHVOICE="$(OMNIVOX_RECORD_RHVOICE)" \
		OMNIVOX_RELEASE_DIR="$(OMNIVOX_RELEASE_DIR)" \
		OMNIVOX_RELEASE_IMAGE="$(OMNIVOX_RELEASE_IMAGE)" \
		OMNIVOX_RELEASE_TARGET_DIR="$(OMNIVOX_RELEASE_TARGET_DIR)" \
		OMNIVOX_RUNTIME_DIR="$(OMNIVOX_RUNTIME_DIR)" \
		OMNIVOX_TARGET="$(OMNIVOX_TARGET)" \
		OMNIVOX_TGSPEECHBOX_CXX="$(OMNIVOX_TGSPEECHBOX_CXX)" \
		reference_assemblies_nupkg_sha256="$(reference_assemblies_nupkg_sha256)" \
		roslyn_nupkg_sha256="$(roslyn_nupkg_sha256)" \
		"$(OMNIVOX_RELEASE_DIR)/stage-runtime.sh"
	$(MAKE) verify-windows-omnivox-runtime
	$(MAKE) verify-windows-omnivox-live

verify-windows-omnivox-runtime:
	"$(OMNIVOX_RELEASE_DIR)/verify-runtime.sh" \
		"$(OMNIVOX_RUNTIME_DIR)" "$(OMNIVOX_RELEASE_DIR)"

verify-windows-omnivox-live:
	"$(OMNIVOX_RELEASE_DIR)/verify-runtime-live.sh" \
		"$(OMNIVOX_RUNTIME_DIR)" "$(OMNIVOX_RELEASE_DIR)"

verify-windows-omnivox-main-live:
	"$(OMNIVOX_RELEASE_DIR)/verify-main-live.sh" \
		"$(OMNIVOX_RUNTIME_DIR)"

clean-windows-speech: clean-windows-audio clean-windows-outloud clean-windows-dtk

clean-windows-audio:
	$(MAKE) -C servers/windows-audio clean

clean-windows-outloud:
	$(MAKE) -C servers/windows-eloquence clean

clean-windows-dtk:
	$(MAKE) -C servers/windows-dectalk clean

clean-windows-omnivox:
	rm -rf "$(OMNIVOX_RUNTIME_DIR)"

dist: release-artifact

###  User level target--  config

config:
	@cd etc && $(MAKE) config $(MAKEFLAGS)
	@cd lisp && $(MAKE) EMACS="$(EMACS)" config $(MAKEFLAGS)

###   complete build

all: emacsvox

q:
	make clean
	make config 
	make
	@cd lisp && make muggles $(MAKEFLAGS)
	@cd lisp && make extra-muggles $(MAKEFLAGS)
	@test -d tvr && cd	 tvr && make $(MAKEFLAGS)

###   user level target-- clean

clean:
	@cd lisp &&  $(MAKE) $(MAKEFLAGS) clean

###  guarded releases

# All version values come from VERSION.  Checking, artifact creation, local
# tagging, and external publication remain separate operations so no tag or
# remote state changes before the complete gate and artifact succeed.
release-source-check: version-check headers-check
	@utils/emacsvox-version-check --release

release-check: release-source-check test docs-release-check
	@echo "Emacsvox $(VERSION) passed the release gate."

release-artifact: release-check
	@set -eu; \
		utils/emacsvox-version-check --release; \
		mkdir -p "$(DIST_DIR)"; \
		tar_tmp="$(RELEASE_ARCHIVE).tar.tmp"; \
		archive_tmp="$(RELEASE_ARCHIVE).tmp"; \
		checksum_tmp="$(RELEASE_CHECKSUM).tmp"; \
		provenance_tmp="$(RELEASE_PROVENANCE).tmp"; \
		trap 'rm -f "$$tar_tmp" "$$archive_tmp" "$$checksum_tmp" \
			"$$provenance_tmp"' \
			EXIT HUP INT TERM; \
		git archive --format=tar --prefix="$(RELEASE_PREFIX)/" \
			--output="$$tar_tmp" HEAD; \
		bzip2 -9 -c "$$tar_tmp" > "$$archive_tmp"; \
		python3 utils/emacsvox-check-source-archive.py \
			--archive "$$archive_tmp" --emacs "$(EMACS)"; \
		rm -f "$$tar_tmp"; \
		mv "$$archive_tmp" "$(RELEASE_ARCHIVE)"; \
		cd "$(DIST_DIR)"; \
		sha256sum "$(notdir $(RELEASE_ARCHIVE))" > "$$checksum_tmp"; \
		mv "$$checksum_tmp" "$(notdir $(RELEASE_CHECKSUM))"; \
		artifact_sha256="$$(cut -d ' ' -f 1 \
			"$(notdir $(RELEASE_CHECKSUM))")"; \
		{ \
			printf 'version=%s\n' "$(VERSION)"; \
			printf 'source_commit=%s\n' "$$(git -C "$(CURDIR)" rev-parse HEAD)"; \
			printf 'artifact_sha256=%s\n' "$$artifact_sha256"; \
		} > "$$provenance_tmp"; \
		mv "$$provenance_tmp" "$(notdir $(RELEASE_PROVENANCE))"; \
		trap - EXIT HUP INT TERM
	@echo "Prepared $(RELEASE_ARCHIVE)"
	@echo "Checksum $(RELEASE_CHECKSUM)"
	@echo "Provenance $(RELEASE_PROVENANCE)"

release-artifact-check: release-source-check
	@set -eu; \
		test -f "$(RELEASE_ARCHIVE)" || { \
			echo "Missing release artifact; run make release-artifact." >&2; \
			exit 1; \
		}; \
		test -f "$(RELEASE_CHECKSUM)" || { \
			echo "Missing release checksum; run make release-artifact." >&2; \
			exit 1; \
		}; \
		test -f "$(RELEASE_PROVENANCE)" || { \
			echo "Missing release provenance; run make release-artifact." >&2; \
			exit 1; \
		}; \
		cd "$(DIST_DIR)"; \
		sha256sum --check "$(notdir $(RELEASE_CHECKSUM))"; \
		test "$$(sed -n 's/^version=//p' \
			"$(notdir $(RELEASE_PROVENANCE))")" = "$(VERSION)" || { \
			echo "Release artifact version does not match VERSION." >&2; \
			exit 1; \
		}; \
		test "$$(sed -n 's/^source_commit=//p' \
			"$(notdir $(RELEASE_PROVENANCE))")" = \
			"$$(git -C "$(CURDIR)" rev-parse HEAD)" || { \
			echo "Release artifact was not built from current HEAD." >&2; \
			exit 1; \
		}; \
		test "$$(sed -n 's/^artifact_sha256=//p' \
			"$(notdir $(RELEASE_PROVENANCE))")" = \
			"$$(cut -d ' ' -f 1 "$(notdir $(RELEASE_CHECKSUM))")" || { \
			echo "Release artifact provenance does not match its checksum." >&2; \
			exit 1; \
		}

source-archive-check: check-emacs
	python3 utils/emacsvox-check-source-archive.py --archive "$(RELEASE_ARCHIVE)" --emacs "$(EMACS)"

source-archive-test:
	python3 -m unittest discover -s test -p 'test_source_archive.py' -v

release: release-artifact
	@echo "Artifact ready; run make release-tag only after inspecting it."

release-tag: release-artifact-check
	@utils/emacsvox-version-check --tag
	git tag -a --no-sign "$(VERSION)" -m "Emacsvox $(VERSION)"
	@echo "Created local annotated tag $(VERSION); it has not been pushed."

release-publish: release-artifact-check
	@utils/emacsvox-version-check --publish
	@command -v gh >/dev/null 2>&1 || { \
		echo "GitHub CLI 'gh' is required for publication." >&2; exit 1; }
	@set -eu; \
		release_repository="$$(gh repo view \
		"$$(git remote get-url "$(RELEASE_REMOTE)")" \
		--json nameWithOwner --jq .nameWithOwner)"; \
		test -n "$$release_repository" || { \
			echo "Could not resolve GitHub repository for $(RELEASE_REMOTE)." >&2; \
			exit 1; \
		}; \
		git push "$(RELEASE_REMOTE)" "refs/tags/$(VERSION)"; \
		gh release create "$(VERSION)" \
			"$(RELEASE_ARCHIVE)" "$(RELEASE_CHECKSUM)" \
			"$(RELEASE_PROVENANCE)" \
			--repo "$$release_repository" --verify-tag \
			--title "Emacsvox $(VERSION)" --notes-file etc/NEWS

### Install: 

install:
	@echo "This release requires Emacs 30.2 or later on all platforms."
	@echo "On WSL2, inspect and run the guided binary installation with:"
	@echo "  ./bin/emacsvox-wsl-install --check"
	@echo "  ./bin/emacsvox-wsl-install"
	@echo "On other platforms, run make bytecode and install Omnivox as described in the manual."
	@echo "For an audible speech-server check, run: ./bin/emacsvox --check"
	@echo "For an isolated first start, run: ./bin/emacsvox"
	@echo "For normal customized starts, export TTS_PROGRAM=omnivox and add:"
	@echo "(load-file \"`pwd`/lisp/emacsvox-setup.el\")"
	@echo "Package maintainers: see docs/developer/integration-maintenance.org for instructions."

### Worktree:
# Usage make wk TAG=tag
wk:
	git worktree add ../${TAG}-emacsvox ${TAG}

###  end of file

#local variables:
#mode: makefile
#fill-column: 90
#outline-regexp: "^###"
#end:
