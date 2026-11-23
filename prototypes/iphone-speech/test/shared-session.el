;;; shared-session.el --- Open a draft in the isolated PC test frame -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Code:
(load (expand-file-name "response.el" (file-name-directory load-file-name)) nil nil t)
(require 'server)
(when (getenv "EMACSVOX_TRIAL_ROUTED")
  (load (expand-file-name "../frame-speech.el" (file-name-directory load-file-name)) nil nil t)
  (iphone-frame-speech-enable))
(defvar iphone-shared-buffer nil)
(defvar-local iphone-test--permission-client nil)
(defvar-local iphone-test--permission-id 0)
(defvar iphone-test--armed-frame nil)
(defvar iphone-test--reply-buffer nil)
(defvar iphone-test--acp-reply nil)

(defun iphone-test--prepare-question (id)
  "Show a disposable upstream question and place point on Submit."
  (unless (buffer-live-p iphone-test--reply-buffer)
    (setq iphone-test--reply-buffer (iphone-test-render-response "Frame confirmation test")))
  (switch-to-buffer iphone-test--reply-buffer)
  (unless (map-elt agent-shell--state :client)
    (map-put! agent-shell--state :client
              (acp-make-client :command "true" :context-buffer (current-buffer)
                               :response-sender #'ignore))
    (setf (alist-get :id (alist-get :session agent-shell--state)) "frame-test"))
  (let ((agent-shell-elicitation--experimental-feature-enabled t))
    (agent-shell--on-request
     :state agent-shell--state
     :acp-request `((method . "elicitation/create") (id . ,id)
                    (params . ((mode . "form") (sessionId . "frame-test")
                               (message . "Confirm test answer")
                               (requestedSchema . ((type . "object")
                                                   (properties . ((note . ((type . "string"))))))))))))
  (goto-char (point-min))
  (while (and (< (point) (point-max))
              (not (eq (map-elt (get-text-property (point) 'agent-shell-elicitation-control) :action) 'submit)))
    (goto-char (next-single-property-change (point) 'agent-shell-elicitation-control nil (point-max))))
  (eq (key-binding (kbd "RET")) 'agent-shell-elicitation-act))

(defun iphone-test--steer ()
  "Send a steering request and hold the ACP reply until the test delivers it."
  (interactive)
  (setq iphone-test--acp-reply nil)
  (cl-letf (((symbol-function 'acp-send-request)
             (lambda (&rest args) (setq iphone-test--acp-reply (plist-get args :on-success)))))
    (agent-shell-experimental--send-steering :state agent-shell--state :prompt "Use the test answer")))

(defun iphone-test-tone (&optional repeat-with-return)
  "Play the receiver's 480 ms Diagnostics tone through the phone frame.
With a prefix argument, open a test buffer where Return plays the tone."
  (interactive "P")
  (unless (and (getenv "EMACSVOX_TRIAL_ROUTED")
               (process-live-p (frame-parameter nil 'emacsvox-phone-speaker)))
    (user-error "Run this command from the connected test phone"))
  (when repeat-with-return
    (let ((buffer (generate-new-buffer "*iPhone tone comparison*")))
      (with-current-buffer buffer
        (insert "Press Return to play the tone. Press q to return to your buffer.\n")
        (goto-char (point-min))
        (special-mode)
        (use-local-map (define-keymap :parent special-mode-map
                        "RET" #'iphone-test-tone
                        "q" (lambda () (interactive) (quit-window t))))
        (set-buffer-modified-p nil))
      (pop-to-buffer-same-window buffer)))
  (tts-stop)
  (tts-tone 660 480 t))

(defun iphone-test-permission (&optional on-next-line)
  "Announce a practice permission or visit its choices.
With a prefix argument, start a fresh request after your next line move."
  (interactive "P")
  (unless (and (getenv "EMACSVOX_TRIAL_ROUTED") (buffer-live-p iphone-shared-buffer)
               (process-live-p (frame-parameter nil 'emacsvox-phone-speaker)))
    (user-error "Run this command from the connected test phone"))
  (if on-next-line
      (progn
        (unless (eq (frame-parameter nil 'emacsvox-conversation) iphone-shared-buffer)
          (user-error "Visit the shared Codex sample before arming practice"))
        (setq iphone-test--armed-frame (selected-frame))
        (add-hook 'post-command-hook #'iphone-test--after-line 90)
        (message "Press Control+n to start permission practice"))
    (iphone-test--show-permission)))

(defun iphone-test--after-line ()
  (let ((frame iphone-test--armed-frame))
    (when (or (not (frame-live-p frame))
              (and (eq frame (selected-frame)) (eq this-command 'next-line)))
      (remove-hook 'post-command-hook #'iphone-test--after-line)
      (setq iphone-test--armed-frame nil)
      (when (frame-live-p frame)
        (run-at-time
         0.25 nil
         (lambda ()
           (when (and (frame-live-p frame) (process-live-p (frame-parameter frame 'emacsvox-phone-speaker))
                      (eq (frame-parameter frame 'emacsvox-conversation) iphone-shared-buffer))
             (with-selected-frame frame (iphone-test--show-permission t)))))))))

(defun iphone-test--show-permission (&optional fresh)
  (with-current-buffer iphone-shared-buffer
    (let* ((client (map-elt agent-shell--state :client))
           (tool-id "phone-listening-test")
           (pending (agent-shell--permission-pending-p :tool-call-id tool-id)))
      (when (and client (not (eq client iphone-test--permission-client)))
        (user-error "This sample already has an agent client"))
      (unless client
        ;; Only this generated sample receives a local ACP response handler.
        (setq iphone-test--permission-client
              (acp-make-client :command "true" :context-buffer (current-buffer)
                               :request-sender #'ignore :notification-sender #'ignore
                               :response-sender #'ignore))
        (map-put! agent-shell--state :client iphone-test--permission-client)
        (setf (alist-get :id (alist-get :session agent-shell--state)) "phone-listening-test"))
      (unless (eq (frame-parameter nil 'emacsvox-conversation) (current-buffer))
        (switch-to-buffer (current-buffer))
        (iphone-frame-speech-subscribe (current-buffer)))
      (when (and fresh pending)
        (save-excursion
          (agent-shell--send-permission-response
           :client iphone-test--permission-client :state agent-shell--state
           :tool-call-id tool-id :request-id pending :cancelled t))
        (setq pending nil))
      (if pending
          (progn (switch-to-buffer (current-buffer))
                 (call-interactively #'agent-shell-jump-to-latest-permission-button-row))
        (let ((agent-shell-permission-responder-function nil))
          (agent-shell--on-request
           :state agent-shell--state
           :acp-request
           `((method . "session/request_permission") (id . ,(cl-incf iphone-test--permission-id))
             (params . ((toolCall . ((toolCallId . ,tool-id) (kind . "read") (status . "pending")
                                     (title . "Read the lighthouse notes for the listening test")))
                        (options . [((kind . "allow_once") (name . "Allow once") (optionId . "allow"))
                                    ((kind . "reject_once") (name . "Reject") (optionId . "reject"))]))))))))))

