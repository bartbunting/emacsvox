;;; emacsvox-bbdb-tests.el --- BBDB advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'bbdb)
(require 'bbdb-com)
(require 'bbdb-mua)
(load (expand-file-name "../lisp/emacsvox-bbdb.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-bbdb-advice-is-current-and-direct ()
  "Current BBDB targets use native advice directly."
  (dolist (entry emacsvox-bbdb--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))))
  (dolist (obsolete '(bbdb-delete-current-field-or-record
                      bbdb-edit-current-field
                      bbdb-send-mail
                      bbdb-bury-buffer
                      bbdb-elide-record
                      bbdb/vm-show-sender
                      bbdb/rmail-show-sender
                      bbdb/mh-show-sender))
    (should-not (fboundp obsolete))))

(ert-deftest emacsvox-bbdb-completion-calls-original-once ()
  "Completion advice preserves the result without repeating the command."
  (with-temp-buffer
    (insert "bar")
    (let ((ems--interactive-fn-name 'bbdb-complete-mail)
          (calls 0)
          spoken)
      (cl-letf (((symbol-function 'tts-speak)
                 (lambda (text) (setq spoken text))))
        (should
         (eq 'completed
             (emacsvox--advice-bbdb-complete-mail-around
              (lambda (&rest _)
                (cl-incf calls)
                (insert "t")
                'completed))))
        (should (= calls 1))
        (should (equal spoken "t"))))))

(provide 'emacsvox-bbdb-tests)
;;; emacsvox-bbdb-tests.el ends here
