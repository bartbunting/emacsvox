;;; emacsvox-enriched-tests.el --- Enriched advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'enriched)
(require 'ert)
(load
 (expand-file-name "../lisp/emacsvox-enriched.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-enriched-advice-is-directly-registered ()
  (dolist
      (entry
       '((enriched-decode emacsvox--advice-enriched-decode-after)
         (enriched-mode emacsvox--advice-enriched-mode-after)))
    (pcase-let ((`(,target ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-enriched-decode-uses-native-bounds ()
  (let (bounds)
    (cl-letf (((symbol-function 'emacsvox-enriched-voiceify-faces)
               (lambda (from to) (setq bounds (list from to)))))
      (emacsvox--advice-enriched-decode-after 2 7))
    (should (equal bounds '(2 7)))))

(ert-deftest emacsvox-enriched-mode-uses-buffer-bounds ()
  (with-temp-buffer
    (insert "rich text")
    (let (bounds)
      (cl-letf (((symbol-function 'emacsvox-enriched-voiceify-faces)
                 (lambda (from to) (setq bounds (list from to)))))
        (emacsvox--advice-enriched-mode-after))
      (should (equal bounds (list (point-min) (point-max)))))))

(provide 'emacsvox-enriched-tests)
