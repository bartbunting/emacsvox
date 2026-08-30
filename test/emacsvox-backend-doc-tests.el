;;; emacsvox-backend-doc-tests.el --- Backend documentation tests -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Keep the initial-user backend recommendation coherent with the runtime
;; selector and the installed manual topology.

;;; Code:

(require 'ert)
(require 'tts-speak)

(defconst emacsvox-backend-doc-tests--root
  (file-name-as-directory
   (expand-file-name
    "../" (file-name-directory (or load-file-name buffer-file-name))))
  "Repository root used by backend documentation checks.")

(defun emacsvox-backend-doc-tests--file-string (relative-name)
  "Return the literal contents of RELATIVE-NAME below the repository root."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name relative-name emacsvox-backend-doc-tests--root))
    (buffer-string)))

(defun emacsvox-backend-doc-tests--normalize-whitespace (string)
  "Collapse whitespace in STRING for spoken-copy comparisons."
  (replace-regexp-in-string "[ \t\n\r]+" " " string))

(ert-deftest emacsvox-backend-guide-owns-the-omnivox-first-route ()
  "The canonical guide should recommend and visibly accept Omnivox."
  (let ((guide
         (emacsvox-backend-doc-tests--file-string "info/emacsvox-body.texi")))
    (dolist
        (required
         '("@node Speech Backends"
           "For a new installation@comma{} use\n@strong{Omnivox}"
           "make build"
           "make install"
           "make windows-omnivox"
           "omnivox --check"
           "export TTS_PROGRAM=omnivox"
           "Direct GNU/Linux Tcl server"
           "legacy Python/PyObjC macOS server"
           "Native Windows Emacs"))
      (should (string-match-p (regexp-quote required) guide)))))

(ert-deftest emacsvox-native-windows-preview-guide-is-bounded-and-complete ()
  "The native Windows preview should be reproducible without POSIX tooling."
  (let ((guide
         (emacsvox-backend-doc-tests--file-string
          "docs/manual/chapters/speech-backends.org")))
    (dolist
        (required
         '("** Trying Native Windows Emacsvox"
           ":TEXINFO_NODE_NAME: Trying Native Windows Emacsvox"
           "$Platform = \"windows-x64\""
           "Get-FileHash -Algorithm SHA256"
           "Expand-Archive -LiteralPath"
           "$env:TTS_PROGRAM = $Omnivox"
           "emacs.exe"
           "M-x omnivox-list-voices RET"
           "M-x emacsvox-toggle-icons RET"
           "not yet the recommended first installation"
           "Do not copy or load the archive's ~omnivox-voices.el~"))
      (should (string-match-p (regexp-quote required) guide)))))

(ert-deftest emacsvox-backend-guide-is-linked-from-user-entry-points ()
  "The README, installation chapter, and manual menu should share one owner."
  (let ((readme
         (emacsvox-backend-doc-tests--file-string "Readme.org"))
        (installation
         (emacsvox-backend-doc-tests--file-string "info/emacsvox-body.texi"))
        (source-installation
         (emacsvox-backend-doc-tests--file-string "etc/install.org"))
        (master
         (emacsvox-backend-doc-tests--file-string "docs/manual/emacsvox.org"))
        (menu
         (emacsvox-backend-doc-tests--file-string "info/preamble.texi")))
    (should
     (string-match-p
      "file:docs/manual/chapters/speech-backends\\.org.*Speech Backends guide"
      readme))
    (should (string-match-p "@xref{Speech Backends}" installation))
    (should
     (string-match-p
      "file:../docs/manual/chapters/speech-backends\\.org.*Speech Backends guide"
      source-installation))
    (should
     (string-match-p
      (regexp-quote "export TTS_PROGRAM=omnivox") installation))
    (should
     (string-match-p
      (regexp-quote "#+include: \"chapters/speech-backends.org\"") master))
    (should
     (string-match-p "\\* Speech Backends: Speech Backends\\." menu))))

(ert-deftest emacsvox-tts-program-doc-distinguishes-recommendation-and-default ()
  "Live help should not present a compatibility default as the recommendation."
  (let ((documentation
         (documentation-property 'tts-program 'variable-documentation)))
    (should (string-match-p "Omnivox is recommended" documentation))
    (should (string-match-p "compatibility defaults" documentation))
    (should (string-match-p "TTS_PROGRAM" documentation))))

