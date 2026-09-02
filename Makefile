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

.PHONY: version version-check headers-check test unit-test notmuch-test compiled-notmuch-test
.PHONY: compiled-aural-test build-aural-test trace trace-test
.PHONY: reference-test advice-audit name-audit tts-audit
.PHONY: check-emacs bytecode bytecode-check bytecode-rebuild generated-reference
.PHONY: docs-preview docs-update docs-reference docs-generate
.PHONY: docs-org-export docs-org-preview docs-org-generate docs-org-check
.PHONY: docs-check docs-release-check docs-check-external
.PHONY: docs-publish docs-publish-pages
.PHONY: aural-audit aural-reference windows-speech windows-audio windows-outloud windows-dtk windows-omnivox
.PHONY: windows-omnivox-dev
.PHONY: verify-windows-omnivox-toolchain verify-windows-omnivox-helpers prepare-windows-omnivox-piper verify-windows-omnivox-runtime verify-windows-omnivox-live
.PHONY: clean-windows-speech clean-windows-audio clean-windows-outloud clean-windows-dtk clean-windows-omnivox
.PHONY: dist release release-source-check release-check release-artifact
.PHONY: release-artifact-check
.PHONY: release-tag release-publish

version:
	@cat "$(VERSION_FILE)"

version-check:
	@utils/emacsvox-version-check --check

headers-check:
	@utils/emacsvox-header-check

test: version-check headers-check unit-test compiled-notmuch-test compiled-aural-test build-aural-test trace-test

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
		'(unless (version<= "31" emacs-version) (error "Emacsvox requires Emacs 31 or newer; got %s from %s" emacs-version invocation-directory))'

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
	@cd lisp && $(MAKE) $(MAKEFLAGS)
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
OMNIVOX_INCLUDE_TGSPEECHBOX ?= 0
OMNIVOX_TGSPEECHBOX_CXX ?= x86_64-w64-mingw32-g++-posix
OMNIVOX_RECORD_RHVOICE ?= 0
include $(OMNIVOX_RELEASE_DIR)/toolchain.lock
OMNIVOX_CSC = $(OMNIVOX_RELEASE_DIR)/cache/roslyn-$(roslyn_version)/tasks/net472/csc.exe
OMNIVOX_REFERENCE_DIR = $(OMNIVOX_RELEASE_DIR)/cache/net40-reference-assemblies-$(reference_assemblies_version)/build/.NETFramework/v4.0
OMNIVOX_PIPER_DIR = $(OMNIVOX_RELEASE_DIR)/cache/piper-$(omnivox_piper_version)/companion-$(omnivox_piper_archive_sha256)/piper

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

