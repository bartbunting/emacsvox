;;; emacsvox-xkcd-tests.el --- XKCD advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'xkcd)
(require 'browse-url)
(load (expand-file-name "../lisp/emacsvox-xkcd.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-xkcd-advice-is-current-and-direct ()
  "Current XKCD targets use native advice directly."
  (dolist (entry emacsvox-xkcd--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-xkcd-image-advice-calls-original-once ()
  "Graphical image insertion calls its original once and returns its result."
  (let ((calls 0)
        (window-system 'x))
    (should
     (eq 'inserted
         (emacsvox--advice-xkcd-insert-image-around
          (lambda (&rest _)
            (cl-incf calls)
            'inserted)
          "comic.png" 42)))
    (should (= calls 1))))

(ert-deftest emacsvox-xkcd-browser-advice-uses-url-argument ()
  "Browser advice sends URL to EWW without calling its original."
  (let ((original-calls 0)
        opened-url)
    (cl-letf (((symbol-function 'eww-browse-url)
               (lambda (url &rest _)
                 (setq opened-url url)
                 'opened)))
      (should
       (eq 'opened
           (emacsvox--advice-browse-url-default-browser-around
            (lambda (&rest _)
              (cl-incf original-calls))
            "https://xkcd.com/42/" 'new-window)))
      (should (equal opened-url "https://xkcd.com/42/"))
      (should (zerop original-calls)))))

(provide 'emacsvox-xkcd-tests)
;;; emacsvox-xkcd-tests.el ends here