(defun iphone-shared-show-draft ()
  (when-let* ((id (frame-parameter nil 'emacsvox-phone-id))
              ((not (display-graphic-p)))
              ((buffer-live-p iphone-shared-buffer)))
    (when (getenv "EMACSVOX_TRIAL_ROUTED") (iphone-frame-speech-attach id))
    (if (and (getenv "EMACSVOX_TRIAL_ROUTED") (frame-parameter nil 'emacsvox-native-ssh))
        (unless (iphone-frame-speech--open-terminal-buffer
                 (if (buffer-live-p iphone-frame-speech--entry-buffer)
                     iphone-frame-speech--entry-buffer iphone-shared-buffer))
          (goto-char (point-max)))
      (switch-to-buffer iphone-shared-buffer)
      (goto-char (point-max)))
    (when (getenv "EMACSVOX_TRIAL_ROUTED")
      (unless (frame-parameter nil 'emacsvox-native-ssh)
        (iphone-frame-speech-subscribe iphone-shared-buffer))
      (iphone-frame-speech--packet (frame-parameter nil 'emacsvox-phone-speaker) "attached" id))
    (redisplay t)
    (unless (frame-parameter nil 'emacsvox-native-ssh)
      (call-process "tmux" nil nil nil "-N" "-S"
                  (expand-file-name "tmux.sock" server-socket-dir)
                  "wait-for" "-S" id))))

(defun iphone-shared-prepare ()
  (setq iphone-shared-buffer (iphone-test-render-response))
  (switch-to-buffer iphone-shared-buffer)
  (rename-buffer "Shared Codex sample")
  (emacsvox-agent-shell-edit-input)
  (goto-char (point-max))
  (insert "Started on PC")
  (setq server-name "shared"
        server-socket-dir (getenv "EMACSVOX_SHARED_DIR")
        server-client-instructions nil)
  (add-hook 'server-after-make-frame-hook #'iphone-shared-show-draft)
  (server-start)
  (let ((ready (expand-file-name "ready" server-socket-dir)))
    (with-temp-file (concat ready ".tmp")
      (insert (expand-file-name "emacsclient" invocation-directory)))
    (rename-file (concat ready ".tmp") ready)))

(add-hook 'emacs-startup-hook
          (lambda () (run-with-idle-timer 0.3 nil #'iphone-shared-prepare)))
;;; shared-session.el ends here
