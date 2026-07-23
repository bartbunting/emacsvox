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

(ert-deftest emacsvox-org-structure-advice-is-directly-registered ()
  "Org structure advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--org-structure-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

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
  "Org agenda and table advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--org-agenda-table-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-org-timestamp-feedback-is-target-aware ()
  "Only the matching timestamp command cues and speaks its value."
  (let ((ems--interactive-fn-name 'org-timestamp-up)
        (org-last-changed-timestamp "<2026-07-23 Thu>")
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'dtk-speak)
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
    (cl-letf (((symbol-function 'dtk-speak)
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

(provide 'emacsvox-org-tests)
;;; emacsvox-org-tests.el ends here
