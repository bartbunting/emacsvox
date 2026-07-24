;;; emacsvox-markdown-tests.el --- Markdown advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'markdown-mode)
(load (expand-file-name "../lisp/emacsvox-markdown.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-markdown-current-advice-is-direct ()
  "Every available Markdown target uses native advice directly."
  (dolist (entry emacsvox-markdown--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (fboundp target)
        (should (advice-member-p function target))))))

(ert-deftest emacsvox-markdown-speak-line-calls-original-once ()
  "Ordinary buffers delegate to the original speaker exactly once."
  (with-temp-buffer
    (let ((calls 0))
      (should
       (eq
        'spoken
        (emacsvox--advice-markdown-speak-line-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (should (equal arguments '(1)))
           'spoken)
         1)))
      (should (= calls 1)))))

(ert-deftest emacsvox-markdown-delete-calls-original-once ()
  "Markdown deletion gives feedback and invokes its command once."
  (with-temp-buffer
    (insert "x")
    (let ((calls 0)
          (ems--interactive-fn-name 'markdown-outdent-or-delete))
      (cl-letf (((symbol-function 'tts-tone) #'ignore)
                ((symbol-function 'emacsvox-speak-this-char) #'ignore))
        (should
         (eq
          'deleted
          (emacsvox--advice-markdown-outdent-or-delete-around
           (lambda () (cl-incf calls) 'deleted)))))
      (should (= calls 1)))))

(provide 'emacsvox-markdown-tests)
;;; emacsvox-markdown-tests.el ends here
