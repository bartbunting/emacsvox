;;; emacsvox-yaml-tests.el --- YAML advice tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'package)
(package-initialize)
(require 'yaml-mode)

(load
 (expand-file-name
  "../lisp/emacsvox-yaml.el"
  (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-yaml-current-target-contracts ()
  "Every advised YAML target exists with its current arguments."
  (dolist
      (entry
       '((yaml-indent-line nil)
         (yaml-mode nil)
         (yaml-fill-paragraph (&optional justify region))
         (yaml-electric-backspace (arg))
         (yaml-electric-bar-and-angle (arg))
         (yaml-electric-dash-and-dot (arg))))
    (pcase-let ((`(,target ,arguments) entry))
      (should (equal (help-function-arglist target t) arguments)))))

(ert-deftest emacsvox-yaml-advice-is-directly-registered ()
  "YAML advice uses native advice directly."
  (dolist (entry emacsvox-yaml--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-yaml-backspace-calls-original-once ()
  "Electric backspace calls once, passes ARG, and preserves its result."
  (with-temp-buffer
    (insert "ab")
    (let ((ems--interactive-fn-name 'yaml-electric-backspace)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'tts-tone-deletion)
                 (lambda () (push 'tone events)))
                ((symbol-function 'emacsvox-speak-this-char)
                 (lambda (char) (push (list 'char char) events))))
        (should
         (eq
          'deleted
          (emacsvox--advice-yaml-electric-backspace-around
           (lambda (arg)
             (cl-incf calls)
             (should (= arg 2))
             (delete-char -1)
             'deleted)
           2))))
      (should (= calls 1))
      (should (equal (nreverse events) '(tone (char 97)))))))

(ert-deftest emacsvox-yaml-feedback-is-target-aware ()
  "Only matching interactive YAML motion speaks."
  (let ((ems--interactive-fn-name 'yaml-indent-line)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-yaml-electric-bar-and-angle-after)
      (emacsvox--advice-yaml-indent-line-after))
    (should (equal events '(line)))))

(provide 'emacsvox-yaml-tests)
;;; emacsvox-yaml-tests.el ends here
