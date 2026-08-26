;;; emacsvox-man-tests.el --- Man advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Man advice.

;;; Code:

(require 'ert)
(require 'man)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-man.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--man-advice
  '((Man-mode emacsvox--advice-Man-mode-after)
    (Man-goto-section emacsvox--advice-Man-goto-section-after)
    (Man-goto-page emacsvox--advice-Man-goto-page-after)
    (Man-next-manpage emacsvox--advice-Man-next-manpage-after)
    (Man-previous-manpage emacsvox--advice-Man-previous-manpage-after)
    (Man-next-section emacsvox--advice-Man-next-section-after)
    (Man-previous-section emacsvox--advice-Man-previous-section-after)
    (Man-goto-see-also-section
     emacsvox--advice-Man-goto-see-also-section-after)
    (Man-kill emacsvox--advice-Man-kill-after)
    (man emacsvox--advice-man-after))
  "Current Emacs 31 Man targets and their direct after advice.")

(ert-deftest emacsvox-man-advice-is-directly-registered ()
  "Man advice is attached directly to current Emacs 31 targets."
  (dolist (entry emacsvox-test--man-advice)
    (pcase-let ((`(,target ,function) entry))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (should-not (fboundp 'Man-quit)))

(ert-deftest emacsvox-man-mode-setup-remains-unconditional ()
  "Man mode setup runs for normal internal mode initialization."
  (with-temp-buffer
    (let (events)
      (cl-letf (((symbol-function 'tts-apply-punctuation-mode-policy)
                 (lambda () (push 'punctuation-policy events)))
                ((symbol-function
                  'emacsvox-pronounce-refresh-pronunciations)
                 (lambda () (push 'pronunciations events)))
                ((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events))))
        (emacsvox--advice-Man-mode-after))
      (should (equal paragraph-start "^[     \n\f]*$"))
      (should (equal paragraph-separate "^[     \n\f]*$"))
      (should
       (equal
        (nreverse events)
        '(punctuation-policy pronunciations (icon help)))))))

(ert-deftest emacsvox-man-section-feedback-is-target-aware ()
  "Only the matching Man section command produces feedback."
  (let ((ems--interactive-fn-name 'Man-previous-section)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-Man-goto-section-after "NAME")
      (emacsvox--advice-Man-next-section-after 1)
      (emacsvox--advice-Man-previous-section-after 1))
    (should
     (equal
      (nreverse events)
      '((icon section) line)))))

(ert-deftest emacsvox-man-nested-page-movement-is-not-duplicated ()
  "An interactive next-page command does not trigger goto-page feedback."
  (let ((ems--interactive-fn-name 'Man-next-manpage)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-Man-goto-page-after 2)
      (emacsvox--advice-Man-next-manpage-after))
    (should
     (equal
      (nreverse events)
      '((icon large-movement) line)))))

(ert-deftest emacsvox-man-close-feedback-uses-current-kill-command ()
  "Current Man kill feedback cues and reports the selected buffer."
  (let ((ems--interactive-fn-name 'Man-kill)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events))))
      (emacsvox--advice-Man-kill-after)
      (emacsvox--advice-man-after "printf"))
    (should
     (equal
      (nreverse events)
      '((icon close-object) mode-line)))))

(provide 'emacsvox-man-tests)
;;; emacsvox-man-tests.el ends here
