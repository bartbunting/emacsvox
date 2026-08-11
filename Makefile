# $Author: tv.raman.tv $
# Description:  Makefile for Emacsvox
# Keywords: Emacsvox,  TTS,Makefile
###  LCD Entry:

# LCD Archive Entry:
# emacsvox| T. V. Raman |raman@cs.cornell.edu
# A speech interface to Emacs |
# Location https://github.com/tvraman/emacsvox
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
EMACS=emacs
README = README

### Tests

TRACE_GOLDEN=test/golden/emacsvox-core.eld
EMACSPEAK_TRACE_GOLDEN=test/golden/emacspeak-core.eld

.PHONY: test unit-test compiled-aural-test build-aural-test trace trace-test reference-test advice-audit name-audit tts-audit
.PHONY: aural-audit aural-reference windows-speech windows-audio windows-outloud windows-dtk windows-omnivox
.PHONY: verify-windows-omnivox-toolchain verify-windows-omnivox-helpers verify-windows-omnivox-runtime
.PHONY: clean-windows-speech clean-windows-audio clean-windows-outloud clean-windows-dtk clean-windows-omnivox
test: unit-test compiled-aural-test build-aural-test trace-test

unit-test:
	$(EMACS) -Q --batch -l test/run-tests.el

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

emacsvox: config 
	@cd lisp && $(MAKE) $(MAKEFLAGS)
	@make   $(README)
	@chmod 644 $(README)
	@echo "See the NEWS file for a  summary of new features — Control e cap n in Emacs"
	@echo "See Emacsvox Customizations for customizations — control e cap C in Emacs"
	@echo  "Read the Emacsvox Manual — Control e TAB in Emacs"
	@make install

swiftmac:
	@cd servers/mac-swiftmac && $(MAKE) $(MAKEFLAGS) || echo "Can't build swiftmac server!"

outloud: 
	@cd servers/linux-outloud && $(MAKE) $(MAKEFLAGS) || echo "Can't build Outloud server!"

espeak: 
	@cd servers/native-espeak && $(MAKE) $(MAKEFLAGS)  || echo "Can't build espeak server!"

dtk: 
	@cd servers/software-dtk && $(MAKE) $(MAKEFLAGS)  || echo "Can't build DTK server!"

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
include $(OMNIVOX_RELEASE_DIR)/toolchain.lock
OMNIVOX_CSC = $(OMNIVOX_RELEASE_DIR)/cache/roslyn-$(roslyn_version)/tasks/net472/csc.exe
OMNIVOX_REFERENCE_DIR = $(OMNIVOX_RELEASE_DIR)/cache/net40-reference-assemblies-$(reference_assemblies_version)/build/.NETFramework/v4.0

verify-windows-omnivox-toolchain:
	OMNIVOX_RELEASE_IMAGE="$(OMNIVOX_RELEASE_IMAGE)" \
		"$(OMNIVOX_RELEASE_DIR)/verify-toolchain.sh"

verify-windows-omnivox-helpers:
	"$(OMNIVOX_RELEASE_DIR)/verify-helper-determinism.sh" \
		"$(CURDIR)" "$(OMNIVOX_CSC)" "$(OMNIVOX_REFERENCE_DIR)"

