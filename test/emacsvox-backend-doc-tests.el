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

(ert-deftest emacsvox-backend-guide-owns-the-omnivox-first-route ()
  "The canonical guide should recommend and visibly accept Omnivox."
  (let ((guide
         (emacsvox-backend-doc-tests--file-string "info/backends.texi")))
    (dolist
        (required
         '("@node Speech Backends"
           "For a new installation, use\n@strong{Omnivox}"
           "make build"
           "make install"
           "make windows-omnivox"
           "omnivox --check"
           "export TTS_PROGRAM=omnivox"
           "Direct GNU/Linux Tcl server"
           "legacy Python/PyObjC macOS server"
           "Native Windows Emacs"))
      (should (string-match-p (regexp-quote required) guide)))))

(ert-deftest emacsvox-backend-guide-is-linked-from-user-entry-points ()
  "The README, installation chapter, and manual menu should share one owner."
  (let ((readme
         (emacsvox-backend-doc-tests--file-string "Readme.org"))
        (installation
         (emacsvox-backend-doc-tests--file-string "info/install.texi"))
        (source-installation
         (emacsvox-backend-doc-tests--file-string "etc/install.org"))
        (master
         (emacsvox-backend-doc-tests--file-string "info/emacsvox.texi"))
        (menu
         (emacsvox-backend-doc-tests--file-string "info/preamble.texi")))
    (should
     (string-match-p
      "file:info/backends\\.texi.*Speech Backends guide" readme))
    (should (string-match-p "@xref{Speech Backends}" installation))
    (should
     (string-match-p
      "file:../info/backends\\.texi.*Speech Backends guide"
      source-installation))
    (should
     (string-match-p
      (regexp-quote "export TTS_PROGRAM=omnivox") installation))
    (should (string-match-p "@include backends\\.texi" master))
    (should
     (string-match-p "\\* Speech Backends: Speech Backends\\." menu))))

(ert-deftest emacsvox-tts-program-doc-distinguishes-recommendation-and-default ()
  "Live help should not present a compatibility default as the recommendation."
  (let ((documentation
         (documentation-property 'tts-program 'variable-documentation)))
    (should (string-match-p "Omnivox is recommended" documentation))
    (should (string-match-p "compatibility defaults" documentation))
    (should (string-match-p "TTS_PROGRAM" documentation))))

(provide 'emacsvox-backend-doc-tests)
;;; emacsvox-backend-doc-tests.el ends here
