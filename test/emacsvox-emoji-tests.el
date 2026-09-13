;;; emacsvox-emoji-tests.el --- Emoji preparation tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'emacsvox-emoji)

(ert-deftest emacsvox-emoji-bundled-trial-names ()
  (dolist (entry '(("🔮" . "crystal ball") ("✨" . "sparkles")
                   ("✅" . "check mark button") ("⚠️" . "warning")
                   ("🚀" . "rocket") ("💡" . "light bulb")
                   ("👩‍💻" . "woman technologist")
                   ("👍🏽" . "thumbs up: medium skin tone")))
    (let ((result (emacsvox-emoji--lookup (car entry))))
      (should (equal (plist-get result :name) (cdr entry)))
      (should (plist-get result :data-file))
      (should (equal (plist-get result :emacs-version) emacs-version)))))

(ert-deftest emacsvox-emoji-lookup-does-not-name-unknown-components ()
  (should (eq (plist-get (emacsvox-emoji--lookup "🔮‍🚀") :diagnostic)
              'missing-name)))

(ert-deftest emacsvox-emoji-lookup-data-failures-are-bounded ()
  (require 'emoji-labels)
  (dolist (table (list nil '(invalid) (make-hash-table :test 'eq)))
    (let ((emoji--names table))
      (should (equal (emacsvox-emoji--lookup "🔮")
                     '(:diagnostic unavailable-data)))))
  (let ((emoji--names (make-hash-table :test 'equal)))
    (puthash "🔮" 42 emoji--names)
    (should (equal (emacsvox-emoji--lookup "🔮") '(:diagnostic missing-name))))
  (cl-letf (((symbol-function 'require) (lambda (&rest _) (error "missing"))))
    (should (equal (emacsvox-emoji--lookup "🔮")
                   '(:diagnostic unavailable-data)))))

(provide 'emacsvox-emoji-tests)
;;; emacsvox-emoji-tests.el ends here
