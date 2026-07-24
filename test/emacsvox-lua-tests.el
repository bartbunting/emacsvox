;;; emacsvox-lua-tests.el --- Lua advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'lua-mode)
(load
 (expand-file-name "../lisp/emacsvox-lua.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(defconst emacsvox-test--lua-targets
  '(lua-backwards-to-block-begin-or-end
    lua-beginning-of-proc lua-end-of-proc lua-forward-sexp
    lua-goto-matching-block lua-start-process lua-kill-process
    lua-search-documentation lua-send-buffer lua-send-current-line
    lua-send-lua-region lua-send-proc lua-send-region
    lua-show-process-buffer))

(ert-deftest emacsvox-lua-advice-is-directly-registered ()
  (dolist (target emacsvox-test--lua-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (commandp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-lua-navigation-feedback-is-target-aware ()
  (let ((ems--interactive-fn-name 'lua-end-of-proc) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-lua-beginning-of-proc-after)
      (emacsvox--advice-lua-end-of-proc-after))
    (should (equal (nreverse events) '(large-movement line)))))

(ert-deftest emacsvox-lua-send-feedback-is-target-aware ()
  (let ((ems--interactive-fn-name 'lua-send-region) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-lua-send-buffer-after)
      (emacsvox--advice-lua-send-region-after))
    (should (equal events '(task-done)))))

(ert-deftest emacsvox-lua-programmatic-advice-is-quiet ()
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (&rest args) (push args events))))
      (emacsvox--advice-lua-start-process-after)
      (emacsvox--advice-lua-send-buffer-after))
    (should-not events)))

(provide 'emacsvox-lua-tests)
