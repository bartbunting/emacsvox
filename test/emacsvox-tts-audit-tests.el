;;; emacsvox-tts-audit-tests.el --- Tests for TTS namespace audit -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for the syntax-aware DTK-to-TTS namespace inventory.

;;; Code:

(require 'ert)
(require 'tts-audit)

(defun emacsvox-test--tts-audit-source (source)
  "Return TTS audit data parsed from SOURCE."
  (with-temp-buffer
    (insert source)
    (ems-tts-audit-buffer "fixture.el")))

(ert-deftest emacsvox-tts-audit-ignores-comments ()
  "Comments that mention DTK names do not inflate the inventory."
  (let ((result
         (emacsvox-test--tts-audit-source
          ";; (dtk-speak \"ignored\") DTK_PROGRAM\n\
           (message \"ready\")\n")))
    (should-not (plist-get result :symbol-counts))
    (should-not (plist-get result :string-counts))))

(ert-deftest emacsvox-tts-audit-counts-symbols-and-configuration-strings ()
  "Executable symbols and legacy strings are reported separately."
  (let ((result
         (emacsvox-test--tts-audit-source
          "(let ((dtk-quiet t))\n\
             (dtk-speak (getenv \"DTK_PROGRAM\")))\n")))
    (should
     (equal
      (plist-get result :symbol-counts)
      '((dtk-quiet . 1) (dtk-speak . 1))))
    (should
     (equal
      (plist-get result :string-counts)
      '(("DTK_PROGRAM" . 1))))))

(ert-deftest emacsvox-tts-audit-allows-only-real-dectalk-backend-strings ()
  "DECtalk backend names remain valid without exempting generic DTK strings."
  (let ((result
         (emacsvox-test--tts-audit-source
          "(list \"dtk-exp\" \"dtk-soft\" \"dtk-other\" \"DTK_PROGRAM\")\n")))
    (should
     (equal
      (plist-get result :string-counts)
      '(("DTK_PROGRAM" . 1) ("dtk-other" . 1))))
    (should-not (ems-tts-audit-clean-p result))))

(ert-deftest emacsvox-tts-audit-recognizes-a-clean-result ()
  "The audit gate accepts code that uses only canonical names."
  (let ((result
         (emacsvox-test--tts-audit-source
          "(tts-speak (getenv \"TTS_PROGRAM\"))\n")))
    (should (ems-tts-audit-clean-p result))))

(ert-deftest emacsvox-tts-audit-active-text-excludes-only-explicit-history ()
  "The text gate includes active support files and excludes named history."
  (should (ems-tts-audit--active-text-path-p "servers/tts-lib.tcl"))
  (should (ems-tts-audit--active-text-path-p "tvr/emacs-startup.el"))
  (should-not (ems-tts-audit--active-text-path-p "announcements/old.org"))
  (should-not (ems-tts-audit--active-text-path-p "etc/NEWS-59.0"))
  (should-not (ems-tts-audit--active-text-path-p "test/example.el")))

(ert-deftest emacsvox-tts-audit-identifies-definitions ()
  "Legacy definitions are distinguished from ordinary references."
  (let ((result
         (emacsvox-test--tts-audit-source
          "(defvar dtk-program \"espeak\")\n\
           (defun dtk-speak (text) text)\n\
           (dtk-speak \"hello\")\n")))
    (should
     (equal
      (plist-get result :definitions)
      '(dtk-program dtk-speak)))
    (should
     (equal
      (plist-get result :symbol-counts)
      '((dtk-program . 1) (dtk-speak . 2))))))

(ert-deftest emacsvox-tts-audit-includes-legacy-keymap-name ()
  "The old speech keymap name is included despite its Emacsvox prefix."
  (let ((result
         (emacsvox-test--tts-audit-source
          "(define-prefix-command 'emacsvox-dtk-submap)\n")))
    (should
     (equal
      (plist-get result :symbol-counts)
      '((emacsvox-dtk-submap . 1))))))

(ert-deftest emacsvox-tts-audit-orders-most-used-symbols-deterministically ()
  "Usage order is descending by count and alphabetical for ties."
  (should
   (equal
    (ems-tts-audit--most-used
     '((dtk-stop . 2) (dtk-tone . 2) (dtk-speak . 4)))
    '((dtk-speak . 4) (dtk-stop . 2) (dtk-tone . 2)))))

(provide 'emacsvox-tts-audit-tests)
;;; emacsvox-tts-audit-tests.el ends here
