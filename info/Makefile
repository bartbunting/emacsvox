#$Id$
# Built Info pages are checked into GitHub.  Run `make docs-generate` from the
# repository root after changing public Lisp documentation or manual sources.
# Historical Emacspeak documents retain their original names.
SF_HOME= raman,emacspeak@web.sourceforge.net:/home/groups/e/em/emacspeak/htdocs/info
# Compatibility input for the old info-level publication target.  Prefer the
# root `docs-publish` target; this path is intentionally not defaulted.
GH_PAGES ?=
FILES=*.texi
USER_INCLUDES= style.texi preamble.texi copyright.texi announce.texi \
introduction.texi install.texi backends.texi using.texi audio-desktop.texi \
voices.texi online-help.texi applications.texi \
notmuch.texi agent-shell.texi eat.texi term.texi keyboard.texi \
tts-server.texi acknowledge.texi tts.texi
REFERENCE_INCLUDES= style.texi docs.texi keys.texi intro-docs.texi
HERITAGE_INCLUDES= style.texi emacspeak-significance.texi \
inc-turning-twenty.texi packages.texi documents.texi structure.texi \
web-browsing.texi eterm.texi
INCLUDES= $(USER_INCLUDES) $(REFERENCE_INCLUDES) $(HERITAGE_INCLUDES)

MAKEINFO ?= makeinfo
NORMALIZE_INFO = perl -0777 -pi -e 's/[ \t]+$$//mg; s/\n+\z/\n/'

all: info introducing-emacspeak.info turning-twenty.info #emacsvox.pdf

info: emacsvox.info emacsvox-reference.info emacsvox-heritage.info

emacsvox.info: emacsvox.texi $(USER_INCLUDES)
	@set -eu; \
		info_staging=$$(mktemp -d ./.emacsvox-info.XXXXXX); \
		trap 'rm -rf "$$info_staging"' 0 1 2 3 15; \
		$(MAKEINFO) --output="$$info_staging/emacsvox.info" emacsvox.texi; \
		$(NORMALIZE_INFO) "$$info_staging"/emacsvox.info*; \
		rm -f emacsvox.info emacsvox.info-[0-9]*; \
		for info_file in "$$info_staging"/emacsvox.info*; do \
			cp "$$info_file" .; \
		done

emacsvox-reference.info: emacsvox-reference.texi $(REFERENCE_INCLUDES)
	@set -eu; \
		info_staging=$$(mktemp -d ./.emacsvox-reference-info.XXXXXX); \
		trap 'rm -rf "$$info_staging"' 0 1 2 3 15; \
		$(MAKEINFO) --output="$$info_staging/emacsvox-reference.info" \
			emacsvox-reference.texi; \
		$(NORMALIZE_INFO) \
			"$$info_staging"/emacsvox-reference.info*; \
		rm -f emacsvox-reference.info emacsvox-reference.info-[0-9]*; \
		for info_file in "$$info_staging"/emacsvox-reference.info*; do \
			cp "$$info_file" .; \
		done

emacsvox-heritage.info: emacsvox-heritage.texi $(HERITAGE_INCLUDES)
	@set -eu; \
		heritage_staging=$$(mktemp -d ./.emacsvox-heritage-info.XXXXXX); \
		trap 'rm -rf "$$heritage_staging"' 0 1 2 3 15; \
		$(MAKEINFO) --output="$$heritage_staging/emacsvox-heritage.info" \
			emacsvox-heritage.texi; \
		$(NORMALIZE_INFO) "$$heritage_staging"/emacsvox-heritage.info*; \
		rm -f emacsvox-heritage.info emacsvox-heritage.info-[0-9]*; \
		for info_file in "$$heritage_staging"/emacsvox-heritage.info*; do \
			cp "$$info_file" .; \
		done

introducing-emacspeak.info: introducing-emacspeak.texi
	$(MAKEINFO) introducing-emacspeak.texi	
	$(NORMALIZE_INFO) introducing-emacspeak.info

turning-twenty.info: turning-twenty.texi
	$(MAKEINFO) turning-twenty.texi
	$(NORMALIZE_INFO) turning-twenty.info
pdf:
	@if test -z "$(GH_PAGES)"; then \
		echo "Set GH_PAGES to an existing publication directory." >&2; \
		exit 2; \
	fi
	$(MAKE) emacsvox.pdf
	cp emacsvox.pdf $(GH_PAGES)/
emacsvox.pdf: emacsvox.texi $(USER_INCLUDES)
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
	\rm emacsvox.info* emacsvox-reference.info* emacsvox-heritage.info* \
		emacsvox.pdf || echo "all clean"

spell:
	codespell -I .codespell *.texi


tags:
	etags *.texi
