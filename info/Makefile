#$Id$
# Note: Building the info pages requires package hydra to be installed.
# Built info pages are checked into GitHub.
# You should need to rebuild info files
#*only* if you change the Emacsvox Lisp sources.
# Historical Emacspeak documents retain their original names.
SF_HOME= raman,emacspeak@web.sourceforge.net:/home/groups/e/em/emacspeak/htdocs/info
# Emacsvox manual publication checkout.
GH_PAGES=../../gh-pages-emacsvox/manual
BATCH = -batch -q -no-site-file     \
--eval '(setq file-name-handler-alist nil gc-cons-threshold 128000000)'
FILES=*.texi
INCLUDES= style.texi preamble.texi copyright.texi announce.texi emacspeak-significance.texi \
introduction.texi install.texi using.texi audio-desktop.texi voices.texi online-help.texi \
packages.texi notmuch.texi agent-shell.texi eat.texi eterm.texi docs.texi keyboard.texi tts-server.texi \
inc-turning-twenty.texi acknowledge.texi intro-docs.texi documents.texi structure.texi \
web-browsing.texi tts.texi

MAKEINFO = makeinfo 
STRIP_TRAILING_WHITESPACE = perl -pi -e 's/[ \t]+$$//'
CSS=--css-ref="http://www.w3.org/StyleSheets/Core/Modernist"
EMACS=emacs

all: info  introducing-emacspeak.info turning-twenty.info #emacsvox.pdf

info: emacsvox.info

emacsvox.info: emacsvox.texi $(INCLUDES)
	$(MAKEINFO) emacsvox.texi
	$(STRIP_TRAILING_WHITESPACE) emacsvox.info*

introducing-emacspeak.info: introducing-emacspeak.texi
	$(MAKEINFO) introducing-emacspeak.texi	
	$(STRIP_TRAILING_WHITESPACE) introducing-emacspeak.info

turning-twenty.info: turning-twenty.texi
	$(MAKEINFO) turning-twenty.texi
	$(STRIP_TRAILING_WHITESPACE) turning-twenty.info
force:

docs.texi:force
	$(EMACS) $(BATCH) -l ../utils/self-document.el -f self-document-all-modules
pdf: emacsvox.pdf
	cp emacsvox.pdf $(GH_PAGES)/
emacsvox.pdf: emacsvox.texi $(INCLUDES)
	makeinfo --pdf emacsvox.texi
	\rm emacsvox.aux emacsvox.cp emacsvox.cps emacsvox.fn \
emacsvox.fns emacsvox.ky emacsvox.kys emacsvox.log \
emacsvox.toc emacsvox.vr emacsvox.vrs

man:
	makeinfo -o ${GH_PAGES} --html ${CSS} emacsvox.texi
	tidy -q -utf8 -mic -asxml  ${GH_PAGES}/*.html 2>&1 > /dev/null  || echo tidy
	@echo "Commit and push updated HTML files from gh-pages!"

publish:
	cd ../../gh-pages-emacsvox && make

introducing-emacspeak.html: introducing-emacspeak.texi
	makeinfo --no-split --html  introducing-emacspeak.texi
#For publishing to SF
pub:  html/index.html introducing-emacspeak.html
	rsync introducing-emacspeak.html ${SF_HOME}
	rsync -avz  html ${SF_HOME}/info/


clean:
	\rm emacsvox.info* emacsvox.pdf || echo "all clean"

spell:
	codespell -I .codespell *.texi


tags:
	etags *.texi
