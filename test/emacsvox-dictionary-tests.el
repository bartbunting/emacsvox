;;; emacsvox-dictionary-tests.el --- Dictionary advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Dictionary advice.

;;; Code:

(require 'ert)
(require 'dictionary)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-dictionary.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--dictionary-after-targets
  '(dictionary
    dictionary-close
    dictionary-select-dictionary
    dictionary-select-strategy
    dictionary-search
    dictionary-lookup-definition
    dictionary-match-words
    dictionary-previous)
  "Current Emacs 31 Dictionary targets using direct after advice.")

(ert-deftest emacsvox-dictionary-advice-is-directly-registered ()
  "Dictionary advice is attached directly to current Emacs 31 targets."
  (dolist (target emacsvox-test--dictionary-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (should-not (fboundp 'dictionary-prev-link))
  (should-not (fboundp 'dictionary-next-link))
  (should
   (eq (lookup-key dictionary-mode-map "n") 'forward-button))
  (should
   (eq (lookup-key dictionary-mode-map "p") 'backward-button)))

(ert-deftest emacsvox-dictionary-selection-feedback-is-target-aware ()
  "Only the matching Dictionary selection command produces feedback."
  (let ((ems--interactive-fn-name 'dictionary-select-strategy)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push (apply #'format format-string arguments) events))))
      (emacsvox--advice-dictionary-select-dictionary-after)
      (emacsvox--advice-dictionary-select-strategy-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) "Selected strategy")))))

(ert-deftest emacsvox-dictionary-search-feedback-is-target-aware ()
  "Only the matching Dictionary search operation cues and speaks."
  (let ((ems--interactive-fn-name 'dictionary-lookup-definition)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-dictionary-search-after "word")
      (emacsvox--advice-dictionary-lookup-definition-after))
    (should
     (equal
      (nreverse events)
      '((icon search-hit) line)))))

(ert-deftest emacsvox-dictionary-lifecycle-feedback-is-target-aware ()
  "Dictionary open and close operations retain distinct feedback."
  (let ((ems--interactive-fn-name 'dictionary-close)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events))))
      (emacsvox--advice-dictionary-after)
      (emacsvox--advice-dictionary-close-after))
    (should
     (equal
      (nreverse events)
      '((icon close-object) mode-line)))))

(provide 'emacsvox-dictionary-tests)
;;; emacsvox-dictionary-tests.el ends here
