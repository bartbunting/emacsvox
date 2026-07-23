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

.PHONY: test
test:
	$(EMACS) -Q --batch -l test/run-tests.el

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