(ert-deftest emacsvox-first-use-bootstrap-is-visible-before-advanced-material ()
  "The rendered repository entry point should expose first speech immediately."
  (let* ((readme
          (emacsvox-backend-doc-tests--file-string "Readme.org"))
         (start (string-search "* Start Here: First Speech" readme))
         (next (string-search "* Where To Go Next" readme))
         (advanced
          (string-search "* Advanced Technical And Migration Notes" readme)))
    (should start)
    (should next)
    (should advanced)
    (should (< start next advanced))
    (dolist
        (required
         '("make check-emacs"
           "make all"
           "./bin/emacsvox --diagnose"
           "./bin/emacsvox --check"
           "M-x tts-speak-version RET"
           "C-h v tts-program RET"
           "(setenv \"TTS_PROGRAM\" \"omnivox\")"
           "(load-file \"/path/to/emacsvox/lisp/emacsvox-setup.el\")"
           "Recovering-From-No-Speech.html"))
      (should (string-match-p (regexp-quote required) readme)))))

(ert-deftest emacsvox-first-use-manual-menu-precedes-reference-and-heritage ()
  "The installed manual should present the finite current-user route first."
  (let* ((menu
          (emacsvox-backend-doc-tests--file-string "info/preamble.texi"))
         (installation (string-search "* Installation: Installation." menu))
         (backends
          (string-search "* Speech Backends: Speech Backends." menu))
         (basic (string-search "* Basic Usage: Basic Usage." menu))
         (reference (string-search "Exact generated reference:" menu))
         (heritage
          (string-search "Heritage (not current operating guidance):" menu)))
    (dolist (position (list installation backends basic reference heritage))
      (should position))
    (should
     (string-match-p
      (regexp-quote
       "* Commands, Options, And Keys: (emacsvox-reference).")
      menu))
    (should
     (string-match-p
      (regexp-quote "* Emacspeak Heritage: (emacsvox-heritage).")
      menu))
    (should
     (string-match-p
      (regexp-quote "@ref{Top,Emacspeak Heritage,,emacsvox-heritage")
      menu))
    (should (< installation backends basic reference heritage))))

(ert-deftest emacsvox-first-use-manual-owns-success-and-recovery ()
  "The canonical manual should define first-speech acceptance and rollback."
  (let ((guide
         (emacsvox-backend-doc-tests--file-string "info/emacsvox-body.texi")))
    (dolist
        (required
         '("@chapter Getting Started: Installation and First Speech"
           "@node Confirming First Speech"
           "@node Recovering From No Speech"
           "@node Persistent Startup"
           "without playing audio@comma{} creating\nan Omnivox session log"
           "A zero exit status without both audible signals is not success."
           "Could not find speech server executable"
           "M-x tts-restart RET"
           "This is the rollback"
           "build\noutputs are not distributed"))
      (should (string-match-p (regexp-quote required) guide)))
    (let ((selection
           (string-search "(setenv \"TTS_PROGRAM\" \"omnivox\")" guide))
          (setup
           (string-search
            "(load-file \"/path/to/emacsvox/lisp/emacsvox-setup.el\")"
            guide)))
      (should selection)
      (should setup)
      (should (< selection setup)))))

(ert-deftest emacsvox-first-use-docs-match-the-live-startup-checkpoint ()
  "The documented acceptance sentence should match the startup source."
  (let ((checkpoint
         "I am completely operational, and all my circuits are functioning perfectly!")
        (readme
         (emacsvox-backend-doc-tests--file-string "Readme.org"))
        (guide
         (emacsvox-backend-doc-tests--file-string
          "docs/manual/chapters/installation.org"))
        (startup
         (emacsvox-backend-doc-tests--file-string "lisp/emacsvox.el")))
    (dolist (text (list readme guide startup))
      (should
       (string-match-p
        (regexp-quote checkpoint)
        (emacsvox-backend-doc-tests--normalize-whitespace text))))))