windows-omnivox:
	@set -eu; \
		for repository in "$(CURDIR)" "$(OMNIVOX_DIR)"; do \
			if ! git -C "$$repository" diff --quiet --ignore-submodules -- || \
				! git -C "$$repository" diff --cached --quiet --ignore-submodules --; then \
				echo "Refusing to stage Omnivox from tracked changes in $$repository" >&2; \
				exit 1; \
			fi; \
		done
	$(MAKE) verify-windows-omnivox-toolchain
	$(MAKE) verify-windows-omnivox-helpers
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
			cargo build --locked --release -p omnivox-cli \
				--target $(OMNIVOX_TARGET); \
			cp "$$CARGO_TARGET_DIR/$(OMNIVOX_TARGET)/release/omnivox.exe" \
				"$$CARGO_TARGET_DIR/$(OMNIVOX_TARGET)/release/omnivox.unstripped.exe"; \
			SOURCE_DATE_EPOCH=0 x86_64-w64-mingw32-strip --strip-all \
				"$$CARGO_TARGET_DIR/$(OMNIVOX_TARGET)/release/omnivox.exe"; \
			mkdir -p "$$CARGO_TARGET_DIR/windows-runtime"; \
			cp "$$(x86_64-w64-mingw32-g++-win32 -print-file-name=libstdc++-6.dll)" \
				"$$CARGO_TARGET_DIR/windows-runtime/libstdc++-6.dll"; \
			cp "$$(x86_64-w64-mingw32-g++-win32 -print-file-name=libgcc_s_seh-1.dll)" \
				"$$CARGO_TARGET_DIR/windows-runtime/libgcc_s_seh-1.dll"; \
		'
	@set -eu; \
		executable="$(OMNIVOX_RELEASE_TARGET_DIR)/$(OMNIVOX_TARGET)/release/omnivox.exe"; \
		unstripped_executable="$(OMNIVOX_RELEASE_TARGET_DIR)/$(OMNIVOX_TARGET)/release/omnivox.unstripped.exe"; \
		eloquence_helper="$(CURDIR)/servers/windows-eloquence/bin/OmnivoxEloquenceHelper32.exe"; \
		dectalk_helper="$(CURDIR)/servers/windows-dectalk/bin/OmnivoxDectalkHelper32.exe"; \
		dectalk_dll="$(CURDIR)/servers/windows-dectalk/runtime/DECtalk.dll"; \
		dectalk_dictionary="$(CURDIR)/servers/windows-dectalk/runtime/dtalk_us.dic"; \
		stdlib="$(OMNIVOX_RELEASE_TARGET_DIR)/windows-runtime/libstdc++-6.dll"; \
		gcc_runtime="$(OMNIVOX_RELEASE_TARGET_DIR)/windows-runtime/libgcc_s_seh-1.dll"; \
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
		windows_cache_parent="$$(wslpath -u "$$windows_local_app_data")/Emacsvox/Omnivox/espeak-data/$$data_digest"; \
		mkdir -p "$$windows_cache_parent"; \
		if [ ! -f "$$windows_cache_parent/espeak-ng-data/phontab" ]; then \
			cache_stage="$$windows_cache_parent/espeak-ng-data.new.$$$$"; \
			cp -a "$$espeak_data" "$$cache_stage"; \
			mv "$$cache_stage" "$$windows_cache_parent/espeak-ng-data"; \
		fi; \
		windows_cache_path="$$(wslpath -w "$$windows_cache_parent")"; \
		emacsvox_commit="$$(git -C "$(CURDIR)" rev-parse HEAD)"; \
		omnivox_commit="$$(git -C "$(OMNIVOX_DIR)" rev-parse HEAD)"; \
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
				"$$stdlib" "$$gcc_runtime" | cut -d ' ' -f1; \
			if [ -f "$$dectalk_dll" ] && [ -f "$$dectalk_dictionary" ]; then \
				sha256sum "$$dectalk_dll" "$$dectalk_dictionary" | cut -d ' ' -f1; \
			else \
				printf '%s\n' no-dectalk-runtime; \
			fi; \
			printf '%s\n' "$$data_digest" "$$emacsvox_commit" \
				"$$omnivox_commit" "$$cargo_lock_digest" \
				"$$toolchain_lock_digest" "$$dockerfile_digest" \
				"$$release_image_id" "$$csc_digest" \
				"$(roslyn_nupkg_sha256)" \
				"$(reference_assemblies_nupkg_sha256)" \
				"$$eloquence_runtime_digest"; \
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
		if [ -f "$$dectalk_dll" ] && [ -f "$$dectalk_dictionary" ]; then \
			install_payload "$$dectalk_dll" \
				"$$version_dir/DECtalk.dll" regular; \
			install_payload "$$dectalk_dictionary" \
				"$$version_dir/dtalk_us.dic" regular; \
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
		dectalk_runtime=not-bundled; \
		if [ -f "$$version_dir/DECtalk.dll" ] && \
			[ -f "$$version_dir/dtalk_us.dic" ]; then \
			dectalk_runtime=bundled-pinned-archive; \
		fi; \
		{ \
			printf '%s\n' \
				'format=emacsvox-omnivox-provenance-v1' \
				"build_id=$$build_id" \
				"emacsvox_commit=$$emacsvox_commit" \
				"omnivox_commit=$$omnivox_commit" \
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
				"windows_rustflags=-C link-arg=-Wl,--no-insert-timestamp" \
				"windows_strip=SOURCE_DATE_EPOCH=0 x86_64-w64-mingw32-strip --strip-all" \
				"omnivox_executable_sha256=$$executable_digest" \
				"unstripped_diagnostics=retained-local-not-staged" \
				"espeak_data_sha256=$$data_digest" \
				"eloquence_runtime=external-user-supplied-not-bundled" \
				"eloquence_runtime_sha256=$$eloquence_runtime_digest" \
				"dectalk_runtime=$$dectalk_runtime"; \
		} > "$$version_dir/PROVENANCE.new"; \
		mv -f "$$version_dir/PROVENANCE.new" "$$version_dir/PROVENANCE"; \
		payload_files='omnivox.exe libstdc++-6.dll libgcc_s_seh-1.dll OmnivoxEloquenceHelper32.exe OmnivoxDectalkHelper32.exe PROVENANCE'; \
		if [ "$$dectalk_runtime" = bundled-pinned-archive ]; then \
			payload_files="$$payload_files DECtalk.dll dtalk_us.dic"; \
		fi; \
		(cd "$$version_dir" && sha256sum $$payload_files) \
			> "$$version_dir/SHA256SUMS.new"; \
		mv -f "$$version_dir/SHA256SUMS.new" "$$version_dir/SHA256SUMS"; \
		(cd "$$version_dir" && sha256sum --check SHA256SUMS); \
		mkdir -p "$$windows_runtime_dir"; \
		for runtime_file in omnivox.exe libstdc++-6.dll libgcc_s_seh-1.dll \
			OmnivoxEloquenceHelper32.exe OmnivoxDectalkHelper32.exe \
			PROVENANCE SHA256SUMS; do \
			if [ ! -f "$$windows_runtime_dir/$$runtime_file" ]; then \
				cp "$$version_dir/$$runtime_file" \
					"$$windows_runtime_dir/$$runtime_file.new.$$$$"; \
				mv "$$windows_runtime_dir/$$runtime_file.new.$$$$" \
					"$$windows_runtime_dir/$$runtime_file"; \
			fi; \
		done; \
		for runtime_file in DECtalk.dll dtalk_us.dic; do \
			if [ -f "$$version_dir/$$runtime_file" ] && \
				[ ! -f "$$windows_runtime_dir/$$runtime_file" ]; then \
				cp "$$version_dir/$$runtime_file" \
					"$$windows_runtime_dir/$$runtime_file.new.$$$$"; \
				mv "$$windows_runtime_dir/$$runtime_file.new.$$$$" \
					"$$windows_runtime_dir/$$runtime_file"; \
			fi; \
		done; \
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

