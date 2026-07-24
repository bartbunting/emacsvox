;;; emacsvox-erc-tests.el --- ERC advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated ERC advice.

;;; Code:

(require 'ert)
(require 'erc)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-erc.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(ert-deftest emacsvox-erc-advice-is-directly-registered ()
  "ERC advice is attached to current Emacs 31 entry points."
  (dolist
      (entry
       '((erc-mode :after emacsvox--advice-erc-mode-after)
         (erc-select :after emacsvox--advice-erc-select-after)
         (erc-send-current-line
          :after emacsvox--advice-erc-send-current-line-after)
         (erc-insert-line :after emacsvox--advice-erc-insert-line-after)
         (erc-parse-server-response
          :around emacsvox--advice-erc-parse-server-response-around)))
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-erc-does-not-recreate-removed-commands ()
  "Loading the integration leaves removed ERC entry points undefined."
  (dolist
      (target
       '(erc-send-paragraph
         erc-display-line-buffer
         erc-parse-line-from-server))
    (should-not (fboundp target))))

(ert-deftest emacsvox-erc-key-bindings-use-a-real-prefix ()
  "The ERC local map retains all Emacsvox commands under `C-c'."
  (should
   (eq
    (lookup-key erc-mode-map (kbd "C-c SPC"))
    'emacsvox-erc-toggle-speak-all-participants))
  (should
   (eq
    (lookup-key erc-mode-map (kbd "C-c m"))
    'emacsvox-erc-toggle-my-monitor))
  (should
   (eq
    (lookup-key erc-mode-map (kbd "C-c C-m"))
    'emacsvox-erc-toggle-room-monitor)))

(ert-deftest emacsvox-erc-mode-enables-voice-lock ()
  "Entering ERC refreshes pronunciations and enables voice lock."
  (let ((voice-lock-mode nil)
        refreshed)
    (cl-letf (((symbol-function
                'emacsvox-pronounce-refresh-pronunciations)
               (lambda () (setq refreshed t))))
      (emacsvox--advice-erc-mode-after))
    (should refreshed)
    (should voice-lock-mode)))

(ert-deftest emacsvox-erc-command-feedback-is-target-aware ()
  "ERC selection and sending retain distinct interactive feedback."
  (let ((ems--interactive-fn-name 'erc-send-current-line)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events))))
      (emacsvox--advice-erc-select-after)
      (emacsvox--advice-erc-send-current-line-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object))))))

(ert-deftest emacsvox-erc-inserted-monitored-message-is-spoken ()
  "A monitored inserted message is announced once in its ERC buffer."
  (with-temp-buffer
    (setq-local emacsvox-erc-room-monitor t)
    (setq-local emacsvox-erc-monitor-my-messages t)
    (setq-local emacsvox-erc-speak-all-participants t)
    (let (events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push
                    (list 'message
                          (apply #'format format-string arguments)
                          emacsvox-speak-messages)
                    events)))
                ((symbol-function 'dtk-speak)
                 (lambda (text) (push (list 'speak text) events))))
        (emacsvox--advice-erc-insert-line-after
         "<bart> hello" (current-buffer)))
      (should
       (equal
        (nreverse events)
        '((icon progress)
          (message "<bart> hello" nil)
          (speak "<bart> hello")))))))

(ert-deftest emacsvox-erc-unmonitored-message-is-quiet ()
  "An inserted message is quiet when room monitoring is disabled."
  (with-temp-buffer
    (setq-local emacsvox-erc-room-monitor nil)
    (setq-local emacsvox-erc-monitor-my-messages t)
    (setq-local emacsvox-erc-speak-all-participants t)
    (let (events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (&rest arguments) (push arguments events)))
                ((symbol-function 'dtk-speak)
                 (lambda (&rest arguments) (push arguments events))))
        (emacsvox--advice-erc-insert-line-after
         "<bart> hello" (current-buffer)))
      (should-not events))))

(ert-deftest emacsvox-erc-server-parser-runs-once-quietly ()
  "The current ERC parser is called once with message speech silenced."
  (let ((calls 0))
    (should
     (eq
      'result
      (emacsvox--advice-erc-parse-server-response-around
       (lambda (&rest arguments)
         (setq calls (1+ calls))
         (should (equal arguments '(process "PING")))
         (should-not emacsvox-speak-messages)
         'result)
       'process "PING")))
    (should (= calls 1))))

(provide 'emacsvox-erc-tests)
;;; emacsvox-erc-tests.el ends here
