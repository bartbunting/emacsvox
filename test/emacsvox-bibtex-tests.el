;;; emacsvox-bibtex-tests.el --- BibTeX advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated BibTeX advice.

;;; Code:

(require 'ert)
(require 'bibtex)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-bibtex.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--bibtex-after-targets
  '(bibtex-next-field
    bibtex-find-text
    bibtex-beginning-of-entry
    bibtex-end-of-entry
    bibtex-remove-OPT-or-ALT
    bibtex-empty-field
    bibtex-kill-field
    bibtex-clean-entry
    bibtex-Unpublished
    bibtex-String
    bibtex-TechReport
    bibtex-Preamble
    bibtex-Proceedings
    bibtex-PhdThesis
    bibtex-Misc
    bibtex-MastersThesis
    bibtex-Manual
    bibtex-InProceedings
    bibtex-InCollection
    bibtex-InBook
    bibtex-Book
    bibtex-Article)
  "Current Emacs 31 BibTeX targets using direct after advice.")

(ert-deftest emacsvox-bibtex-advice-is-directly-registered ()
  "BibTeX advice is attached once to each current Emacs 31 target."
  (dolist (target emacsvox-test--bibtex-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target)))
          (registrations 0))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (advice-mapc
       (lambda (advice _properties)
         (when (eq advice function)
           (setq registrations (1+ registrations))))
       target)
      (should (= registrations 1))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-bibtex-obsolete-targets-remain-absent ()
  "Loading BibTeX support does not recreate superseded command names."
  (dolist
      (target
       '(end-of-bibtex-entry
         beginning-of-bibtex-entry
         bibtex-remove-OPT
         bibtex-kill-optional-field
         bibtex-string
         bibtex-preamble))
    (should-not (fboundp target))
    (should-not
     (fboundp
      (intern (format "emacsvox--advice-%s-after" target))))))

(ert-deftest emacsvox-bibtex-movement-feedback-is-target-aware ()
  "Only the matching BibTeX movement command produces feedback."
  (let ((ems--interactive-fn-name 'bibtex-end-of-entry)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda (&rest _) (push 'line events))))
      (emacsvox--advice-bibtex-next-field-after)
      (emacsvox--advice-bibtex-end-of-entry-after))
    (should
     (equal
      (nreverse events)
      '((icon large-movement) line)))))

(ert-deftest emacsvox-bibtex-editing-feedback-is-target-aware ()
  "BibTeX field deletion and cleanup retain distinct feedback."
  (let ((ems--interactive-fn-name 'bibtex-kill-field)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda (&rest _) (push 'line events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message (apply #'format format-string arguments))
                  events))))
      (emacsvox--advice-bibtex-clean-entry-after)
      (emacsvox--advice-bibtex-kill-field-after))
    (should
     (equal
      (nreverse events)
      '((icon delete-object) line)))))

(ert-deftest emacsvox-bibtex-entry-feedback-is-target-aware ()
  "Only the matching BibTeX entry command announces creation."
  (let ((ems--interactive-fn-name 'bibtex-InProceedings)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda (&rest _) (push 'line events))))
      (emacsvox--advice-bibtex-Article-after)
      (emacsvox--advice-bibtex-InProceedings-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) line)))))

(provide 'emacsvox-bibtex-tests)
;;; emacsvox-bibtex-tests.el ends here
