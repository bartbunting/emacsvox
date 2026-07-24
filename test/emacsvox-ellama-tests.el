;;; emacsvox-ellama-tests.el --- Ellama advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'ellama)
(load (expand-file-name "../lisp/emacsvox-ellama.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-ellama-advice-is-current-and-direct ()
  "Current Ellama targets use native advice directly."
  (dolist (target emacsvox-ellama--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function) ems--modern-advice-wrappers))))
  (dolist (target emacsvox-ellama--removed-targets)
    (should-not (fboundp target))))

(ert-deftest emacsvox-ellama-request-feedback-is-target-aware ()
  "Only the matching interactive Ellama request command speaks."
  (let ((ems--interactive-fn-name 'ellama-ask-line)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'dtk-speak)
               (lambda (text) (push text events))))
      (emacsvox--advice-ellama-ask-selection-after)
      (emacsvox--advice-ellama-ask-line-after))
    (should (equal (nreverse events) '(select-object "Calling LLM")))))

(ert-deftest emacsvox-ellama-chat-done-speaks-text-argument ()
  "Ellama completion feedback uses the callback's text argument."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'dtk-speak)
               (lambda (text) (push text events))))
      (emacsvox--advice-ellama-chat-done-after "answer"))
    (should (equal (nreverse events) '(item "answer")))))

(provide 'emacsvox-ellama-tests)
;;; emacsvox-ellama-tests.el ends here
