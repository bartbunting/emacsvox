;;; emacsvox-reftex-tests.el --- RefTeX advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated RefTeX advice.

;;; Code:

(require 'ert)
(require 'reftex)
(require 'reftex-index)
(require 'reftex-sel)
(require 'reftex-toc)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-reftex.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--reftex-after-targets
  '(reftex-select-previous-heading
    reftex-select-next-heading
    reftex-toc-quit
    reftex-toc-previous
    reftex-toc-next
    reftex-toc-goto-line
    reftex-toc-goto-line-and-hide
    reftex-toc-view-line
    reftex-select-previous
    reftex-select-next
    reftex-select-accept
    reftex-toc-toggle-follow
    reftex-toc-toggle-labels
    reftex-toc-toggle-file-boundary
    reftex-toc-toggle-context
    reftex-index-next
    reftex-index-previous
    reftex-index-goto-entry
    reftex-index-goto-entry-and-hide
    reftex-index-view-entry
    reftex-index-toggle-follow
    reftex-index-toggle-context
    reftex-display-index
    reftex-index-quit
    reftex-index-quit-and-kill
    reftex-highlight)
  "Current Emacs 31 RefTeX targets using direct after advice.")

(ert-deftest emacsvox-reftex-advice-is-directly-registered ()
  "RefTeX advice is attached directly to current Emacs 31 targets."
  (dolist (target emacsvox-test--reftex-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-reftex-obsolete-index-toggles-remain-absent ()
  "Loading RefTeX support does not recreate removed index toggles."
  (dolist
      (target
       '(reftex-index-toggle-labels
         reftex-index-toggle-file-boundary))
    (should-not (fboundp target))
    (should-not
     (fboundp
      (intern (format "emacsvox--advice-%s-after" target))))))

(ert-deftest emacsvox-reftex-selection-feedback-is-target-aware ()
  "Only the matching RefTeX selection command produces feedback."
  (let ((ems--interactive-fn-name 'reftex-select-next-heading)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda (&rest _) (push 'line events))))
      (emacsvox--advice-reftex-select-previous-heading-after)
      (emacsvox--advice-reftex-select-next-heading-after))
    (should
     (equal
      (nreverse events)
      '(line (icon section))))))

(ert-deftest emacsvox-reftex-toggle-feedback-is-target-aware ()
  "RefTeX TOC toggles report the resulting state."
  (let ((ems--interactive-fn-name 'reftex-toc-toggle-labels)
        (reftex-toc-include-labels t)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message (apply #'format format-string arguments))
                  events))))
      (emacsvox--advice-reftex-toc-toggle-context-after)
      (emacsvox--advice-reftex-toc-toggle-labels-after))
    (should
     (equal
      (nreverse events)
      '((icon on) (message "Turned on labels. "))))))

(ert-deftest emacsvox-reftex-highlight-uses-native-range-arguments ()
  "RefTeX highlighting voices the native BEGIN to END range."
  (with-temp-buffer
    (insert "abcdef")
    (let (events)
      (cl-letf (((symbol-function 'emacsvox-speak-line)
                 (lambda (&rest _) (push 'line events)))
                ((symbol-function 'sit-for)
                 (lambda (seconds &rest _)
                   (push (list 'sit-for seconds) events))))
        (emacsvox--advice-reftex-highlight-after 0 2 5 nil))
      (should
       (eq (get-text-property 2 'personality) voice-bolden))
      (should-not (get-text-property 5 'personality))
      (should
       (equal
        (nreverse events)
        '(line (sit-for 2)))))))

(provide 'emacsvox-reftex-tests)
;;; emacsvox-reftex-tests.el ends here
