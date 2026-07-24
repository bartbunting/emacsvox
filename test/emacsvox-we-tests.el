;;; emacsvox-we-tests.el --- Web extraction advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(mapc #'require '(url url-cookie url-history url-http))
(load (expand-file-name "../lisp/emacsvox-we.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-we-url-advice-is-current-and-direct ()
  "Current URL targets use native advice directly."
  (dolist (target emacsvox-we--url-advice-targets)
    (let ((function (intern (format "emacsvox--advice-%s-around" target))))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-we-url-advice-preserves-result ()
  "URL advice calls its original once and preserves the return value."
  (let ((calls 0))
    (should
     (eq 'saved
         (emacsvox--advice-url-history-save-history-around
          (lambda (&rest _)
            (cl-incf calls)
            'saved)
          "history-file")))
    (should (= calls 1))))

(provide 'emacsvox-we-tests)
;;; emacsvox-we-tests.el ends here
