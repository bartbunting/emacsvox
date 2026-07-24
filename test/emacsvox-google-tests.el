;;; emacsvox-google-tests.el --- Google advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'gmaps)
(load (expand-file-name "../lisp/emacsvox-google.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-google-advice-is-current-and-direct ()
  "Current bundled GMaps targets use native advice directly."
  (dolist (entry emacsvox-google--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-google-place-details-calls-original-once ()
  "Place-details advice preserves the result and invokes GMaps once."
  (with-temp-buffer
    (let ((ems--interactive-fn-name 'gmaps-place-details)
          (calls 0))
      (cl-letf (((symbol-function 'emacsvox-speak-region) #'ignore))
        (should
         (eq 'details
             (emacsvox--advice-gmaps-place-details-around
              (lambda ()
                (cl-incf calls)
                'details))))
        (should (= calls 1))))))

(provide 'emacsvox-google-tests)
;;; emacsvox-google-tests.el ends here
