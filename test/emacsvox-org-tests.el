;;; emacsvox-org-tests.el --- Org advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Org advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-org.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

;; Verify that direct advice survives definition of lazily loaded Org commands.
(require 'org-goto)
(require 'org-agenda)
(require 'org-archive)
(require 'org-capture)
(require 'org-src)
(require 'ox)
(require 'ox-md)

(defconst emacsvox-test--org-structure-after-targets
  '(org-next-item org-previous-item
    org-mark-ring-goto org-mark-ring-push
    org-next-visible-heading org-previous-visible-heading
    org-forward-heading-same-level org-backward-heading-same-level
    org-backward-sentence org-forward-sentence
    org-backward-element org-forward-element
    org-next-link org-previous-link
    org-goto org-goto-ret org-goto-left org-goto-right org-goto-quit
    org-metaleft org-metaright org-metaup org-metadown org-meta-return
    org-shiftmetaleft org-shiftmetaright org-shiftmetaup org-shiftmetadown
    org-mark-element org-mark-subtree
    org-backward-paragraph org-forward-paragraph
    org-agenda-forward-block org-agenda-backward-block
    org-cycle-list-bullet org-cycle org-shifttab
    org-overview org-content org-tree-to-indirect-buffer)
  "Native after-advice targets in the Org structure and folding slice.")

(defconst emacsvox-test--org-agenda-table-after-targets
  '(org-timestamp-down-day org-timestamp-up-day
    org-timestamp-down org-timestamp-up
    org-eval-in-calendar
    org-agenda-next-date-line org-agenda-previous-date-line
    org-agenda-next-line org-agenda-previous-line org-agenda-goto-today
    org-agenda-quit org-agenda-exit
    org-agenda-goto org-agenda-show org-agenda-switch-to org-agenda
    orgtbl-mode org-return
    org-table-next-field org-table-previous-field
    org-table-next-row org-table-previous-row)
  "Native after-advice targets in the Org agenda and table slice.")

(defconst emacsvox-test--org-editing-after-targets
  '(org-delete-indentation
    org-insert-heading org-insert-todo-heading org-insert-structure-template
    org-promote-subtree org-demote-subtree org-do-promote org-do-demote
    org-move-subtree-up org-move-subtree-down
    org-convert-to-odd-levels org-convert-to-oddeven-levels
    org-cut-subtree org-copy-subtree org-paste-subtree
    org-archive-subtree org-narrow-to-subtree
    org-toggle-archive-tag org-toggle-comment
    end-of-line org-toggle-checkbox
    org-occur org-beginning-of-item org-beginning-of-item-list
    org-end-of-item org-end-of-item-list
    org-beginning-of-line org-end-of-line
    org-edit-src-exit org-edit-src-abort
    org-edit-src-code org-edit-special org-switchb
    org-fill-paragraph org-todo)
  "Native after-advice targets in the Org editing slice.")

(defconst emacsvox-test--org-capture-after-targets
  '(org-capture-goto-last-stored org-capture-goto-target
    org-capture-finalize org-capture-kill org-md-export-as-markdown)
  "Native after-advice targets in the Org capture slice.")

(ert-deftest emacsvox-org-structure-advice-is-directly-registered ()
  "Org structure advice uses native advice directly."
  (dolist (target emacsvox-test--org-structure-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-org-item-feedback-is-target-aware ()
  "Only the matching Org item movement cues and speaks the item."
  (let ((ems--interactive-fn-name 'org-previous-item)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-org-speak-item)
               (lambda () (push 'speak-item events))))
      (emacsvox--advice-org-next-item-after)
      (emacsvox--advice-org-previous-item-after))
    (should
     (equal
      (nreverse events)
      '((icon item) speak-item)))))

(ert-deftest emacsvox-org-structure-feedback-preserves-order ()
  "Org structure movement speaks before its large-movement cue."
  (let ((ems--interactive-fn-name 'org-next-visible-heading)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-org-next-visible-heading-after))
    (should
     (equal
      (nreverse events)
      '(speak-line (icon large-movement))))))

(ert-deftest emacsvox-org-paragraph-feedback-preserves-order ()
  "Org paragraph movement cues before speaking the paragraph."
  (let ((ems--interactive-fn-name 'org-forward-paragraph)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-paragraph)
               (lambda () (push 'speak-paragraph events))))
      (emacsvox--advice-org-forward-paragraph-after))
    (should
     (equal
      (nreverse events)
      '((icon paragraph) speak-paragraph)))))

(ert-deftest emacsvox-org-cycle-keeps-table-feedback-unconditional ()
  "Org visibility cycling always reports the current table cell."
  (let* ((ems--interactive-fn-name nil)
         events
         (emacsvox-org-table-after-movement-function
          (lambda () (push 'table-cell events))))
    (cl-letf (((symbol-function 'org-at-table-p)
               (lambda (&rest _) t))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-org-cycle-after))
    (should (equal events '(table-cell)))))

(ert-deftest emacsvox-org-cycle-nontable-feedback-is-target-aware ()
  "Only matching interactive non-table cycling speaks the line."
  (let ((ems--interactive-fn-name 'org-shifttab)
        events)
    (cl-letf (((symbol-function 'org-at-table-p)
               (lambda (&rest _) nil))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-org-cycle-after)
      (emacsvox--advice-org-shifttab-after))
    (should (equal events '(speak-line)))))

(ert-deftest emacsvox-org-agenda-table-advice-is-directly-registered ()
  "Org agenda and table advice uses native advice directly."
  (dolist (target emacsvox-test--org-agenda-table-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-org-timestamp-feedback-is-target-aware ()
  "Only the matching timestamp command cues and speaks its value."
  (let ((ems--interactive-fn-name 'org-timestamp-up)
        (org-last-changed-timestamp "<2026-07-23 Thu>")
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-org-timestamp-down-after)
      (emacsvox--advice-org-timestamp-up-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) (speak "<2026-07-23 Thu>"))))))

(ert-deftest emacsvox-org-calendar-feedback-remains-unconditional ()
  "Calendar expression results speak even outside an interactive call."
  (let ((ems--interactive-fn-name nil)
        (org-ans2 "Thursday")
        spoken)
    (cl-letf (((symbol-function 'tts-speak)
               (lambda (text) (setq spoken text))))
      (emacsvox--advice-org-eval-in-calendar-after))
    (should (equal spoken "Thursday"))))

(ert-deftest emacsvox-org-agenda-navigation-preserves-feedback-order ()
  "Agenda navigation cues before speaking the destination line."
  (let ((ems--interactive-fn-name 'org-agenda-next-line)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-org-agenda-previous-line-after)
      (emacsvox--advice-org-agenda-next-line-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) speak-line)))))

(ert-deftest emacsvox-org-table-movement-feedback-remains-unconditional ()
  "Table movement always reports the current cell."
  (let* ((ems--interactive-fn-name nil)
         events
         (emacsvox-org-table-after-movement-function
          (lambda () (push 'table-cell events))))
    (emacsvox--advice-org-table-next-field-after)
    (should (equal events '(table-cell)))))

(ert-deftest emacsvox-org-return-selects-table-or-line-feedback ()
  "Interactive Org return reports a table cell or the destination line."
  (let* ((ems--interactive-fn-name 'org-return)
         events
         at-table
         (emacsvox-org-table-after-movement-function
          (lambda () (push 'table-cell events))))
    (cl-letf (((symbol-function 'org-at-table-p)
               (lambda (&rest _) at-table))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (setq at-table t)
      (emacsvox--advice-org-return-after)
      (setq at-table nil
            ems--interactive-fn-name 'org-return)
      (emacsvox--advice-org-return-after))
    (should
     (equal
      (nreverse events)
      '(table-cell speak-line (icon select-object))))))

(ert-deftest emacsvox-org-editing-advice-is-directly-registered ()
  "Org editing advice uses native advice directly."
  (dolist (target emacsvox-test--org-editing-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-org-heading-edit-feedback-preserves-order ()
  "Org heading edits speak the line before the open cue."
  (let ((ems--interactive-fn-name 'org-insert-heading)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-org-insert-todo-heading-after)
      (emacsvox--advice-org-insert-heading-after))
    (should
     (equal
      (nreverse events)
      '(speak-line (icon open-object))))))

(ert-deftest emacsvox-org-subtree-feedback-is-target-aware ()
  "Only the matching subtree command speaks and cues its result."
  (let ((ems--interactive-fn-name 'org-paste-subtree)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-org-copy-subtree-after)
      (emacsvox--advice-org-paste-subtree-after))
    (should
     (equal
      (nreverse events)
      '(speak-line (icon yank-object))))))

(ert-deftest emacsvox-org-generic-end-of-line-delegates-in-org-mode ()
  "Interactive generic line movement invokes Org's line endpoint logic."
  (let ((ems--interactive-fn-name 'end-of-line)
        (major-mode 'org-mode)
        delegated)
    (cl-letf (((symbol-function 'org-end-of-line)
               (lambda (&rest _) (setq delegated t))))
      (emacsvox--advice-end-of-line-after))
    (should delegated)))

(ert-deftest emacsvox-org-item-navigation-preserves-feedback-order ()
  "Org item navigation speaks the line before its selection cue."
  (let ((ems--interactive-fn-name 'org-end-of-item)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-org-end-of-item-after))
    (should
     (equal
      (nreverse events)
      '(speak-line (icon select-object))))))

(ert-deftest emacsvox-org-source-edit-feedback-is-target-aware ()
  "Only the matching source edit command reports its window transition."
  (let ((ems--interactive-fn-name 'org-edit-src-exit)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-org-edit-src-abort-after)
      (emacsvox--advice-org-edit-src-exit-after))
    (should
     (equal
      (nreverse events)
      '((icon close-object) speak-line)))))

(ert-deftest emacsvox-org-todo-feedback-reports-current-state ()
  "Interactive TODO changes cue and report the resulting state."
  (let ((ems--interactive-fn-name 'org-todo)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'org-get-todo-state)
               (lambda () "DONE"))
              ((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) events))))
      (emacsvox--advice-org-todo-after))
    (should
     (equal
      (nreverse events)
      '((icon button) "DONE")))))

(ert-deftest emacsvox-org-capture-advice-is-directly-registered ()
  "Org capture advice uses native advice directly."
  (dolist (target emacsvox-test--org-capture-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-org-last-capture-feedback-is-target-aware ()
  "Visiting the last capture only reports an interactive invocation."
  (let ((ems--interactive-fn-name 'org-capture-goto-last-stored)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-org-capture-goto-last-stored-after))
    (should
     (equal
      (nreverse events)
      '((icon large-movement) speak-line)))))

(ert-deftest emacsvox-org-capture-target-feedback-remains-unconditional ()
  "Internally selected capture targets still cue and speak."
  (let ((ems--interactive-fn-name nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-org-capture-goto-target-after))
    (should
     (equal
      (nreverse events)
      '((icon large-movement) speak-line)))))

(ert-deftest emacsvox-org-capture-lifecycle-cues-remain-unconditional ()
  "Finalizing and cancelling captures always emit their lifecycle cues."
  (let ((ems--interactive-fn-name nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-org-capture-finalize-after)
      (emacsvox--advice-org-capture-kill-after))
    (should (equal (nreverse events) '(save-object close-object)))))

(ert-deftest emacsvox-org-markdown-export-feedback-is-target-aware ()
  "Interactive Markdown export cues completion and speaks the mode line."
  (let ((ems--interactive-fn-name 'org-md-export-as-markdown)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events))))
      (emacsvox--advice-org-md-export-as-markdown-after))
    (should
     (equal
      (nreverse events)
      '((icon task-done) mode-line)))))

(ert-deftest emacsvox-org-risky-advice-is-directly-registered ()
  "Org deletion and export advice uses native advice directly."
  (dolist
      (entry
       '((org-delete-char :around emacsvox--advice-org-delete-char-around)
         (org-export--dispatch-action
          :before emacsvox--advice-org-export--dispatch-action-before)
         (org-export-to-file :after
                             emacsvox--advice-org-export-to-file-after)))
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-org-delete-char-calls-original-once ()
  "Interactive Org deletion gives feedback, then calls the command once."
  (let ((ems--interactive-fn-name 'org-delete-char)
        calls
        events)
    (cl-letf (((symbol-function 'dtk-tone-deletion)
               (lambda () (push 'deletion-tone events)))
              ((symbol-function 'emacsvox-speak-char)
               (lambda (delete-p) (push (list 'speak-char delete-p) events))))
      (should
       (eq
        'result
        (emacsvox--advice-org-delete-char-around
         (lambda (n)
           (push n calls)
           'result)
         3))))
    (should (equal calls '(3)))
    (should
     (equal
      (nreverse events)
      '(deletion-tone (speak-char t))))))

(ert-deftest emacsvox-org-delete-char-is-quiet-programmatically ()
  "Programmatic Org deletion calls the original once without feedback."
  (let ((ems--interactive-fn-name nil)
        calls
        feedback)
    (cl-letf (((symbol-function 'dtk-tone-deletion)
               (lambda () (setq feedback t)))
              ((symbol-function 'emacsvox-speak-char)
               (lambda (&rest _) (setq feedback t))))
      (emacsvox--advice-org-delete-char-around
       (lambda (n) (push n calls))
       2))
    (should (equal calls '(2)))
    (should-not feedback)))

(ert-deftest emacsvox-org-legacy-completion-calls-original-once ()
  "The optional legacy Org completion wrapper preserves one-call semantics."
  (with-temp-buffer
    (let ((calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-get-minibuffer-contents)
                 (lambda () ""))
                ((symbol-function 'emacsvox-speak-line)
                 (lambda () (push 'speak-line events)))
                ((symbol-function 'emacsvox-speak-completions-if-available)
                 (lambda () (push 'completions events))))
        (should
         (eq
          'result
          (emacsvox--advice-org-complete-around
           (lambda ()
             (cl-incf calls)
             (insert "completed")
             'result))))
      (should (= calls 1))
      (should (equal events '(speak-line)))))))

(ert-deftest emacsvox-org-legacy-completion-does-not-create-a-command ()
  "Absent legacy Org completion remains absent on current Org."
  (unless (symbol-file 'org-complete 'defun)
    (should-not (fboundp 'org-complete))))

(ert-deftest emacsvox-org-export-dispatch-uses-explicit-arguments ()
  "Export menu feedback selects choices from native advice arguments."
  (let ((entries '((?a "Alpha") (?b "Beta")))
        notified
        waited)
    (cl-letf (((symbol-function 'tts-notify)
               (lambda (text) (setq notified text)))
              ((symbol-function 'sit-for)
               (lambda (seconds) (setq waited seconds))))
      (emacsvox--advice-org-export--dispatch-action-before
       "Export" '(?a ?b) entries nil nil nil))
    (should (equal notified "a: Alpha\n\nb: Beta\n"))
    (should (= waited 5))))

(ert-deftest emacsvox-org-export-to-file-uses-explicit-file ()
  "Export completion reports the FILE argument directly."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-notify)
               (lambda (text) (push (list 'notify text) events))))
      (emacsvox--advice-org-export-to-file-after
       'html "/tmp/report.html" nil nil nil nil nil nil))
    (should
     (equal
      (nreverse events)
      '((icon save-object) (notify "Wrote /tmp/report.html"))))))

(provide 'emacsvox-org-tests)
;;; emacsvox-org-tests.el ends here
