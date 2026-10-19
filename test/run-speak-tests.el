;;; run-speak-tests.el --- Verify core reading extractions -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Run with Emacs -Q --batch -l test/run-speak-tests.el.
;; EMACSVOX_SPEAK_TEST_LOAD=compiled selects current byte-code explicitly.
;; Definition modules must preserve the facade's activation responsibilities.

;;; Code:
(require 'cl-lib)
(require 'ert)
(require 'subr-x)

(defvar emacsvox-speak-test-modules
  '(("emacsvox-speak-status" emacsvox-speak-mode-line emacsvox-speak-header-line emacsvox-battery-alarm emacsvox-speak-net-id)
    ("emacsvox-speak-windows" emacsvox-speak-other-window emacsvox-describe-tapestry emacsvox-cycle-to-next-buffer)
    ("emacsvox-speak-time" emacsvox-speak-time emacsvox-speak-collect-date emacsvox-speak-message-at-time)
    ("emacsvox-speak-completion" emacsvox-get-current-completion emacsvox-completions-move-to-completion-group)
    ("emacsvox-speak-presentation" emacsvox-speak--point-facts emacsvox-speak--indentation-facts emacsvox-set-indentation-presentation)
    ("emacsvox-speak-characters" emacsvox-speak-this-char emacsvox--delayed-phonetic-schedule emacsvox-post-self-insert-hook)
    ("emacsvox-speak-filters" emacsvox-speak-line-apply-column-filter))
  "Extracted modules and representative definitions whose owners are checked.")

(let* ((root (expand-file-name "../" (file-name-directory load-file-name)))
       (compiled (equal (getenv "EMACSVOX_SPEAK_TEST_LOAD") "compiled"))
       (extension (if compiled ".elc" ".el")))
  (setq load-prefer-newer (not compiled))
  (setenv "TTS_PROGRAM" (expand-file-name "servers/log-null" root))
  (dolist (directory '("lisp" "test"))
    (add-to-list 'load-path (expand-file-name directory root)))
  (require 'emacsvox-paths)
  (emacsvox-paths--register (expand-file-name "lisp" root))
  (set 'emacsvox-sounds-dir (expand-file-name "sounds/" root))
  ;; These are existing dependencies of the reading facade.
  (mapc #'require '(tts-speak voice-setup voice-defs emacsvox-pronounce
                   emacsvox-sounds emacsvox-aural-submission sox-gen))
  (cl-labels
      ((activation ()
         (list
          (mapcar (lambda (symbol)
                    (and (boundp symbol)
                         (list (copy-tree (symbol-value symbol))
                               (copy-tree (default-value symbol)))))
                  '(pre-command-hook post-command-hook post-self-insert-hook
                    completion-setup-hook repeat-mode-hook kill-emacs-hook
                    battery-update-functions))
          (mapcar
           (lambda (target)
             (let (entries)
               (advice-mapc (lambda (function properties)
                             (push (cons function properties) entries)) target)
               (cons target entries)))
           '(tts-speak tts-letter tts-dispatch tts-stop))
          (copy-sequence timer-list) (copy-sequence timer-idle-list)
          (process-list) (get-buffer " *Notifications*"))))
    (let ((before (activation)))
      (dolist (module emacsvox-speak-test-modules)
        (load (expand-file-name (concat "lisp/core/" (car module) extension) root)
              nil t t))
      (when (featurep 'emacsvox-speak)
        (error "Reading definitions loaded the activation facade"))
      (unless (equal before (activation))
        (error "Reading definitions changed hooks, advice, timers or processes"))))
  (require 'emacsvox-preamble)
  (load (expand-file-name (concat "lisp/core/emacsvox-speak" extension) root) nil t t)
  (unless (and (buffer-live-p emacsvox-notifications-buffer)
               (memq emacsvox-notifications-gc-timer timer-list))
    (error "Reading activation did not initialize notification history and timer"))
  (unless (and (memq #'emacsvox-post-self-insert-hook post-self-insert-hook)
               (memq #'emacsvox--delayed-phonetic-cancel
                     (default-value 'pre-command-hook))
               (cl-every (lambda (target)
                           (advice-member-p #'emacsvox--delayed-phonetic-cancel target))
                         '(tts-speak tts-letter tts-dispatch tts-stop)))
    (error "Reading activation incomplete: typing=%S mode=%S pre=%S advice=%S"
           (memq #'emacsvox-post-self-insert-hook post-self-insert-hook)
           emacsvox-delayed-phonetic-mode pre-command-hook
           (mapcar (lambda (target)
                     (cons target (and (advice-member-p #'emacsvox--delayed-phonetic-cancel target) t)))
                   '(tts-speak tts-letter tts-dispatch tts-stop))))
  (setq-default emacsvox-speak-messages nil)
  (load (expand-file-name (concat "lisp/core/emacsvox-advice" extension) root) nil t t)
  (dolist (suite '(speak speak-filters speak-command org completion input message navigation
                  position display timer core-migration indentation))
    (load (expand-file-name (format "test/emacsvox-%s-tests.el" suite) root) nil t t))
  (dolist (module (cons '("emacsvox-speak" emacsvox-speak-line)
                       emacsvox-speak-test-modules))
    (dolist (function (cdr module))
      (let ((expected (expand-file-name
                       (concat "lisp/core/" (car module) extension) root))
            (actual (symbol-file function 'defun)))
        (unless (equal actual expected)
          (error "Wrong owner for %s: expected %s, got %s" function expected actual))
        (message "%s: %s" function actual)))))

;; The existing scrolling fixture mocks inlined helpers; keep it source-only.
(ert-run-tests-batch-and-exit
 (if (equal (getenv "EMACSVOX_SPEAK_TEST_LOAD") "compiled")
     '(not (member emacsvox-core-scroll-advice-preserves-semantic-feedback))
   t))

;;; run-speak-tests.el ends here
