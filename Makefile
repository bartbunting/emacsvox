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
MINGW_CXX ?= x86_64-w64-mingw32-g++

windows-omnivox:
	$(MAKE) -C servers/windows-eloquence omnivox-helper
	$(MAKE) -C servers/windows-dectalk omnivox-helper
	cd "$(OMNIVOX_DIR)" && cargo build --locked --release -p omnivox-cli
	cd "$(OMNIVOX_DIR)" && \
		CC_x86_64_pc_windows_gnu=x86_64-w64-mingw32-gcc \
		CXX_x86_64_pc_windows_gnu=$(MINGW_CXX) \
		AR_x86_64_pc_windows_gnu=x86_64-w64-mingw32-ar \
		CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=x86_64-w64-mingw32-gcc \
		cargo build --locked --release -p omnivox-cli \
			--target $(OMNIVOX_TARGET)
	@set -eu; \
		executable="$(OMNIVOX_DIR)/target/$(OMNIVOX_TARGET)/release/omnivox.exe"; \
		eloquence_helper="$(CURDIR)/servers/windows-eloquence/bin/OmnivoxEloquenceHelper32.exe"; \
		dectalk_helper="$(CURDIR)/servers/windows-dectalk/bin/OmnivoxDectalkHelper32.exe"; \
		dectalk_dll="$(CURDIR)/servers/windows-dectalk/runtime/DECtalk.dll"; \
		dectalk_dictionary="$(CURDIR)/servers/windows-dectalk/runtime/dtalk_us.dic"; \
		stdlib="$$($(MINGW_CXX) -print-file-name=libstdc++-6.dll)"; \
		gcc_runtime="$$($(MINGW_CXX) -print-file-name=libgcc_s_seh-1.dll)"; \
		espeak_phontab="$$(find \
			"$(OMNIVOX_DIR)/target/release/build" \
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
		build_id="$$( { \
			sha256sum "$$executable" "$$eloquence_helper" "$$dectalk_helper" \
				"$$stdlib" "$$gcc_runtime" | cut -d ' ' -f1; \
			if [ -f "$$dectalk_dll" ] && [ -f "$$dectalk_dictionary" ]; then \
				sha256sum "$$dectalk_dll" "$$dectalk_dictionary" | cut -d ' ' -f1; \
			else \
				printf '%s\n' no-dectalk-runtime; \
			fi; \
			printf '%s\n' "$$data_digest"; \
		} | sha256sum | cut -c1-16)"; \
		version_dir="$(OMNIVOX_RUNTIME_DIR)/versions/$$build_id"; \
		windows_runtime_dir="$$(wslpath -u "$$windows_local_app_data")/Emacsvox/Omnivox/runtime/$$build_id"; \
		mkdir -p "$$version_dir"; \
		if [ ! -x "$$version_dir/omnivox.exe" ]; then \
			cp "$$executable" "$$version_dir/omnivox.exe.new"; \
			chmod +x "$$version_dir/omnivox.exe.new"; \
			mv -f "$$version_dir/omnivox.exe.new" "$$version_dir/omnivox.exe"; \
		fi; \
		if [ ! -f "$$version_dir/libstdc++-6.dll" ]; then \
			cp "$$stdlib" "$$version_dir/libstdc++-6.dll.new"; \
			mv -f "$$version_dir/libstdc++-6.dll.new" \
				"$$version_dir/libstdc++-6.dll"; \
		fi; \
		if [ ! -f "$$version_dir/libgcc_s_seh-1.dll" ]; then \
			cp "$$gcc_runtime" "$$version_dir/libgcc_s_seh-1.dll.new"; \
			mv -f "$$version_dir/libgcc_s_seh-1.dll.new" \
				"$$version_dir/libgcc_s_seh-1.dll"; \
		fi; \
		if [ ! -x "$$version_dir/OmnivoxEloquenceHelper32.exe" ]; then \
			cp "$$eloquence_helper" \
				"$$version_dir/OmnivoxEloquenceHelper32.exe.new"; \
			chmod +x "$$version_dir/OmnivoxEloquenceHelper32.exe.new"; \
			mv -f "$$version_dir/OmnivoxEloquenceHelper32.exe.new" \
				"$$version_dir/OmnivoxEloquenceHelper32.exe"; \
		fi; \
		if [ ! -x "$$version_dir/OmnivoxDectalkHelper32.exe" ]; then \
			cp "$$dectalk_helper" \
				"$$version_dir/OmnivoxDectalkHelper32.exe.new"; \
			chmod +x "$$version_dir/OmnivoxDectalkHelper32.exe.new"; \
			mv -f "$$version_dir/OmnivoxDectalkHelper32.exe.new" \
				"$$version_dir/OmnivoxDectalkHelper32.exe"; \
		fi; \
		if [ -f "$$dectalk_dll" ] && [ -f "$$dectalk_dictionary" ]; then \
			if [ ! -f "$$version_dir/DECtalk.dll" ]; then \
				cp "$$dectalk_dll" "$$version_dir/DECtalk.dll.new"; \
				mv -f "$$version_dir/DECtalk.dll.new" \
					"$$version_dir/DECtalk.dll"; \
			fi; \
			if [ ! -f "$$version_dir/dtalk_us.dic" ]; then \
				cp "$$dectalk_dictionary" \
					"$$version_dir/dtalk_us.dic.new"; \
				mv -f "$$version_dir/dtalk_us.dic.new" \
					"$$version_dir/dtalk_us.dic"; \
			fi; \
		fi; \
		if [ ! -f "$$version_dir/espeak-ng-data/phontab" ]; then \
			rm -rf "$$version_dir/espeak-ng-data.new"; \
			cp -a "$$espeak_data" "$$version_dir/espeak-ng-data.new"; \
			mv "$$version_dir/espeak-ng-data.new" \
				"$$version_dir/espeak-ng-data"; \
		fi; \
		printf '%s\n' "$$windows_cache_path" \
			> "$$version_dir/espeak-ng-data.path.new"; \
		mv -f "$$version_dir/espeak-ng-data.path.new" \
			"$$version_dir/espeak-ng-data.path"; \
		mkdir -p "$$windows_runtime_dir"; \
		for runtime_file in omnivox.exe libstdc++-6.dll libgcc_s_seh-1.dll \
			OmnivoxEloquenceHelper32.exe OmnivoxDectalkHelper32.exe; do \
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
