;;; diagnose-choice-preview.el --- Preview handoff observations -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Run with the Emacs selected by local.mk: -Q --batch -l this file.
;; Source-only consistency checks for the independent handoff examples.
;; Original runtime observations now have positive preview/editor/context tests.
;; Passing this file alone does not establish editor usability or playback.
;;; Code:
(setq load-prefer-newer t)
(require 'jka-compr)
(let* ((tests (file-name-directory (or load-file-name buffer-file-name)))
       (inhibit-message t)
       (load-suffixes '(".el")))
  (add-to-list 'load-path (expand-file-name "../lisp" tests))
  (require 'emacsvox-preamble)
  (require 'omnivox-voices)
  (require 'emacsvox-aural-voice-context))
(require 'ert)

;; Check the independent input/expected-value examples against existing pure
;; validators only. Runtime and spoken acceptance are separate checks.
(let* ((read-circle nil)
       (fixture (with-temp-buffer
                  (insert-file-contents
                   (expand-file-name "fixtures/voice-editor/preview-handoff.el"
                                     (file-name-directory load-file-name)))
                  (goto-char (point-min))
                  (read (current-buffer))))
       (voice (plist-get fixture :voice))
       (rows (plist-get voice :choices))
       (omnivox-average-pitch-contrast 1.0))
  (should (eql (plist-get fixture :fixture-version) 1))
  (emacsvox-aural-routing--validate-choices rows)
  (omnivox--choice-style-json (plist-get voice :definition))
  (dolist (case (plist-get fixture :projection-cases))
    (when (plist-member case :context)
      (let ((wire (omnivox--choice-patch-json (plist-get case :context) t)))
        (should (equal (if (hash-table-p wire) nil wire)
                       (plist-get case :expected-context)))))
    (when (plist-member case :expected-row-patch)
      (let ((row (cl-find (plist-get case :selection) rows :test #'equal
                          :key (lambda (item) (plist-get item :id)))))
        (should (equal (omnivox--choice-patch-json (plist-get row :adjustments))
                       (plist-get case :expected-row-patch))))))
  (dolist (group '(:projection-cases :lifecycle-cases :evidence-cases :compatibility-cases))
    (let* ((cases (plist-get fixture group))
           (ids (mapcar (lambda (item) (plist-get item :id)) cases)))
      (should (proper-list-p cases))
      (should-not (memq nil ids))
      (should (= (length ids) (length (delete-dups (copy-sequence ids))))))
    (princ (format "Fixture %s: %d cases (data consistency only).\n"
                   group (length (plist-get fixture group))))))
;;; diagnose-choice-preview.el ends here
