;;; emacsvox-navigation-tests.el --- Source navigation advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated source navigation advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)
(require 'text-property-search)

(defconst emacsvox-test--navigation-direct-advice
  '((find-library :after emacsvox--advice-find-library-after)
    (find-function :after emacsvox--advice-find-function-after)
    (find-function-at-point :after
     emacsvox--advice-find-function-at-point-after)
    (find-variable :after emacsvox--advice-find-variable-after)
    (find-variable-at-point :after
     emacsvox--advice-find-variable-at-point-after)
    (find-function-on-key :after
     emacsvox--advice-find-function-on-key-after)
    (imenu :after emacsvox--advice-imenu-after)
    (text-property-search-backward :filter-return
     emacsvox--advice-text-property-search-backward-filter-return)
    (text-property-search-forward :filter-return
     emacsvox--advice-text-property-search-forward-filter-return)
    (help-goto-next-page :after
     emacsvox--advice-help-goto-next-page-after)
    (help-goto-previous-page :after
     emacsvox--advice-help-goto-previous-page-after))
  "Source navigation commands using individually named native advice.")

(ert-deftest emacsvox-navigation-advice-is-directly-registered ()
  "Migrated source navigation advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--navigation-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-find-library-feedback-is-target-aware ()
  "Only an interactive `find-library' invocation speaks the mode line."
  (let ((ems--interactive-fn-name 'find-library)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-imenu-after)
      (emacsvox--advice-find-library-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) speak-mode-line)))))

(ert-deftest emacsvox-find-definition-feedback-is-target-aware ()
  "A matching find-definition command speaks its destination line."
  (let ((ems--interactive-fn-name 'find-variable-at-point)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-find-function-after)
      (emacsvox--advice-find-variable-at-point-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) speak-line)))))

(ert-deftest emacsvox-imenu-feedback-is-target-aware ()
  "Only an interactive `imenu' invocation speaks its destination."
  (let ((ems--interactive-fn-name 'imenu)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-find-function-on-key-after)
      (emacsvox--advice-imenu-after))
    (should
     (equal
      (nreverse events)
      '((icon large-movement) speak-line)))))

(ert-deftest emacsvox-property-search-speaks-matching-range ()
  "An interactive property-search hit is spoken and returned unchanged."
  (let ((ems--interactive-fn-name 'text-property-search-forward)
        (match (make-prop-match :beginning 3 :end 7 :value 'face))
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-region)
               (lambda (start end)
                 (push (list 'speak-region start end) events))))
      (should
       (eq
        (emacsvox--advice-text-property-search-backward-filter-return
         match)
        match))
      (should
       (eq
        (emacsvox--advice-text-property-search-forward-filter-return
         match)
        match)))
    (should
     (equal
      (nreverse events)
      '((speak-region 3 7) (icon select-object))))))

(ert-deftest emacsvox-property-search-announces-a-miss ()
  "An interactive property-search miss warns, speaks, and returns nil."
  (let ((ems--interactive-fn-name 'text-property-search-backward)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (should-not
       (emacsvox--advice-text-property-search-backward-filter-return
        nil)))
    (should
     (equal
      (nreverse events)
      '((icon warn-user) speak-line)))))

(ert-deftest emacsvox-help-page-feedback-is-target-aware ()
  "Only the matching interactive Help page command speaks its destination."
  (let ((ems--interactive-fn-name 'help-goto-previous-page)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-help-goto-next-page-after)
      (emacsvox--advice-help-goto-previous-page-after))
    (should
     (equal
      (nreverse events)
      '((icon scroll) speak-line)))))

(provide 'emacsvox-navigation-tests)
;;; emacsvox-navigation-tests.el ends here