windows-omnivox:
	@set -eu; \
		case "$(OMNIVOX_INCLUDE_PINNED_PIPER)" in \
			0 | 1) ;; \
			*) echo "OMNIVOX_INCLUDE_PINNED_PIPER must be 0 or 1" >&2; exit 1 ;; \
		esac; \
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
	@if [ "$(OMNIVOX_INCLUDE_PINNED_PIPER)" = 1 ]; then \
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
	@set -eu; \
		executable="$(OMNIVOX_RELEASE_TARGET_DIR)/$(OMNIVOX_TARGET)/release/omnivox.exe"; \
		unstripped_executable="$(OMNIVOX_RELEASE_TARGET_DIR)/$(OMNIVOX_TARGET)/release/omnivox.unstripped.exe"; \
		rhvoice_companion="$(OMNIVOX_RELEASE_TARGET_DIR)/$(OMNIVOX_TARGET)/release/rhvoice"; \
		flite_companion="$(OMNIVOX_RELEASE_TARGET_DIR)/$(OMNIVOX_TARGET)/release/flite"; \
		rutts_companion="$(OMNIVOX_RELEASE_TARGET_DIR)/$(OMNIVOX_TARGET)/release/rutts"; \
		tgspeechbox_companion="$(OMNIVOX_RELEASE_TARGET_DIR)/$(OMNIVOX_TARGET)/release/tgspeechbox"; \
		omnivox_license="$(OMNIVOX_DIR)/LICENSE"; \
		eloquence_helper="$(OMNIVOX_HELPER_DIR)/bin/OmnivoxEloquenceHelper32.exe"; \
		dectalk_helper="$(OMNIVOX_HELPER_DIR)/bin/OmnivoxDectalkHelper32.exe"; \
		helper_license="$(OMNIVOX_HELPER_DIR)/COPYING"; \
		dectalk_dll="$(CURDIR)/servers/windows-dectalk/runtime/DECtalk.dll"; \
		dectalk_dictionary="$(CURDIR)/servers/windows-dectalk/runtime/dtalk_us.dic"; \
		stdlib="$(OMNIVOX_RELEASE_TARGET_DIR)/windows-runtime/libstdc++-6.dll"; \
		gcc_runtime="$(OMNIVOX_RELEASE_TARGET_DIR)/windows-runtime/libgcc_s_seh-1.dll"; \
		for required in \
			"$$rhvoice_companion/omnivox-rhvoice-helper.exe" \
			"$$flite_companion/omnivox-flite-helper.exe" \
			"$$flite_companion/SHA256SUMS" \
			"$$flite_companion/SOURCE-PROVENANCE.json" \
			"$$flite_companion/third-party-licenses/Flite-COPYING.txt" \
			"$$rutts_companion/omnivox-rutts-helper.exe" \
			"$$rutts_companion/SHA256SUMS" \
			"$$rutts_companion/SOURCE-PROVENANCE.json" \
			"$$rutts_companion/third-party-licenses/RuTTS-LICENSE.txt" \
			"$$omnivox_license"; do \
			if [ ! -f "$$required" ]; then \
				echo "Prepared companion file is missing: $$required" >&2; \
				exit 1; \
			fi; \
		done; \
		rhvoice_companion_digest="$$(cd "$$rhvoice_companion" && \
			find . -type f -print0 | LC_ALL=C sort -z | \
			xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"; \
		flite_companion_digest="$$(cd "$$flite_companion" && \
			find . -type f -print0 | LC_ALL=C sort -z | \
			xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"; \
		rutts_companion_digest="$$(cd "$$rutts_companion" && \
			find . -type f -print0 | LC_ALL=C sort -z | \
			xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"; \
		tgspeechbox_companion_digest=not-included; \
		tgspeechbox_build_environment=not-included; \
		tgspeechbox_cxx=not-included; \
		tgspeechbox_cxx_digest=not-included; \
		if [ "$(OMNIVOX_INCLUDE_TGSPEECHBOX)" = 1 ]; then \
			for required in \
				"$$tgspeechbox_companion/omnivox-tgspeechbox-helper.exe" \
				"$$tgspeechbox_companion/VOICE-INVENTORY.json" \
				"$$tgspeechbox_companion/VOICE-INVENTORY-22050.json" \
				"$$tgspeechbox_companion/VOICE-INVENTORY-44100.json" \
				"$$tgspeechbox_companion/SHA256SUMS" \
				"$$tgspeechbox_companion/SOURCE-PROVENANCE.json" \
				"$$tgspeechbox_companion/espeak-ng-data/phontab" \
				"$$tgspeechbox_companion/packs/lang/en-us.yaml" \
				"$$tgspeechbox_companion/third-party-licenses/TGSpeechBox-LICENSE.txt" \
				"$$tgspeechbox_companion/third-party-licenses/eSpeak-NG-GPL-3.0.txt"; do \
				if [ ! -f "$$required" ]; then \
					echo "Prepared TGSpeechBox companion file is missing: $$required" >&2; \
					exit 1; \
				fi; \
			done; \
			if x86_64-w64-mingw32-objdump -p \
				"$$tgspeechbox_companion/omnivox-tgspeechbox-helper.exe" | \
				grep -Eiq 'DLL Name: (libstdc\+\+|libgcc|libwinpthread)'; then \
				echo "TGSpeechBox helper imports an unbundled MinGW runtime DLL" >&2; \
				exit 1; \
			fi; \
			tgspeechbox_companion_digest="$$(cd "$$tgspeechbox_companion" && \
				find . -type f -print0 | LC_ALL=C sort -z | \
				xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"; \
			tgspeechbox_build_environment=wsl-host-development-only; \
			tgspeechbox_cxx="$$("$(OMNIVOX_TGSPEECHBOX_CXX)" --version | sed -n '1p')"; \
			tgspeechbox_cxx_path="$$(command -v "$(OMNIVOX_TGSPEECHBOX_CXX)")"; \
			tgspeechbox_cxx_digest="$$(sha256sum \
				"$$(readlink -f "$$tgspeechbox_cxx_path")" | cut -d ' ' -f1)"; \
		fi; \
		piper_companion=; \
		piper_companion_digest=not-included; \
		if [ "$(OMNIVOX_INCLUDE_PINNED_PIPER)" = 1 ]; then \
			piper_companion="$(OMNIVOX_PIPER_DIR)"; \
			if [ ! -f "$$piper_companion/omnivox-piper-helper.exe" ] || \
				[ ! -f "$$piper_companion/espeak-ng-data/phontab" ]; then \
				echo "Prepared Piper companion is incomplete: $$piper_companion" >&2; \
				exit 1; \
			fi; \
			piper_companion_digest="$$(cd "$$piper_companion" && \
				find . -type f -print0 | LC_ALL=C sort -z | \
				xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"; \
		fi; \
		espeak_phontab="$$(find \
			"$(OMNIVOX_RELEASE_TARGET_DIR)/release/build" \
			-path '*/espeak-rs-sys-*/out/share/espeak-ng-data/phontab' \
			-print -quit)"; \
		if [ -z "$$espeak_phontab" ]; then \
			echo "Could not locate native espeak-ng-data build output" >&2; \
			exit 1; \
		fi; \
		espeak_data="$${espeak_phontab%/phontab}"; \
		data_digest="$$(cd "$$espeak_data" && \
			find . -type f -print0 | LC_ALL=C sort -z | \
			xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"; \
		windows_local_app_data="$$(powershell.exe -NoProfile -NonInteractive \
			-Command '[Environment]::GetFolderPath("LocalApplicationData")' | \
			tr -d '\r')"; \
		if [ -z "$$windows_local_app_data" ]; then \
			echo "Could not locate Windows LocalAppData" >&2; \
			exit 1; \
		fi; \
		rhvoice_configuration_state=not-recorded; \
		rhvoice_library_digest=not-observed; \
		rhvoice_data_digest=not-observed; \
		rhvoice_config_digest=not-configured; \
		rhvoice_library_windows_path=; \
		rhvoice_data_windows_path=; \
		rhvoice_config_windows_path=; \
		if [ "$(OMNIVOX_RECORD_RHVOICE)" = 1 ] && \
			{ [ -n "$${OMNIVOX_RHVOICE_LIBRARY:-}" ] || \
			  [ -n "$${OMNIVOX_RHVOICE_DATA:-}" ] || \
			  [ -n "$${OMNIVOX_RHVOICE_CONFIG:-}" ]; }; then \
			if [ -z "$${OMNIVOX_RHVOICE_LIBRARY:-}" ] || \
				[ -z "$${OMNIVOX_RHVOICE_DATA:-}" ]; then \
				echo "Recording RHVoice requires OMNIVOX_RHVOICE_LIBRARY and OMNIVOX_RHVOICE_DATA" >&2; \
				exit 1; \
			fi; \
			rhvoice_library_source="$$OMNIVOX_RHVOICE_LIBRARY"; \
			if [ ! -f "$$rhvoice_library_source" ]; then \
				rhvoice_library_source="$$(wslpath -u \
					"$$OMNIVOX_RHVOICE_LIBRARY" 2>/dev/null || :)"; \
			fi; \
			case "$$rhvoice_library_source" in \
				*.[dD][lL][lL]) ;; \
				*) \
					echo "OMNIVOX_RHVOICE_LIBRARY must identify a readable RHVoice.dll" >&2; \
					exit 1 ;; \
			esac; \
			if [ ! -f "$$rhvoice_library_source" ]; then \
				echo "OMNIVOX_RHVOICE_LIBRARY does not identify a readable file" >&2; \
				exit 1; \
			fi; \
			rhvoice_data_source="$$OMNIVOX_RHVOICE_DATA"; \
			if [ ! -d "$$rhvoice_data_source" ]; then \
				rhvoice_data_source="$$(wslpath -u \
					"$$OMNIVOX_RHVOICE_DATA" 2>/dev/null || :)"; \
			fi; \
			if [ ! -d "$$rhvoice_data_source/languages" ] || \
				[ ! -d "$$rhvoice_data_source/voices" ]; then \
				echo "OMNIVOX_RHVOICE_DATA must contain languages and voices directories" >&2; \
				exit 1; \
			fi; \
			rhvoice_library_digest="$$(sha256sum \
				"$$rhvoice_library_source" | cut -d ' ' -f1)"; \
			rhvoice_data_digest="$$(cd "$$rhvoice_data_source" && \
				find . -type f -print0 | LC_ALL=C sort -z | \
				xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"; \
			rhvoice_library_windows_path="$$(wslpath -w \
				"$$rhvoice_library_source")"; \
			rhvoice_data_windows_path="$$(wslpath -w \
				"$$rhvoice_data_source")"; \
			if [ -n "$${OMNIVOX_RHVOICE_CONFIG:-}" ]; then \
				rhvoice_config_source="$$OMNIVOX_RHVOICE_CONFIG"; \
				if [ ! -d "$$rhvoice_config_source" ]; then \
					rhvoice_config_source="$$(wslpath -u \
						"$$OMNIVOX_RHVOICE_CONFIG" 2>/dev/null || :)"; \
				fi; \
				if [ ! -d "$$rhvoice_config_source" ]; then \
					echo "OMNIVOX_RHVOICE_CONFIG does not identify a readable directory" >&2; \
					exit 1; \
				fi; \
				rhvoice_config_digest="$$(cd "$$rhvoice_config_source" && \
					find . -type f -print0 | LC_ALL=C sort -z | \
					xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"; \
				rhvoice_config_windows_path="$$(wslpath -w \
					"$$rhvoice_config_source")"; \
			fi; \
			rhvoice_configuration_state=recorded-windows-paths; \
		fi; \
		piper_model_state=not-included; \
		piper_model_digest=not-configured; \
		piper_model_sha256=not-observed; \
		piper_model_config_sha256=not-observed; \
		piper_model_windows_path=; \
		piper_model_config_windows_path=; \
		if [ "$(OMNIVOX_INCLUDE_PINNED_PIPER)" = 1 ]; then \
			piper_model_state=external-user-supplied-not-configured; \
		elif [ -n "$${OMNIVOX_PIPER_MODEL:-}" ]; then \
			echo "OMNIVOX_PIPER_MODEL cannot be used when the development runtime omits Piper" >&2; \
			exit 1; \
		fi; \
		if [ "$(OMNIVOX_INCLUDE_PINNED_PIPER)" = 1 ] && \
			[ -n "$${OMNIVOX_PIPER_MODEL:-}" ]; then \
			piper_model_source="$$OMNIVOX_PIPER_MODEL"; \
			if [ ! -f "$$piper_model_source" ]; then \
				piper_model_source="$$(wslpath -u "$$OMNIVOX_PIPER_MODEL" 2>/dev/null || :)"; \
			fi; \
			case "$$piper_model_source" in \
				*.onnx) ;; \
				*) \
					echo "OMNIVOX_PIPER_MODEL must identify a readable .onnx file" >&2; \
					exit 1 ;; \
			esac; \
			if [ ! -f "$$piper_model_source" ]; then \
				echo "OMNIVOX_PIPER_MODEL does not identify a readable file" >&2; \
				exit 1; \
			fi; \
			if [ -f "$$piper_model_source.json" ]; then \
				piper_model_config_source="$$piper_model_source.json"; \
			elif [ -f "$${piper_model_source%.onnx}.json" ]; then \
				piper_model_config_source="$${piper_model_source%.onnx}.json"; \
			else \
				echo "Piper model configuration is not adjacent to $$piper_model_source" >&2; \
				exit 1; \
			fi; \
			piper_model_sha256="$$(sha256sum "$$piper_model_source" | cut -d ' ' -f1)"; \
			piper_model_config_sha256="$$(sha256sum \
				"$$piper_model_config_source" | cut -d ' ' -f1)"; \
			piper_model_digest="$$(printf '%s\n%s\n' \
				"$$piper_model_sha256" "$$piper_model_config_sha256" | \
				sha256sum | cut -d ' ' -f1)"; \
			piper_model_cache="$$(wslpath -u "$$windows_local_app_data")/Emacsvox/Omnivox/piper-models/$$piper_model_digest"; \
			mkdir -p "$$piper_model_cache"; \
			install_model_input() { \
				model_source=$$1; \
				model_destination="$$piper_model_cache/$${model_source##*/}"; \
				if [ ! -f "$$model_destination" ]; then \
					cp "$$model_source" "$$model_destination.new.$$$$"; \
					mv "$$model_destination.new.$$$$" "$$model_destination"; \
				fi; \
				if ! cmp -s "$$model_source" "$$model_destination"; then \
					echo "Existing content-addressed Piper model differs: $$model_destination" >&2; \
					exit 1; \
				fi; \
			}; \
			install_model_input "$$piper_model_source"; \
			install_model_input "$$piper_model_config_source"; \
			piper_model_windows_path="$$(wslpath -w \
				"$$piper_model_cache/$${piper_model_source##*/}")"; \
			piper_model_config_windows_path="$$(wslpath -w \
				"$$piper_model_cache/$${piper_model_config_source##*/}")"; \
			piper_model_state=external-user-supplied-windows-cache; \
		fi; \
		windows_cache_parent="$$(wslpath -u "$$windows_local_app_data")/Emacsvox/Omnivox/espeak-data/$$data_digest"; \
		mkdir -p "$$windows_cache_parent"; \
		if [ ! -f "$$windows_cache_parent/espeak-ng-data/phontab" ]; then \
			cache_stage="$$windows_cache_parent/espeak-ng-data.new.$$$$"; \
			cp -a "$$espeak_data" "$$cache_stage"; \
			mv "$$cache_stage" "$$windows_cache_parent/espeak-ng-data"; \
		fi; \
		espeak_identity="$$windows_cache_parent/omnivox-espeak-data.sha256"; \
		if [ ! -f "$$espeak_identity" ]; then \
			printf '%s\n' "$$data_digest" > "$$espeak_identity.new.$$$$"; \
			mv "$$espeak_identity.new.$$$$" "$$espeak_identity"; \
		fi; \
		if [ "$$(wc -l < "$$espeak_identity")" -ne 1 ] || \
			[ "$$(sed -n '1p' "$$espeak_identity")" != "$$data_digest" ]; then \
			echo "Existing eSpeak cache identity differs: $$espeak_identity" >&2; \
			exit 1; \
		fi; \
		windows_cache_path="$$(wslpath -w "$$windows_cache_parent")"; \
		emacsvox_commit="$$(git -C "$(CURDIR)" rev-parse HEAD)"; \
		omnivox_commit="$$(git -C "$(OMNIVOX_DIR)" rev-parse HEAD)"; \
		build_kind="$(OMNIVOX_BUILD_KIND)"; \
		emacsvox_worktree_digest="$$(git -C "$(CURDIR)" diff --binary HEAD -- | \
			sha256sum | cut -d ' ' -f1)"; \
		omnivox_worktree_digest="$$(git -C "$(OMNIVOX_DIR)" diff --binary HEAD -- | \
			sha256sum | cut -d ' ' -f1)"; \
		cargo_lock_digest="$$(sha256sum "$(OMNIVOX_DIR)/Cargo.lock" | cut -d ' ' -f1)"; \
		toolchain_lock_digest="$$(sha256sum "$(OMNIVOX_RELEASE_DIR)/toolchain.lock" | cut -d ' ' -f1)"; \
		dockerfile_digest="$$(sha256sum "$(OMNIVOX_RELEASE_DIR)/Dockerfile" | cut -d ' ' -f1)"; \
		release_image_id="$$(docker image inspect --format '{{.Id}}' "$(OMNIVOX_RELEASE_IMAGE)")"; \
		rustc_version="$$(docker run --rm --platform linux/amd64 \
			"$(OMNIVOX_RELEASE_IMAGE)" rustc --version)"; \
		mingw_version="$$(docker run --rm --platform linux/amd64 \
			"$(OMNIVOX_RELEASE_IMAGE)" \
			x86_64-w64-mingw32-gcc-win32 --version | sed -n '1p')"; \
		csc_digest="$$(sha256sum "$(OMNIVOX_CSC)" | cut -d ' ' -f1)"; \
		windows_csc="$$(wslpath -m "$(OMNIVOX_CSC)")"; \
		csc_version="$$(powershell.exe -NoProfile -NonInteractive -Command \
			"& '$$windows_csc' /version" | tr -d '\r')"; \
		executable_digest="$$(sha256sum "$$executable" | cut -d ' ' -f1)"; \
		unstripped_digest="$$(sha256sum "$$unstripped_executable" | cut -d ' ' -f1)"; \
		eloquence_runtime_digest=external-not-observed; \
		if [ -n "$${OMNIVOX_ECI_DLL:-}" ]; then \
			eci_file="$$OMNIVOX_ECI_DLL"; \
			if [ ! -f "$$eci_file" ]; then \
				eci_file="$$(wslpath -u "$$OMNIVOX_ECI_DLL")"; \
			fi; \
			if [ ! -f "$$eci_file" ]; then \
				echo "OMNIVOX_ECI_DLL does not identify a readable file" >&2; \
				exit 1; \
			fi; \
			eloquence_runtime_digest="$$(sha256sum "$$eci_file" | cut -d ' ' -f1)"; \
		fi; \
		build_id="$$( { \
			sha256sum "$$executable" "$$eloquence_helper" "$$dectalk_helper" \
				"$$helper_license" "$$omnivox_license" \
				"$$stdlib" "$$gcc_runtime" | cut -d ' ' -f1; \
			printf '%s\n' "$$rhvoice_companion_digest" \
				"$$flite_companion_digest" \
				"$$rutts_companion_digest" \
				"$$tgspeechbox_companion_digest" \
				"$$tgspeechbox_cxx" \
				"$$tgspeechbox_cxx_digest"; \
			if [ -f "$$dectalk_dll" ] && [ -f "$$dectalk_dictionary" ]; then \
				sha256sum "$$dectalk_dll" "$$dectalk_dictionary" | cut -d ' ' -f1; \
			else \
				printf '%s\n' no-dectalk-runtime; \
			fi; \
			printf '%s\n' "$$data_digest" "$$emacsvox_commit" \
				"$$omnivox_commit" "$$build_kind" \
				"$$emacsvox_worktree_digest" "$$omnivox_worktree_digest" \
				"$$cargo_lock_digest" \
				"$$toolchain_lock_digest" "$$dockerfile_digest" \
				"$$release_image_id" "$$csc_digest" \
				"$(roslyn_nupkg_sha256)" \
				"$(reference_assemblies_nupkg_sha256)" \
				"$$eloquence_runtime_digest" \
				"$(OMNIVOX_INCLUDE_PINNED_PIPER)" \
				"$(OMNIVOX_INCLUDE_TGSPEECHBOX)" \
				"$(omnivox_piper_archive_sha256)" \
				"$$piper_companion_digest" \
				"$$piper_model_digest" \
				"$$rhvoice_configuration_state" \
				"$$rhvoice_library_digest" "$$rhvoice_data_digest" \
				"$$rhvoice_config_digest" \
				"$$rhvoice_library_windows_path" \
				"$$rhvoice_data_windows_path" \
				"$$rhvoice_config_windows_path"; \
		} | sha256sum | cut -c1-16)"; \
		version_dir="$(OMNIVOX_RUNTIME_DIR)/versions/$$build_id"; \
		diagnostics_dir="$(OMNIVOX_RELEASE_DIR)/cache/diagnostics/$$build_id"; \
		windows_runtime_dir="$$(wslpath -u "$$windows_local_app_data")/Emacsvox/Omnivox/runtime/$$build_id"; \
		mkdir -p "$$diagnostics_dir"; \
		cp "$$unstripped_executable" \
			"$$diagnostics_dir/omnivox.unstripped.exe.new"; \
		mv -f "$$diagnostics_dir/omnivox.unstripped.exe.new" \
			"$$diagnostics_dir/omnivox.unstripped.exe"; \
		{ \
			printf '%s\n' \
				'format=emacsvox-omnivox-local-diagnostics-v1' \
				"build_id=$$build_id" \
				"emacsvox_commit=$$emacsvox_commit" \
				"omnivox_commit=$$omnivox_commit" \
				"build_kind=$$build_kind" \
				"emacsvox_worktree_sha256=$$emacsvox_worktree_digest" \
				"omnivox_worktree_sha256=$$omnivox_worktree_digest" \
				"deployed_omnivox_sha256=$$executable_digest" \
				"unstripped_omnivox_sha256=$$unstripped_digest"; \
		} > "$$diagnostics_dir/MANIFEST.new"; \
		mv -f "$$diagnostics_dir/MANIFEST.new" \
			"$$diagnostics_dir/MANIFEST"; \
		mkdir -p "$$version_dir"; \
		install_payload() { \
			payload_source=$$1; \
			payload_destination=$$2; \
			payload_mode=$$3; \
			if [ ! -f "$$payload_destination" ]; then \
				cp "$$payload_source" "$$payload_destination.new"; \
				mv -f "$$payload_destination.new" "$$payload_destination"; \
			fi; \
			if ! cmp -s "$$payload_source" "$$payload_destination"; then \
				echo "Existing content-addressed payload differs: $$payload_destination" >&2; \
				exit 1; \
			fi; \
			if [ "$$payload_mode" = executable ]; then \
				chmod +x "$$payload_destination"; \
			fi; \
		}; \
		install_payload "$$executable" "$$version_dir/omnivox.exe" executable; \
		install_payload "$$stdlib" "$$version_dir/libstdc++-6.dll" regular; \
		install_payload "$$gcc_runtime" \
			"$$version_dir/libgcc_s_seh-1.dll" regular; \
		install_payload "$$eloquence_helper" \
			"$$version_dir/OmnivoxEloquenceHelper32.exe" executable; \
		install_payload "$$dectalk_helper" \
			"$$version_dir/OmnivoxDectalkHelper32.exe" executable; \
		install_payload "$$helper_license" \
			"$$version_dir/WINDOWS-HELPERS-COPYING" regular; \
		install_payload "$$omnivox_license" \
			"$$version_dir/OMNIVOX-LICENSE" regular; \
		if [ -f "$$dectalk_dll" ] && [ -f "$$dectalk_dictionary" ]; then \
			install_payload "$$dectalk_dll" \
				"$$version_dir/DECtalk.dll" regular; \
			install_payload "$$dectalk_dictionary" \
				"$$version_dir/dtalk_us.dic" regular; \
		fi; \
		stage_companion() { \
			companion_name=$$1; \
			companion_source=$$2; \
			expected_companion_digest=$$3; \
			if [ ! -d "$$version_dir/$$companion_name" ]; then \
				companion_stage="$$version_dir/$$companion_name.new.$$$$"; \
				cp -a "$$companion_source" "$$companion_stage"; \
				mv "$$companion_stage" "$$version_dir/$$companion_name"; \
			fi; \
			version_companion_digest="$$(cd "$$version_dir/$$companion_name" && \
				find . -type f -print0 | LC_ALL=C sort -z | \
				xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"; \
			if [ "$$version_companion_digest" != "$$expected_companion_digest" ]; then \
				echo "Staged $$companion_name companion does not match its build output" >&2; \
				exit 1; \
			fi; \
		}; \
		stage_companion rhvoice "$$rhvoice_companion" \
			"$$rhvoice_companion_digest"; \
		stage_companion flite "$$flite_companion" \
			"$$flite_companion_digest"; \
		stage_companion rutts "$$rutts_companion" \
			"$$rutts_companion_digest"; \
		if [ "$(OMNIVOX_INCLUDE_TGSPEECHBOX)" = 1 ]; then \
			stage_companion tgspeechbox "$$tgspeechbox_companion" \
				"$$tgspeechbox_companion_digest"; \
		fi; \
		if [ "$(OMNIVOX_INCLUDE_PINNED_PIPER)" = 1 ]; then \
			if [ ! -d "$$version_dir/piper" ]; then \
				piper_stage="$$version_dir/piper.new.$$$$"; \
				cp -a "$$piper_companion" "$$piper_stage"; \
				mv "$$piper_stage" "$$version_dir/piper"; \
			fi; \
			version_piper_digest="$$(cd "$$version_dir/piper" && \
				find . -type f -print0 | LC_ALL=C sort -z | \
				xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"; \
			if [ "$$version_piper_digest" != "$$piper_companion_digest" ]; then \
				echo "Staged Piper companion does not match its pinned input" >&2; \
				exit 1; \
			fi; \
		fi; \
		if [ ! -f "$$version_dir/espeak-ng-data/phontab" ]; then \
			rm -rf "$$version_dir/espeak-ng-data.new"; \
			cp -a "$$espeak_data" "$$version_dir/espeak-ng-data.new"; \
			mv "$$version_dir/espeak-ng-data.new" \
				"$$version_dir/espeak-ng-data"; \
		fi; \
		version_data_digest="$$(cd "$$version_dir/espeak-ng-data" && \
			find . -type f -print0 | LC_ALL=C sort -z | \
			xargs -0 sha256sum | sha256sum | cut -d ' ' -f1)"; \
		if [ "$$version_data_digest" != "$$data_digest" ]; then \
			echo "Staged eSpeak data does not match its build input" >&2; \
			exit 1; \
		fi; \
		printf '%s\n' "$$windows_cache_path" \
			> "$$version_dir/espeak-ng-data.path.new"; \
		mv -f "$$version_dir/espeak-ng-data.path.new" \
			"$$version_dir/espeak-ng-data.path"; \
		if [ -n "$$rhvoice_library_windows_path" ]; then \
			printf '%s\n' "$$rhvoice_library_windows_path" \
				> "$$version_dir/rhvoice-library.path.new"; \
			mv -f "$$version_dir/rhvoice-library.path.new" \
				"$$version_dir/rhvoice-library.path"; \
			printf '%s\n' "$$rhvoice_data_windows_path" \
				> "$$version_dir/rhvoice-data.path.new"; \
			mv -f "$$version_dir/rhvoice-data.path.new" \
				"$$version_dir/rhvoice-data.path"; \
			if [ -n "$$rhvoice_config_windows_path" ]; then \
				printf '%s\n' "$$rhvoice_config_windows_path" \
					> "$$version_dir/rhvoice-config.path.new"; \
				mv -f "$$version_dir/rhvoice-config.path.new" \
					"$$version_dir/rhvoice-config.path"; \
			fi; \
		fi; \
		if [ -n "$$piper_model_windows_path" ]; then \
			printf '%s\n' "$$piper_model_windows_path" \
				> "$$version_dir/piper-model.path.new"; \
			mv -f "$$version_dir/piper-model.path.new" \
				"$$version_dir/piper-model.path"; \
			printf '%s\n' "$$piper_model_config_windows_path" \
				> "$$version_dir/piper-model-config.path.new"; \
			mv -f "$$version_dir/piper-model-config.path.new" \
				"$$version_dir/piper-model-config.path"; \
		fi; \
		dectalk_runtime=not-bundled; \
		if [ -f "$$version_dir/DECtalk.dll" ] && \
			[ -f "$$version_dir/dtalk_us.dic" ]; then \
			dectalk_runtime=bundled-pinned-archive; \
		fi; \
		omnivox_features=none; \
		piper_companion_state=not-included; \
		piper_version=not-included; \
		piper_commit=not-included; \
		piper_archive_digest=not-included; \
		if [ "$(OMNIVOX_INCLUDE_PINNED_PIPER)" = 1 ]; then \
			omnivox_features=piper; \
			piper_companion_state=official-omnivox-release; \
			piper_version=$(omnivox_piper_version); \
			piper_commit=$(omnivox_piper_commit); \
			piper_archive_digest=$(omnivox_piper_archive_sha256); \
		fi; \
		tgspeechbox_companion_state=not-included; \
		tgspeechbox_target=not-included; \
		tgspeechbox_markers=not-included; \
		tgspeechbox_rate_mapping=not-included; \
		if [ "$(OMNIVOX_INCLUDE_TGSPEECHBOX)" = 1 ]; then \
			tgspeechbox_companion_state=local-omnivox-experimental-build; \
			tgspeechbox_target=$(OMNIVOX_TARGET); \
			tgspeechbox_markers=none; \
			tgspeechbox_rate_mapping=provisional; \
		fi; \
		{ \
			printf '%s\n' \
				'format=emacsvox-omnivox-provenance-v1' \
				"build_id=$$build_id" \
				"emacsvox_commit=$$emacsvox_commit" \
				"omnivox_commit=$$omnivox_commit" \
				"build_kind=$$build_kind" \
				"emacsvox_worktree_sha256=$$emacsvox_worktree_digest" \
				"omnivox_worktree_sha256=$$omnivox_worktree_digest" \
				"cargo_lock_sha256=$$cargo_lock_digest" \
				"toolchain_lock_sha256=$$toolchain_lock_digest" \
				"dockerfile_sha256=$$dockerfile_digest" \
				"release_image_id=$$release_image_id" \
				"rustc=$$rustc_version" \
				"mingw_gcc=$$mingw_version" \
				"roslyn_csc=$$csc_version" \
				"roslyn_csc_sha256=$$csc_digest" \
				"roslyn_nupkg_sha256=$(roslyn_nupkg_sha256)" \
				"net40_reference_assemblies_nupkg_sha256=$(reference_assemblies_nupkg_sha256)" \
				"target=$(OMNIVOX_TARGET)" \
				"omnivox_features=$$omnivox_features" \
				"windows_rustflags=-C link-arg=-Wl,--no-insert-timestamp" \
				"windows_strip=SOURCE_DATE_EPOCH=0 x86_64-w64-mingw32-strip --strip-all" \
				"omnivox_executable_sha256=$$executable_digest" \
				"unstripped_diagnostics=retained-local-not-staged" \
				"espeak_data_sha256=$$data_digest" \
				'rhvoice_companion=local-omnivox-build' \
				"rhvoice_companion_tree_sha256=$$rhvoice_companion_digest" \
				'rhvoice_runtime=external-user-supplied-not-bundled' \
				"rhvoice_configuration=$$rhvoice_configuration_state" \
				"rhvoice_library_sha256=$$rhvoice_library_digest" \
				"rhvoice_data_tree_sha256=$$rhvoice_data_digest" \
				"rhvoice_config_tree_sha256=$$rhvoice_config_digest" \
				'flite_companion=local-omnivox-build' \
				"flite_companion_tree_sha256=$$flite_companion_digest" \
				'flite_target=x86_64-pc-windows-gnu' \
				'flite_compiled_voice=cmu_us_slt' \
				'rutts_companion=local-omnivox-build' \
				"rutts_companion_tree_sha256=$$rutts_companion_digest" \
				'rutts_target=x86_64-pc-windows-gnu' \
				'rutts_version=6.3.3' \
				'rutts_built_in_voices=male,female' \
				'rutts_rulex=not-included' \
				"tgspeechbox_companion=$$tgspeechbox_companion_state" \
				"tgspeechbox_companion_tree_sha256=$$tgspeechbox_companion_digest" \
				"tgspeechbox_target=$$tgspeechbox_target" \
				"tgspeechbox_markers=$$tgspeechbox_markers" \
				"tgspeechbox_rate_mapping=$$tgspeechbox_rate_mapping" \
				"tgspeechbox_build_environment=$$tgspeechbox_build_environment" \
				"tgspeechbox_cxx=$$tgspeechbox_cxx" \
				"tgspeechbox_cxx_sha256=$$tgspeechbox_cxx_digest" \
				"piper_companion=$$piper_companion_state" \
				"piper_companion_version=$$piper_version" \
				"piper_companion_commit=$$piper_commit" \
				"piper_companion_archive_sha256=$$piper_archive_digest" \
				"piper_companion_tree_sha256=$$piper_companion_digest" \
				"piper_model=$$piper_model_state" \
				"piper_model_sha256=$$piper_model_sha256" \
				"piper_model_config_sha256=$$piper_model_config_sha256" \
				"eloquence_runtime=external-user-supplied-not-bundled" \
				"eloquence_runtime_sha256=$$eloquence_runtime_digest" \
				"dectalk_runtime=$$dectalk_runtime" \
				'windows_helpers_source=omnivox' \
				'windows_helpers_license=GPL-2.0-or-later'; \
		} > "$$version_dir/PROVENANCE.new"; \
		mv -f "$$version_dir/PROVENANCE.new" "$$version_dir/PROVENANCE"; \
		payload_files='omnivox.exe libstdc++-6.dll libgcc_s_seh-1.dll OmnivoxEloquenceHelper32.exe OmnivoxDectalkHelper32.exe WINDOWS-HELPERS-COPYING OMNIVOX-LICENSE PROVENANCE'; \
		if [ "$$dectalk_runtime" = bundled-pinned-archive ]; then \
			payload_files="$$payload_files DECtalk.dll dtalk_us.dic"; \
		fi; \
		( \
			cd "$$version_dir"; \
			sha256sum $$payload_files; \
			find rhvoice flite rutts -type f -print0 | LC_ALL=C sort -z | \
				xargs -0 sha256sum; \
			if [ "$(OMNIVOX_INCLUDE_TGSPEECHBOX)" = 1 ]; then \
				find tgspeechbox -type f -print0 | LC_ALL=C sort -z | \
					xargs -0 sha256sum; \
			fi; \
			if [ "$(OMNIVOX_INCLUDE_PINNED_PIPER)" = 1 ]; then \
				find piper -type f -print0 | LC_ALL=C sort -z | \
					xargs -0 sha256sum; \
			fi; \
		) > "$$version_dir/SHA256SUMS.new"; \
		mv -f "$$version_dir/SHA256SUMS.new" "$$version_dir/SHA256SUMS"; \
		(cd "$$version_dir" && sha256sum --check SHA256SUMS); \
		mkdir -p "$$windows_runtime_dir"; \
		if [ ! -f "$$windows_runtime_dir/SHA256SUMS" ]; then \
			cp "$$version_dir/SHA256SUMS" \
				"$$windows_runtime_dir/SHA256SUMS.new.$$$$"; \
			mv "$$windows_runtime_dir/SHA256SUMS.new.$$$$" \
				"$$windows_runtime_dir/SHA256SUMS"; \
		fi; \
		if ! cmp -s "$$version_dir/SHA256SUMS" \
			"$$windows_runtime_dir/SHA256SUMS"; then \
			echo "Existing Windows-local SHA256SUMS differs" >&2; \
			exit 1; \
		fi; \
		while read -r _checksum runtime_file; do \
			runtime_destination="$$windows_runtime_dir/$$runtime_file"; \
			mkdir -p "$${runtime_destination%/*}"; \
			if [ ! -f "$$runtime_destination" ]; then \
				cp "$$version_dir/$$runtime_file" \
					"$$runtime_destination.new.$$$$"; \
				mv "$$runtime_destination.new.$$$$" \
					"$$runtime_destination"; \
			fi; \
			if ! cmp -s "$$version_dir/$$runtime_file" \
				"$$runtime_destination"; then \
				echo "Existing Windows-local payload differs: $$runtime_destination" >&2; \
				exit 1; \
			fi; \
		done < "$$version_dir/SHA256SUMS"; \
		windows_runtime_path="$$(wslpath -w "$$windows_runtime_dir")"; \
		printf '%s\n' "$$windows_runtime_path" \
			> "$$version_dir/windows-runtime.path.new"; \
		mv -f "$$version_dir/windows-runtime.path.new" \
			"$$version_dir/windows-runtime.path"; \
		ln -sfn "versions/$$build_id" "$(OMNIVOX_RUNTIME_DIR)/current.new"; \
		mv -Tf "$(OMNIVOX_RUNTIME_DIR)/current.new" \
			"$(OMNIVOX_RUNTIME_DIR)/current"; \
		chmod +x servers/omnivox; \
		echo "Staged Omnivox runtime $$build_id"
	$(MAKE) verify-windows-omnivox-runtime
	$(MAKE) verify-windows-omnivox-live

verify-windows-omnivox-runtime:
	"$(OMNIVOX_RELEASE_DIR)/verify-runtime.sh" \
		"$(OMNIVOX_RUNTIME_DIR)" "$(OMNIVOX_RELEASE_DIR)"

verify-windows-omnivox-live:
	"$(OMNIVOX_RELEASE_DIR)/verify-runtime-live.sh" \
		"$(OMNIVOX_RUNTIME_DIR)" "$(OMNIVOX_RELEASE_DIR)"

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
	@cd lisp && $(MAKE) config $(MAKEFLAGS)

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

release: release-artifact
	@echo "Artifact ready; run make release-tag only after inspecting it."

release-tag: release-artifact-check
	@utils/emacsvox-version-check --tag
	git tag -a "$(VERSION)" -m "Emacsvox $(VERSION)"
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
	@echo "This release requires Emacs 31 or later."
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