(ert-deftest emacsvox-current-applications-own-maintained-user-routes ()
  "The user manual should present verified routes without inherited setup."
  (let ((guide
         (emacsvox-backend-doc-tests--file-string "info/emacsvox-body.texi"))
        (master
         (emacsvox-backend-doc-tests--file-string "docs/manual/emacsvox.org"))
        (menu
         (emacsvox-backend-doc-tests--file-string "info/preamble.texi"))
        (using
         (emacsvox-backend-doc-tests--file-string "info/emacsvox-body.texi")))
    (should
     (string-match-p
      (regexp-quote "#+include: \"chapters/applications.org\"") master))
    (should-not (string-match-p "@include packages\\.texi" master))
    (should
     (string-match-p
      "\\* Applications And Integrations: Emacs Packages\\." menu))
    (dolist
        (required
         '("@chapter Applications And Integrations"
           "@kbd{M-x eww @key{RET}}"
           "@ref{emacsvox-eww,,,emacsvox-reference"
           "@ref{emacsvox-outline,,,emacsvox-reference"
           "@ref{emacsvox-tempo,,,emacsvox-reference"
           "@ref{emacsvox-forms,,,emacsvox-reference"
           "@ref{Notmuch Mail}"
           "@ref{EAT Terminal Access}"
           "@ref{Running Terminal Based Applications}"
           "experimental legacy front end"
           "not a validated deployment guide"))
      (should (string-match-p (regexp-quote required) guide)))
    (dolist
        (obsolete
         '("ftp://cs.nyu.edu"
           "/home/"
           "/usr/bin/ocr"
           "~/ocr"
           "emacsvox-ocr-scan-image-program"
           "Emacsvox/W3"))
      (should-not (string-match-p (regexp-quote obsolete) guide)))
    (should-not (string-match-p "@code{W3}" using))
    (should-not (string-match-p "Emacsvox/W3" using))
    (should-not (string-match-p "REC-CSS2" using))))

(ert-deftest emacsvox-heritage-owns-inherited-application-surveys ()
  "Historical workflows should remain available only from Heritage."
  (let ((heritage
         (emacsvox-backend-doc-tests--file-string
          "info/emacsvox-heritage.texi"))
        (survey
         (emacsvox-backend-doc-tests--file-string "info/packages.texi")))
    (should (string-match-p "@include packages\\.texi" heritage))
    (should
     (string-match-p
      "\\* Historical Application Survey: Emacs Packages\\." heritage))
    (dolist
        (required
         '("@chapter Historical Emacs Application Survey"
           "They are not current Emacsvox\noperating instructions"
           "ftp://cs.nyu.edu/pub/local/fox/dismal"
           "emacsvox-ocr-scan-image-program"
           "/usr/bin/ocr"
           "@include web-browsing.texi"))
      (should (string-match-p (regexp-quote required) survey)))))

(ert-deftest emacsvox-heritage-owns-standalone-historical-artifacts ()
  "Standalone essays should be explicit Heritage links with one artifact owner."
  (let ((heritage
         (emacsvox-backend-doc-tests--file-string
          "info/emacsvox-heritage.texi"))
        (makefile
         (emacsvox-backend-doc-tests--file-string "info/Makefile"))
        (directory
         (emacsvox-backend-doc-tests--file-string "info/dir"))
        (turning-twenty
         (emacsvox-backend-doc-tests--file-string
          "info/inc-turning-twenty.texi"))
        (root emacsvox-backend-doc-tests--root))
    (should
     (string-match-p
      (regexp-quote
       "* Introducing Emacspeak: (introducing-emacspeak).  A standalone 2006 essay.")
      heritage))
    (should-not
     (string-match-p "@include introducing-emacspeak\\.texi" heritage))
    (should
     (string-match-p
      (regexp-quote
       "@ref{Top,Introducing Emacspeak,,introducing-emacspeak}")
      heritage))
    (should (string-match-p "^all: info *#" makefile))
    (should
     (string-match-p
      (regexp-quote
       "heritage-standalone: introducing-emacspeak.info")
      makefile))
    (should
     (string-match-p
      (regexp-quote
       "* Introducing Emacspeak: (introducing-emacspeak). Historical standalone 2006 essay")
      directory))
    (should
     (file-regular-p (expand-file-name "html/introducing-emacspeak.html" root)))
    (should-not
     (file-exists-p (expand-file-name "info/introducing-emacspeak.html" root)))
    (should
     (file-regular-p (expand-file-name "announcements/now-thirty.info" root)))
    (should-not
     (file-exists-p (expand-file-name "info/now-thirty.info" root)))
    (should
     (file-regular-p
      (expand-file-name "announcements/turning-twenty.org" root)))
    (should
     (file-regular-p (expand-file-name "html/turning-twenty.html" root)))
    (should-not
     (file-exists-p (expand-file-name "info/turning-twenty.texi" root)))
    (should-not
     (file-exists-p (expand-file-name "info/turning-twenty.info" root)))
    (dolist
        (copying-term
         '("Copyright (C) T. V. Raman"
           "All Rights Reserved."
           "Permission is granted to make and distribute verbatim copies"))
      (should
       (string-match-p (regexp-quote copying-term) turning-twenty)))))

(provide 'emacsvox-backend-doc-tests)
;;; emacsvox-backend-doc-tests.el ends here
