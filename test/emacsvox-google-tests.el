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
      (should (advice-member-p function target)))))

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

(ert-deftest emacsvox-google-open-link-uses-google-result-filter ()
  "Opening a result extracts the link with the shared Google filter."
  (let (arguments)
    (cl-letf (((symbol-function 'shr-url-at-point)
               (lambda (&optional _) "https://example.com/result"))
              ((symbol-function 'add-hook) #'ignore)
              ((symbol-function 'emacsvox-we-extract-by-id-list)
               (lambda (&rest args) (setq arguments args))))
      (emacsvox-google-open-link))
    (should
     (equal arguments
            (list ems--google-filter "https://example.com/result")))))

(ert-deftest emacsvox-gmaps-mode-uses-current-face-symbol ()
  "GMaps applies the current quoted face symbol to its heading."
  (with-temp-buffer
    (let ((gmaps-my-address nil))
      (gmaps-mode))
    (should
     (eq
      (get-text-property (point-min) 'face)
      'font-lock-doc-face))))

(provide 'emacsvox-google-tests)
;;; emacsvox-google-tests.el ends here
