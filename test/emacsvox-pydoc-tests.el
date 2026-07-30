;;; emacsvox-pydoc-tests.el --- Pydoc advice tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'package)
(package-initialize)
(require 'pydoc)

(load
 (expand-file-name
  "../lisp/emacsvox-pydoc.el"
  (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-pydoc-current-target-contract ()
  "Pydoc retains its current single-name argument."
  (should (equal (help-function-arglist 'pydoc t) '(name))))

(ert-deftest emacsvox-pydoc-advice-is-directly-registered ()
  "Pydoc advice uses native advice directly."
  (should
   (advice-member-p #'emacsvox--advice-pydoc-after 'pydoc)))

(ert-deftest emacsvox-pydoc-feedback-is-target-aware ()
  "Only an interactive Pydoc invocation announces help."
  (let ((ems--interactive-fn-name 'other-command)
        calls)
    (cl-letf
        (((symbol-function 'emacsvox-pydoc--present-buffer)
          (lambda () (setq calls (1+ (or calls 0))))))
      (emacsvox--advice-pydoc-after)
      (setq ems--interactive-fn-name 'pydoc)
      (emacsvox--advice-pydoc-after))
    (should (= calls 1))))

(ert-deftest emacsvox-pydoc-buffer-is-one-native-submission ()
  "Pydoc content, documentation facts, and help cue are submitted together."
  (with-temp-buffer
    (insert
     (propertize
      "Python documentation" 'face 'pydoc-example-leader-face))
    (let (submission)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq submission (cons content arguments)))))
        (emacsvox-pydoc--present-buffer))
      (pcase-let* ((`(,content . ,arguments) submission)
                   (action
                    (car
                     (plist-get arguments :compatibility-actions))))
        (should (equal content "Python documentation"))
        (should
         (eq
          (get-text-property 0 'face content)
          'pydoc-example-leader-face))
        (should
         (equal
          (plist-get arguments :facts)
          '(:role code-construct :events (focus-entered)
            :syntax-role documentation)))
        (should (eq (plist-get arguments :module) 'python))
        (should (eq (plist-get arguments :occasion) 'navigation))
        (should
         (eq
          (emacsvox-aural-compatibility-action-value action)
          'help))))))

(ert-deftest emacsvox-pydoc-face-map-covers-current-interface ()
  "Every Pydoc face mapped to a voice exists in the installed package."
  (dolist (entry emacsvox-pydoc--face-voice-map)
    (should (facep (car entry)))))

(ert-deftest emacsvox-pydoc-mode-enables-python-aural-context ()
  "Pydoc buffers identify themselves with the shared Python module."
  (with-temp-buffer
    (emacsvox-pydoc-enable-aural-context)
    (should (eq emacsvox-aural-module 'python))))

(provide 'emacsvox-pydoc-tests)
;;; emacsvox-pydoc-tests.el ends here
