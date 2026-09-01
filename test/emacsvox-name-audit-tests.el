;;; emacsvox-name-audit-tests.el --- Emacsvox name-audit tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Contract tests for the removed-name audit.

;;; Code:

(require 'ert)
(require 'emacsvox-name-audit)

(ert-deftest emacsvox-name-audit-finds-removed-technical-names ()
  "Removed APIs, environment names, and paths are reported."
  (let ((matches
         (ems-name-audit--line-matches
          "active.el"
          "emacspeak-speak-line EMACSPEAK_DIR ~/.emacspeak/server"
          7)))
    (should
     (equal
      (mapcar (lambda (match) (nth 2 match)) matches)
      '("emacspeak-speak-line" "EMACSPEAK_DIR" "/.emacspeak/")))))

(ert-deftest emacsvox-name-audit-allows-upstream-urls ()
  "Technical-looking names inside upstream URLs remain valid history."
  (should-not
   (ems-name-audit--line-matches
    "active.org"
    "See https://example.invalid/emacspeak-speak-line and https://example.invalid/emacspeak/docs."
    1)))

(ert-deftest emacsvox-name-audit-does-not-hide-prose-beside-url ()
  "An upstream URL does not exempt a stale name elsewhere on its line."
  (let ((matches
         (ems-name-audit--line-matches
          "active.org"
          "https://example.invalid/emacspeak-old uses emacspeak-live"
          2)))
    (should
     (equal (mapcar (lambda (match) (nth 2 match)) matches)
            '("emacspeak-live")))))

(ert-deftest emacsvox-name-audit-exclusions-are-narrow ()
  "Archives are excluded while active implementation paths are audited."
  (should (ems-name-audit--excluded-path-p "announcements/old.org"))
  (should
   (ems-name-audit--excluded-path-p
    "archive/emacsvox/migrations/tts-modernization.org"))
  (should
   (ems-name-audit--excluded-path-p "test/run-scenarios.el"))
  (should
   (ems-name-audit--excluded-path-p "info/emacsvox-reference.info-2"))
  (should
   (ems-name-audit--excluded-path-p "info/emacsvox-heritage.info"))
  (should-not
   (ems-name-audit--excluded-path-p "lisp/emacsvox-speak.el"))
  (should-not
   (ems-name-audit--excluded-path-p "servers/tts-lib.tcl")))

(ert-deftest emacsvox-name-audit-allows-documented-breaking-names ()
  "Breaking names are allowed only in their explicit documentation."
  (should
   (ems-name-audit--allowed-name-p "README.org" "EMACSPEAK_DIR"))
  (should
   (ems-name-audit--allowed-name-p "CLAUDE.md" "/emacspeak/"))
  (should-not
   (ems-name-audit--allowed-name-p "run" "EMACSPEAK_DIR")))

(ert-deftest emacsvox-name-audit-allows-intentional-references-narrowly ()
  "External provenance and negative tests allow only their exact old names."
  (should-not
   (ems-name-audit--line-matches
    "servers/windows-speech-NOTICE.md"
    "Imported from emacspeak-support."
    12))
  (should-not
   (ems-name-audit--line-matches
    "test/emacsvox-launcher-tests.el"
    "Unset EMACSPEAK_DIR and EMACSPEAK_PLAY."
    46))
  (should
   (equal
    (mapcar
     (lambda (match) (nth 2 match))
     (ems-name-audit--line-matches
      "active.org"
      "emacspeak-support EMACSPEAK_DIR EMACSPEAK_PLAY"
      1))
    '("emacspeak-support" "EMACSPEAK_DIR" "EMACSPEAK_PLAY")))
  (should
   (equal
    (mapcar
     (lambda (match) (nth 2 match))
     (ems-name-audit--line-matches
      "test/emacsvox-launcher-tests.el"
      "EMACSPEAK_HOME"
      1))
    '("EMACSPEAK_HOME"))))

(ert-deftest emacsvox-name-audit-recognizes-clean-report ()
  "A report with no matches is clean and formats deterministically."
  (let ((audit '(:file-count 3 :matches nil)))
    (should (ems-name-audit-clean-p audit))
    (should
     (equal
      (ems-name-audit-format audit)
      "Emacsvox name audit: 3 active tracked files, 0 stale names\n"))))

(provide 'emacsvox-name-audit-tests)
;;; emacsvox-name-audit-tests.el ends here
