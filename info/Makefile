#$Id$
# Built Info pages are checked into GitHub.  Run `make docs-generate` from the
# repository root after changing public Lisp documentation or manual sources.
# Historical Emacspeak documents retain their original names.
SF_HOME= raman,emacspeak@web.sourceforge.net:/home/groups/e/em/emacspeak/htdocs/info
# Compatibility input for the old info-level publication target.  Prefer the
# root `docs-publish` target; this path is intentionally not defaulted.
GH_PAGES ?=
FILES=*.texi
INCLUDES= style.texi preamble.texi copyright.texi announce.texi emacspeak-significance.texi \
introduction.texi install.texi backends.texi using.texi audio-desktop.texi voices.texi online-help.texi \
packages.texi notmuch.texi agent-shell.texi eat.texi eterm.texi docs.texi keys.texi keyboard.texi tts-server.texi \
inc-turning-twenty.texi acknowledge.texi intro-docs.texi documents.texi structure.texi \
web-browsing.texi tts.texi

MAKEINFO ?= makeinfo
STRIP_TRAILING_WHITESPACE = perl -pi -e 's/[ \t]+$$//'

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
pdf:
	@if test -z "$(GH_PAGES)"; then \
		echo "Set GH_PAGES to an existing publication directory." >&2; \
		exit 2; \
	fi
	$(MAKE) emacsvox.pdf
	cp emacsvox.pdf $(GH_PAGES)/
emacsvox.pdf: emacsvox.texi $(INCLUDES)
	$(MAKEINFO) --pdf emacsvox.texi
	\rm emacsvox.aux emacsvox.cp emacsvox.cps emacsvox.fn \
emacsvox.fns emacsvox.ky emacsvox.kys emacsvox.log \
emacsvox.toc emacsvox.vr emacsvox.vrs

man:
	@if test -z "$(GH_PAGES)"; then \
		echo "Use root target docs-publish with DOCS_PUBLISH_DIR=/path/to/manual." >&2; \
		exit 2; \
	fi
	@destination=$$(cd "$(GH_PAGES)" && pwd -P) && \
		$(MAKE) -C .. DOCS_PUBLISH_DIR="$$destination" docs-publish

publish: man

introducing-emacspeak.html: introducing-emacspeak.texi
	$(MAKEINFO) --no-split --html introducing-emacspeak.texi
# Historical Emacspeak SourceForge publication target.
pub:  html/index.html introducing-emacspeak.html
	rsync introducing-emacspeak.html ${SF_HOME}
	rsync -avz  html ${SF_HOME}/info/


clean:
	\rm emacsvox.info* emacsvox.pdf || echo "all clean"

spell:
	codespell -I .codespell *.texi


tags:
	etags *.texi
