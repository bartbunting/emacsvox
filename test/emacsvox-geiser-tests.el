;;; emacsvox-geiser-tests.el --- Geiser advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(mapc #'require '(geiser geiser-compile geiser-doc geiser-edit geiser-mode
                  geiser-repl geiser-xref))
(load (expand-file-name "../lisp/emacsvox-geiser.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-geiser-advice-is-current-and-direct ()
  "Current Geiser targets use native advice directly."
  (dolist (entry emacsvox-geiser--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-geiser-around-advice-calls-original-once ()
  "Geiser REPL advice preserves the result without duplicate sends."
  (with-temp-buffer
    (let ((ems--interactive-fn-name 'geiser-repl--maybe-send)
          (calls 0))
      (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
                ((symbol-function 'emacsvox-speak-region) #'ignore))
        (should
         (eq 'sent
             (emacsvox--advice-geiser-repl--maybe-send-around
              (lambda ()
                (cl-incf calls)
                'sent))))
        (should (= calls 1))))))

(provide 'emacsvox-geiser-tests)
;;; emacsvox-geiser-tests.el ends here
