;;; verify-compiled-aural.el --- Clean compiled aural checks -*- lexical-binding: t; -*-

;;; Commentary:

;; This file is run only by `run-compiled-aural-tests.el' in a clean child
;; Emacs whose build directory contains freshly compiled aural entry points.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(let* ((build-directory
        (or
         (getenv "EMACSVOX_COMPILED_AURAL_DIR")
         (error "EMACSVOX_COMPILED_AURAL_DIR is not set")))
       (root-directory
        (or
         (getenv "EMACSVOX_COMPILED_AURAL_ROOT")
         (error "EMACSVOX_COMPILED_AURAL_ROOT is not set")))
       (lisp-directory (expand-file-name "lisp/" root-directory)))
  (add-to-list 'load-path lisp-directory)
  (add-to-list 'load-path build-directory)
  (load (expand-file-name "tts-speak.elc" build-directory) nil nil)
  (load (expand-file-name "emacsvox-aural-tools.elc" build-directory) nil nil)
  (load (expand-file-name "emacsvox-keymap.elc" build-directory) nil nil)
  (dolist
      (function
       '(tts--protocol-queue-text
         emacsvox-aural-tools--training-presented
         emacsvox-keymap-update))
    (unless
        (string-suffix-p
         ".elc" (or (symbol-file function 'defun) ""))
      (error "%S was not loaded from byte-code: %S"
             function (symbol-file function 'defun))))
  (unless (eq (lookup-key emacsvox-keymap (kbd "H")) 'emacsvox-aural)
    (error "Compiled keymap does not bind C-e H to the aural home"))
  (unless
      (eq
       (lookup-key emacsvox-keymap (kbd "E"))
       'emacsvox-aural-explain-presentation)
    (error "Compiled keymap does not bind C-e E to explanation"))
  (let ((emacsvox-aural-session-rules
         (list
          '(:id compiled-preview
            :match (:role heading)
            :render
            (:before
             ((:id label :kind speech :text "Compiled preview"))))))
        ensured queued dispatched)
    (cl-letf
        (((symbol-function 'emacsvox-aural--ensure-speaker)
          (lambda () (setq ensured t)))
         ((symbol-function 'emacsvox-aural-queue-concrete-plan)
          (lambda (plan &rest _) (setq queued plan)))
         ((symbol-function 'tts--protocol-dispatch)
          (lambda () (setq dispatched t))))
      (emacsvox-preview-aural-rule
       'compiled-preview
       '(:role heading :content "Title")
       '(:occasion navigation)))
    (unless
        (and
         ensured dispatched
         (equal
          (emacsvox-aural-concrete-action-text
           (car (emacsvox-aural-concrete-plan-before queued)))
          "Compiled preview"))
      (error "Compiled preview bypassed replaceable boundaries")))
  (let ((plan
         (emacsvox-aural--make-concrete-plan
          :facts '(:role heading :level 2)
          :context '(:occasion navigation)))
        events)
    (cl-letf
        (((symbol-function 'tts-voice-reset-code) (lambda () "RESET"))
         ((symbol-function 'tts--protocol-queue-code)
          (lambda (code) (push (list 'code code) events)))
         ((symbol-function 'tts--protocol-queue-text)
          (lambda (text) (push (list 'text text) events))))
      (emacsvox-aural-tools--training-presented plan))
    (unless
        (equal
         (nreverse events)
         '((code "RESET")
           (text "heading, level 2, navigation occasion.")))
      (error "Compiled training bypassed protocol extension points: %S"
             events)))
  (let* ((calls 0)
         (advice (lambda (&rest _) (cl-incf calls))))
    (unwind-protect
        (progn
          (advice-add 'tts--protocol-stop :before advice)
          (cl-letf
              (((symbol-function 'process-send-string)
                (lambda (&rest _) nil)))
            (let ((tts-speaker-process 'speaker))
              (tts--protocol-stop)))
          (unless (= calls 1)
            (error "Compiled protocol function bypassed native advice")))
      (advice-remove 'tts--protocol-stop advice))))

;;; verify-compiled-aural.el ends here
