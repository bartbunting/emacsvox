;;; emacsvox-sage-tests.el --- Sage advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(require 'emacsvox-preamble)
(package-initialize)
(mapc #'require '(sage-shell-mode sage-shell-blocks))

(defvar emacsvox-test--sage-load-icons nil
  "Auditory icons attempted while loading the Sage integration.")

(let (load-icons)
  (cl-letf
      (((symbol-function 'emacsvox-icon)
        (lambda (icon)
          (push icon load-icons))))
    (load
     (expand-file-name
      "../lisp/emacsvox-sage.el"
      (file-name-directory (or load-file-name buffer-file-name)))
     nil nil))
  (setq
   emacsvox-test--sage-load-icons
   (nreverse load-icons)))

(ert-deftest emacsvox-sage-load-is-audio-hermetic ()
  "Loading the Sage integration does not produce user feedback."
  (should-not emacsvox-test--sage-load-icons))

(ert-deftest emacsvox-sage-advice-is-current-and-direct ()
  "Current Sage targets use native advice directly."
  (dolist (entry emacsvox-sage--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-sage-delete-calls-original-once ()
  "Sage deletion advice preserves feedback order and calls once."
  (with-temp-buffer
    (insert "xy")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'sage-shell:delchar-or-maybe-eof)
          (calls 0)
          events)
      (cl-letf
          (((symbol-function 'emacsvox-speak-edit-operation)
            (lambda (operation)
              (push (list 'edit operation) events)))
           ((symbol-function 'emacsvox-speak-char)
            (lambda (&rest _) (push 'character events))))
        (should
         (eq 'deleted
             (emacsvox--advice-sage-shell:delchar-or-maybe-eof-around
              (lambda (argument)
                (cl-incf calls)
                (push (list 'original argument) events)
                'deleted)
              1)))
        (should (= calls 1))
        (should
         (equal
          (nreverse events)
          '((edit deletion) character (original 1))))))))

(ert-deftest emacsvox-sage-delete-keeps-eof-free-of-edit-feedback ()
  "The Sage EOF branch reports EOF without presenting a deletion."
  (with-temp-buffer
    (insert "xy")
    (goto-char (point-max))
    (let ((ems--interactive-fn-name 'sage-shell:delchar-or-maybe-eof)
          (calls 0)
          events)
      (cl-letf
          (((symbol-function 'message)
            (lambda (format-string &rest arguments)
              (push
               (list 'message
                     (apply #'format format-string arguments))
               events)))
           ((symbol-function 'emacsvox-speak-edit-operation)
            (lambda (operation)
              (push (list 'edit operation) events)))
           ((symbol-function 'emacsvox-speak-char)
            (lambda (&rest _) (push 'character events))))
        (should
         (eq
          (emacsvox--advice-sage-shell:delchar-or-maybe-eof-around
           (lambda (&rest arguments)
             (cl-incf calls)
             (push (cons 'original arguments) events)
             'eof)
           nil)
          'eof)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((message "Sending EOF to comint process")
          (original nil)))))))

(provide 'emacsvox-sage-tests)
;;; emacsvox-sage-tests.el ends here
