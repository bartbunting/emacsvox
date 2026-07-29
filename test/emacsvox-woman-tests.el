;;; emacsvox-woman-tests.el --- WoMan advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'woman)
(require 'emacsvox-man)
(load
 (expand-file-name "../lisp/emacsvox-woman.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-woman-man-face-mapping-conflict-is-visible ()
  "The conflicting Man and WoMan mapping is reported with provenance."
  (let* ((diagnostic
          (voice-setup-face-mapping-diagnostic 'Man-overstrike))
         (declarations (plist-get diagnostic :declarations)))
    (should (plist-get diagnostic :conflict))
    (should
     (equal
      (mapcar
       (lambda (record)
         (cons
          (plist-get record :origin)
          (plist-get record :voice)))
       declarations)
      '((emacsvox-man . voice-bolden-medium)
        (emacsvox-woman . voice-animate))))))

(ert-deftest emacsvox-woman-advice-is-directly-registered ()
  (dolist (target '(WoMan-next-manpage WoMan-previous-manpage))
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (commandp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-woman-feedback-is-target-aware ()
  (let ((ems--interactive-fn-name 'WoMan-previous-manpage) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events))))
      (emacsvox--advice-WoMan-next-manpage-after)
      (emacsvox--advice-WoMan-previous-manpage-after))
    (should
     (equal (nreverse events) '(select-object mode-line)))))

(provide 'emacsvox-woman-tests)
