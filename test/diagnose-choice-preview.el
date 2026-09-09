;;; diagnose-choice-preview.el --- Preview handoff observations -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Run with the Emacs selected by local.mk: -Q --batch -l this file.
;; Source-only, synthetic drafts, private pipe objects and muted writes/timers.
;; Assertions reproduce the remaining projection/view gaps, not correct UX.
;; Ownership and strict decoder observations are positive omnivox-preview-tests.
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

(defvar emacsvox-preview-diagnostic--count 0)
(defun emacsvox-preview-diagnostic--report (name observed expected)
  "Print NAME and require OBSERVED to match the independent EXPECTED baseline."
  (should (equal observed expected))
  (cl-incf emacsvox-preview-diagnostic--count)
  (princ (format "%s %S\n" name observed)))

;; A stable, tuned row reaches the old projector as selectors plus shared style.
(let* ((selector '(:kind exact :scope local :engine-id "test" :voice-id "one"))
       (snapshot (list :definition '(:average-pitch 3) :selectors (list selector)
                       :choices (list (list :id "row-b" :selector selector
                                            :adjustments '(:average-pitch nil :echo 0)))))
       (entry (emacsvox-aural-voice-editing--preview snapshot nil nil "sample")))
  (emacsvox-preview-diagnostic--report
   'projection-drops-row-and-patch
   (list (length (plist-get entry :selectors)) (and (plist-member entry :choices) t)
         (plist-get (plist-get entry :acss) :average-pitch))
   (list 1 nil (/ 3.0 9))))

;; Local Stop removes UI ownership without invalidating its callback generation.
(dolist (change '(stop text))
  (let* ((snapshot '(:definition (:average-pitch 3) :selectors nil))
         (draft (emacsvox-aural-voice-drafts--make :working snapshot :original snapshot))
         (context (list :draft draft :voice 'bolden :palette nil :policy nil :text "before"
                        :preview-generation 0 :preview-result nil :buffer nil))
         (emacsvox-aural-voice-editor--context context)
         (emacsvox-aural-voice-editor--preview-owner nil)
         pending)
    (cl-letf (((symbol-function 'tts-preview-voices) (lambda (_entries callback) (setq pending callback)))
              ((symbol-function 'tts-stop) #'ignore)
              ((symbol-function 'tts-notify) #'ignore)
              ((symbol-function 'emacsvox-aural-voice-editor-refresh) #'ignore)
              ((symbol-function 'read-string) (lambda (&rest _) "after")))
      (emacsvox-aural-voice-editor--preview nil)
      (if (eq change 'stop) (emacsvox-aural-voice-editor-stop)
        (emacsvox-aural-voice-editor-text))
      (funcall pending '(:status failed :message "old sample"))
      (emacsvox-preview-diagnostic--report
       (intern (format "editor-late-result-survives-%s" change))
       (list (plist-get context :preview-generation)
             (plist-get (plist-get context :preview-result) :message)) '(1 "old sample")))))

;; Recapture refreshes the view but leaves an old pending preview's generation.
(with-temp-buffer
  (setq emacsvox-aural-voice-context--generation 7)
  (cl-letf (((symbol-function 'emacsvox-aural-voice-context--check) #'ignore)
            ((symbol-function 'emacsvox-aural-voice-context--capture) (lambda () '(:facts new)))
            ((symbol-function 'emacsvox-aural-voice-context-refresh) #'ignore))
    (emacsvox-aural-voice-context-recapture)
    (emacsvox-preview-diagnostic--report
     'context-recapture-keeps-preview-generation emacsvox-aural-voice-context--generation 7)))

;; An explicit context value equal to shared is still an override above a row.
(let* ((snapshot '(:definition (:average-pitch 3) :selectors nil :choices nil))
       (base '(:palette test :voice bolden))
       (input (list :facts '(:role heading)
                    :context '(:mode fundamental-mode :voice-lock-enabled nil)
                    :rules (list (emacsvox-aural-compile-rule
                                  '(:id contextual :match (:role heading)
                                    :render (:content (:voice (:preset bolden :average-pitch 3)))) 'user))))
       result entry)
  (cl-letf (((symbol-function 'emacsvox-aural-voice-runtime--resolve) (lambda (&rest _) '(:name bolden))))
    (setq result (emacsvox-aural-voice-context--resolve base snapshot input)
          entry (emacsvox-aural-voice-editing--preview (plist-get result :snapshot) nil nil "sample")))
  (emacsvox-preview-diagnostic--report
   'context-flattened-into-shared
   (list (and (memq :average-pitch (plist-get result :explicit)) t)
         (and (plist-member entry :context) t)
         (plist-get (plist-get entry :acss) :average-pitch)) (list t nil (/ 3.0 9))))

(princ (format "%d baseline observations reproduced; preview fixes remain pending.\n"
               emacsvox-preview-diagnostic--count))

;; Check the independent input/expected-value examples against existing pure
;; validators only. These checks do not prove remaining editor integration.
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
