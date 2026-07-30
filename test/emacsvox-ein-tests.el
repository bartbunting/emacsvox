;;; emacsvox-ein-tests.el --- EIN advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(dolist (feature
         '(ein ein-cell ein-classes ein-notebook ein-notebooklist
               ein-pytools ein-traceback ein-worksheet))
  (require feature))
(load (expand-file-name "../lisp/emacsvox-ein.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-ein-advice-is-current-and-direct ()
  "Current EIN targets use native advice directly."
  (dolist (entry emacsvox-ein--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))))
  (dolist (target emacsvox-ein--removed-targets)
    (should-not (fboundp target))))

(ert-deftest emacsvox-ein-feedback-is-target-aware ()
  "Only the matching interactive EIN command provides feedback."
  (let ((ems--interactive-fn-name 'ein:tb-next-item)
        submissions)
    (cl-letf
        (((symbol-function 'emacsvox-ein--present-line)
          (lambda (&rest arguments)
            (push arguments submissions))))
      (emacsvox--advice-ein:tb-prev-item-after)
      (emacsvox--advice-ein:tb-next-item-after))
    (should
     (equal
      submissions
      '(((:role notebook :events (focus-entered)
          :notebook-action ein:tb-next-item)
         navigation))))))

(ert-deftest emacsvox-ein-current-cell-uses-complete-input-bounds ()
  "Speaking a cell copies its complete input, not the suffix after point."
  (with-temp-buffer
    (insert "before\ncell body\nafter")
    (goto-char 13)
    (let ((cell 'cell)
          submission)
      (cl-letf
          (((symbol-function 'ein:worksheet-get-current-cell)
            (lambda (&rest _) cell))
           ((symbol-function 'ein:cell-input-pos-min)
            (lambda (_) 8))
           ((symbol-function 'ein:cell-input-pos-max)
            (lambda (_) 17))
           ((symbol-function 'ein:cell-type)
            (lambda (&rest _) "code"))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq submission (cons content arguments)))))
        (emacsvox-ein-speak-current-cell))
      (should (equal (car submission) "cell body"))
      (should
       (equal
        (plist-get (cdr submission) :facts)
        '(:role notebook-cell :notebook-cell-kind code)))
      (should (eq (plist-get (cdr submission) :module) 'ein))
      (should (eq (plist-get (cdr submission) :occasion) 'inspection)))))

(ert-deftest emacsvox-ein-empty-cell-has-an-audible-label ()
  "An empty cell remains identifiable by type."
  (with-temp-buffer
    (let ((cell 'cell)
          submission)
      (cl-letf
          (((symbol-function 'ein:worksheet-get-current-cell)
            (lambda (&rest _) cell))
           ((symbol-function 'ein:cell-input-pos-min)
            (lambda (_) 1))
           ((symbol-function 'ein:cell-input-pos-max)
            (lambda (_) 1))
           ((symbol-function 'ein:cell-type)
            (lambda (&rest _) "markdown"))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq submission (cons content arguments)))))
        (emacsvox-ein-speak-current-cell))
      (should (equal (car submission) "empty markdown cell"))
      (should
       (eq
        (plist-get (plist-get (cdr submission) :facts) :notebook-cell-kind)
        'markdown)))))

(ert-deftest emacsvox-ein-yank-cell-feedback-is-one-native-submission ()
  "Yanking a cell submits its content and structural change together."
  (let ((ems--interactive-fn-name 'ein:worksheet-yank-cell)
        submissions)
    (cl-letf
        (((symbol-function 'emacsvox-ein--submit-cell)
          (lambda (&rest arguments)
            (push arguments submissions))))
      (emacsvox--advice-ein:worksheet-yank-cell-after))
    (should
     (equal
      submissions
      '((yanked edit (object-changed)))))))

(ert-deftest emacsvox-ein-execution-reports-start-without-moving-point ()
  "Asynchronous execution does not claim completion or alter command motion."
  (with-temp-buffer
    (insert "one\ntwo\n")
    (goto-char 2)
    (let ((ems--interactive-fn-name 'ein:worksheet-execute-cell-km)
          (before (point))
          submission)
      (cl-letf
          (((symbol-function 'emacsvox-ein--submit-message)
            (lambda (&rest arguments)
              (setq submission arguments))))
        (emacsvox--advice-ein:worksheet-execute-cell-km-after))
      (should (= (point) before))
      (should
       (equal
        submission
        '("Cell execution started. Press C-c . to hear results."
          (:role code-operation :events (operation-started)
           :code-operation-kind ein:worksheet-execute-cell-km)))))))

(ert-deftest emacsvox-ein-output-all-uses-prefix-state ()
  "The all-output command reports the requested global visibility."
  (let ((ems--interactive-fn-name
         'ein:worksheet-set-output-visibility-all-km)
        (current-prefix-arg '(4))
        submission)
    (cl-letf
        (((symbol-function 'emacsvox-ein--submit-message)
          (lambda (&rest arguments)
            (setq submission arguments))))
      (emacsvox--advice-ein:worksheet-set-output-visibility-all-km-after))
    (should
     (equal
      submission
      '("Hid all cell output"
        (:role notebook-cell :events (visibility-changed)
         :visibility folded))))))

(ert-deftest emacsvox-ein-save-reports-started-operation ()
  "Notebook saves use in-progress semantics."
  (let ((ems--interactive-fn-name 'ein:notebook-save-notebook-command)
        submission)
    (cl-letf
        (((symbol-function 'emacsvox-ein--submit-message)
          (lambda (&rest arguments)
            (setq submission arguments))))
      (emacsvox--advice-ein:notebook-save-notebook-command-after))
    (should
     (equal
      submission
      '("Saving notebook"
        (:role code-operation :events (operation-started)
         :code-operation-kind ein:notebook-save-notebook-command))))))

(ert-deftest emacsvox-ein-cell-type-adapter-uses-native-policy ()
  "The retained tone adapter submits cell meaning without invoking SoX."
  (let (submission)
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit-actions)
          (lambda (&rest arguments)
            (setq submission arguments))))
      (emacsvox-ein-sox-gen "raw"))
    (should
     (equal
      submission
      '(:facts (:role notebook-cell :notebook-cell-kind raw)
        :module ein :occasion inspection)))))

(ert-deftest emacsvox-ein-policy-covers-cell-and-operation-feedback ()
  "EIN semantics resolve to first-class tones and lifecycle cues."
  (let ((emacsvox-aural-active-scheme 'default)
        (emacsvox-aural-user-rules nil)
        (emacsvox-aural-session-rules nil)
        (emacsvox-aural-buffer-rules nil)
        (emacsvox-aural-enabled-feature-fragments nil)
        (emacsvox-aural--current-rules-cache
         (make-hash-table :test #'equal)))
    (dolist
        (case
         '(((:role notebook-cell :events (focus-entered)
             :notebook-cell-kind code)
            navigation notebook-cell-code large-movement)
           ((:role notebook-cell :events (visibility-changed)
             :visibility folded)
            state-change nil close-object)
           ((:role code-operation :events (operation-started)
             :code-operation-kind execute-cell)
            state-change nil progress)))
      (pcase-let* ((`(,facts ,occasion ,tone ,cue) case)
                   (plan
                    (emacsvox-aural-resolve-active
                     facts
                     (list
                      :module 'ein :mode 'fundamental-mode
                      :mode-lineage '(fundamental-mode)
                      :occasion occasion)))
                   (actions
                    (emacsvox-aural-render-plan-before plan)))
        (when tone
          (should
           (memq tone (mapcar #'emacsvox-aural-action-tone actions))))
        (should
         (memq cue (mapcar #'emacsvox-aural-action-cue actions)))))))

(ert-deftest emacsvox-ein-face-map-covers-current-interface ()
  "Every EIN face mapped to a voice exists in the installed package."
  (dolist (entry emacsvox-ein--face-voice-map)
    (should (facep (car entry)))))

(ert-deftest emacsvox-ein-modes-enable-native-context ()
  "Notebook mode owns context while enabled and restores Python on disable."
  (with-temp-buffer
    (emacsvox-ein-enable-aural-context)
    (should (eq emacsvox-aural-module 'ein)))
  (with-temp-buffer
    (python-mode)
    (let ((ein:notebook-mode t))
      (emacsvox-ein--update-notebook-aural-context)
      (should (eq emacsvox-aural-module 'ein)))
    (let ((ein:notebook-mode nil))
      (emacsvox-ein--update-notebook-aural-context)
      (should (eq emacsvox-aural-module 'python)))))

(provide 'emacsvox-ein-tests)
;;; emacsvox-ein-tests.el ends here
