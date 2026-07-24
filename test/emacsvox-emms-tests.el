;;; emacsvox-emms-tests.el --- EMMS advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(dolist (feature
         '(emms emms-browser emms-info emms-playlist-mode emms-streams))
  (require feature))
(load (expand-file-name "../lisp/emacsvox-emms.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-emms-advice-is-current-and-direct ()
  "Current EMMS targets use native advice directly."
  (dolist (entry emacsvox-emms--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))))
  (dolist (target emacsvox-emms--removed-targets)
    (should-not (fboundp target))))

(ert-deftest emacsvox-emms-feedback-is-target-aware ()
  "Only the matching interactive EMMS command provides feedback."
  (let ((ems--interactive-fn-name 'emms-next)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-emms-previous-after)
      (emacsvox--advice-emms-next-after))
    (should (equal events '(select-object)))))

(ert-deftest emacsvox-emms-silencing-advice-preserves-result ()
  "The EMMS metadata advice calls its original exactly once."
  (let ((calls 0))
    (should
     (eq 'track
         (emacsvox--advice-emms-info-really-initialize-track-around
          (lambda (&rest _)
            (cl-incf calls)
            'track))))
    (should (= calls 1))))

(provide 'emacsvox-emms-tests)
;;; emacsvox-emms-tests.el ends here