verify-windows-omnivox-runtime:
	"$(OMNIVOX_RELEASE_DIR)/verify-runtime.sh" \
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

###   Maintenance targets:   dist

GITVERSION=$(shell git show HEAD | head -1  | cut -b 8- )
README: 
	@rm -f README
	@echo "Emacsvox  Revision $(GITVERSION)" > $(README)
	@echo "This release requires Emacs 29.1 or later."  > $(README)
	@echo "Distribution created by `whoami` at `date`" >> $(README)
	@echo "Unpack the  distribution And type make config " >> $(README)
	@echo "Then type make" >> $(README)
EXCLUDES=-X .excludes --exclude-backups
dist:
	make ${README}
	tar cvf  emacsvox.tar $(EXCLUDES) .

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

i:
	cd info && make && git ci docs || true
	cd info && make man
	cd ../gh-pages-emacsvox  && make && git ci docs || true

###   user level target-- clean

clean:
	@cd lisp &&  $(MAKE) $(MAKEFLAGS) clean

###  labeling releases

#label  releases when ready
LABEL=#version number
MSG="Releasing ${LABEL}"
release: #supply LABEL=NN.NN
	git tag -a -s ${LABEL} -m "Tagging release with ${LABEL}"
	git push --tags
	$(MAKE) dist
	mkdir emacsvox-${LABEL}; \
cd emacsvox-${LABEL} ;\
	tar xvf ../emacsvox.tar ; \
	rm -f ../emacsvox.tar ; \
cd .. ;\
	tar cvfj emacsvox-${LABEL}.tar.bz2 emacsvox-$(LABEL); \
	/bin/rm -rf emacsvox-${LABEL} ;\
	echo "Prepared release in emacsvox-${LABEL}.tar.bz2"
	./utils/emacsvox-ghr ${LABEL} "emacsvox-${LABEL}.tar.bz2"

### Install: 

install:
	@echo "This release requires Emacs 31 or later."
	@echo "You need SoX installed to play OGG and WAV files."
	@echo "You need curl installed for some Internet features."
	@echo "To run  this Emacsvox build, add this  line to the top of your .emacs:"
	@echo "(load-file \"`pwd`/lisp/emacsvox-setup.el\")"
	@echo "    Type make  <engine> [dtk, outloud,  espeak, swiftmac] to build TTS server. "
	@echo "Package maintainers: see   etc/install.org	 for instructions."

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
