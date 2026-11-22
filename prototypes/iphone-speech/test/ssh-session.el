;;; ssh-session.el --- Prepare an isolated TTY attachment test -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Code:
(load (expand-file-name "response.el" (file-name-directory load-file-name)) nil nil t)
(require 'server)
(defvar iphone-ssh-test-buffer nil)

(defun iphone-ssh-test--mark (name)
  (with-temp-file (expand-file-name name (getenv "EMACSVOX_SSH_TEST_DIR")) (insert "1")))

(defun iphone-ssh-test--prompt-ready ()
  (when (and (minibufferp) (equal (minibuffer-contents-no-properties) "forward-ch"))
    (remove-hook 'post-command-hook #'iphone-ssh-test--prompt-ready t)
    (add-hook 'minibuffer-exit-hook (lambda () (iphone-ssh-test--mark "prompt-closed")) nil t)
    ;; Observe from WSL without issuing an emacsclient evaluation that can
    ;; itself receive the asynchronous Control+g intended for this prompt.
    (run-with-idle-timer 0.05 nil #'iphone-ssh-test--mark "prompt-ready")))

(add-hook 'minibuffer-setup-hook
          (lambda ()
            (unless (display-graphic-p)
              (add-hook 'post-command-hook #'iphone-ssh-test--prompt-ready nil t))))

(defun iphone-ssh-prepare-session ()
  (setq iphone-ssh-test-buffer (iphone-test-render-response))
  (with-current-buffer iphone-ssh-test-buffer
    (rename-buffer "Phone SSH sample")
    (goto-char (point-min))
    (search-forward "Starting row")
    (beginning-of-line))
  (unless (server-running-p server-name) (server-start))
  (with-temp-file (expand-file-name "server-path" (getenv "EMACSVOX_SSH_TEST_DIR"))
    (insert (expand-file-name server-name server-socket-dir))))

(defun iphone-ssh-start-test ()
  ;; Prepare the sample once the graphical frame has entered its command loop.
  (run-with-idle-timer
   0.2 nil
   (lambda ()
     (condition-case err
         (iphone-ssh-prepare-session)
       (error
        (with-temp-file (expand-file-name "startup-error" (getenv "EMACSVOX_SSH_TEST_DIR"))
          (insert (symbol-name (car err)))))))))

(add-hook 'emacs-startup-hook #'iphone-ssh-start-test)
;;; ssh-session.el ends here
