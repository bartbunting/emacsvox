;;; frame-speech.el --- Route foreground commands in the shared-frame trial -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Code:
(require 'cl-lib)
(require 'json)
(defvar tts-program)
(defvar tts-speech-rate)
(defvar tts-speaker-process)
(defvar tts-notify-process)
(defvar server-socket-dir)
(defvar-local iphone-frame-speech--subscriber nil)
(defvar-local iphone-frame-speech--buffer-id nil)
(defvar iphone-frame-speech--next-buffer-id 0)
(defvar iphone-frame-speech--request-id nil)
(defconst iphone-frame-speech--program
  (expand-file-name "phone-backend" (file-name-directory load-file-name)))
(defvar iphone-frame-speech--directory nil)
(defvar iphone-frame-speech--entry-buffer nil)
(defvar iphone-frame-speech--last-terminal nil)
(defvar iphone-frame-speech--position (make-marker))
(defvar iphone-frame-speech--command-owner nil)
(defvar iphone-frame-speech--hook-owner nil)
(defvar iphone-frame-speech--bound nil)

(defun iphone-frame-speech--owner ()
  (if (frame-parameter nil 'emacsvox-phone-id)
      (or (frame-parameter nil 'emacsvox-phone-speaker) 'disconnected)
    'desktop))

(defun iphone-frame-speech--pre-command ()
  (setq iphone-frame-speech--hook-owner (iphone-frame-speech--owner)))

(defun iphone-frame-speech--post-command ()
  (when (frame-parameter nil 'emacsvox-phone-speaker)
    (when-let* ((shell (cond ((derived-mode-p 'agent-shell-mode) (current-buffer))
                             ((derived-mode-p 'agent-shell-viewport-view-mode 'agent-shell-viewport-edit-mode)
                              (emacsvox-agent-shell--viewport-session-buffer (current-buffer))))))
      (iphone-frame-speech-subscribe shell))
    (iphone-frame-speech--remember (selected-frame)))
  (setq iphone-frame-speech--hook-owner nil))

(defun iphone-frame-speech--command (original &rest args)
  ;; A command may switch the selected frame or enter a recursive minibuffer.
  (let ((iphone-frame-speech--command-owner (iphone-frame-speech--owner)))
    (apply original args)))

(defun iphone-frame-speech--key-echo (original text)
  ;; Emacs displays a partial key sequence before either command hook runs.
  ;; Other messages can arrive while the phone is the selected frame.
  (let* ((keys (and (frame-parameter nil 'emacsvox-phone-id)
                    (this-single-command-keys)))
         (name (and (length> keys 0) (key-description keys)))
         (iphone-frame-speech--command-owner
          (or iphone-frame-speech--command-owner iphone-frame-speech--hook-owner
              (and name (stringp text)
                   (or (equal text name) (equal text (concat name "-"))
                       (string-prefix-p (concat name "- (") text))
                   (iphone-frame-speech--owner)))))
    (funcall original text)))

(defun iphone-frame-speech--stop (original &optional all)
  ;; Preserve the desktop command's interactive stop of both speech lanes.
  (interactive (list 'iphone-explicit-stop))
  (let ((owner (or iphone-frame-speech--command-owner iphone-frame-speech--hook-owner)))
    (iphone-frame-speech--route original all)
    ;; Several typing and movement commands call (tts-stop 'all) before
    ;; giving feedback. Only explicit Stop clears an urgent phone request.
    (when (and (eq all 'iphone-explicit-stop) (processp owner) (process-live-p owner))
      (iphone-frame-speech--packet owner "stop-all" 0))))

(defun iphone-frame-speech--route (original &rest args)
  (let ((owner (or iphone-frame-speech--command-owner iphone-frame-speech--hook-owner)))
    (cond
     ((or iphone-frame-speech--bound (null owner) (eq owner 'desktop))
      (apply original args))
     ((and (processp owner) (process-live-p owner))
      ;; The existing delivery scheduler keys pending work and Stop by process.
      (let ((iphone-frame-speech--bound t)
            (tts-program iphone-frame-speech--program)
            (tts-speaker-process owner)
            (tts-speech-rate (or (process-get owner 'iphone-speech-rate) 150))
            (tts-notify-process owner))
        (apply original args))))))

(defun iphone-frame-speech--set-rate (original rate &optional prefix)
  (let ((owner (or iphone-frame-speech--command-owner iphone-frame-speech--hook-owner)))
    (if (and (processp owner) (process-live-p owner))
        (progn
          (process-put owner 'iphone-speech-rate rate)
          (iphone-frame-speech--route original rate nil))
      (funcall original rate prefix))))

(defun iphone-frame-speech-attach (id)
  "Give the selected test frame its own speech worker for connection ID."
  (let ((directory (or iphone-frame-speech--directory server-socket-dir)))
    (unless (and (stringp id)
                 (string-match-p "\\`phone-[0-9a-f]\\{8\\}\\(?:-[0-9a-f]\\{4\\}\\)\\{3\\}-[0-9a-f]\\{12\\}\\'" id)
                 (file-exists-p (expand-file-name (concat id ".sock") directory)))
      (user-error "The phone speech connection has expired"))
    (let ((process-environment (copy-sequence process-environment))
          (tts-program iphone-frame-speech--program))
      (setenv "EMACSVOX_PHONE_SOCKET" (expand-file-name (concat id ".sock") directory))
      (set-frame-parameter nil 'emacsvox-phone-speaker (tts-make-process "Phone frame")))))

(defun iphone-frame-speech--remember (frame)
  (when (and (eq frame iphone-frame-speech--last-terminal) (frame-live-p frame))
    (let ((window (frame-selected-window frame)))
      (unless (window-minibuffer-p window)
        (set-marker iphone-frame-speech--position (window-point window) (window-buffer window))))))

(defun iphone-frame-speech--open-terminal-buffer (conversation)
  ;; Each opted-in relay serves one phone. A late detach from a replaced
  ;; frame must not overwrite the position on its successor.
  (iphone-frame-speech--remember iphone-frame-speech--last-terminal)
  (setq iphone-frame-speech--last-terminal (selected-frame))
  (when (buffer-live-p conversation) (iphone-frame-speech-subscribe conversation))
  (if-let* ((saved (marker-buffer iphone-frame-speech--position)))
      (progn (switch-to-buffer saved) (goto-char iphone-frame-speech--position) t)
    (when (buffer-live-p conversation) (switch-to-buffer conversation))
    nil))

(defun iphone-frame-speech--detach (frame)
  (when-let* ((owner (frame-parameter frame 'emacsvox-phone-speaker)))
    (iphone-frame-speech--remember frame)
    (when (eq frame iphone-frame-speech--last-terminal)
      (setq iphone-frame-speech--last-terminal nil))
    (when-let* ((buffer (frame-parameter frame 'emacsvox-conversation)) ((buffer-live-p buffer)))
      (with-current-buffer buffer
        (when (eq iphone-frame-speech--subscriber frame)
          (setq iphone-frame-speech--subscriber nil))))
    (set-frame-parameter frame 'emacsvox-phone-speaker nil)
    (tts--retire-process owner)))

(defun iphone-frame-speech--close-terminal (frame)
  (when (and (frame-live-p frame) (not (display-graphic-p frame))
             (frame-parameter frame 'emacsvox-native-ssh))
    (iphone-frame-speech--detach frame)
    ;; The launcher never terminates the server that owns the conversation.
    (when (or (daemonp) (cdr (frame-list)))
      (delete-frame frame))))

(defun iphone-frame-speech-subscribe (buffer)
  "Deliver Agent Shell events from BUFFER to the attached phone frame."
  (let* ((frame (selected-frame))
         (owner (frame-parameter frame 'emacsvox-phone-speaker))
         (old (frame-parameter frame 'emacsvox-conversation)))
    (unless (eq buffer old)
      (dolist (id (process-get owner 'iphone-requests))
        (iphone-frame-speech--packet owner "resolved" id))
      (when (buffer-live-p old)
        (with-current-buffer old
          (when (eq iphone-frame-speech--subscriber frame)
            (setq iphone-frame-speech--subscriber nil))))
      (when (or iphone-frame-speech--directory (frame-parameter frame 'emacsvox-native-ssh))
        (setq iphone-frame-speech--entry-buffer buffer))
      (set-frame-parameter frame 'emacsvox-conversation buffer)
      (with-current-buffer buffer (setq iphone-frame-speech--subscriber frame))
      (when (process-get owner 'iphone-synced)
        (iphone-frame-speech-control (frame-parameter frame 'emacsvox-phone-id) 'sync 0)))))

(defun iphone-frame-speech--permission-id (key)
  (unless iphone-frame-speech--buffer-id
    (setq iphone-frame-speech--buffer-id (cl-incf iphone-frame-speech--next-buffer-id)))
  (format "%d:%S" iphone-frame-speech--buffer-id key))

(defun iphone-frame-speech--subscriber ()
  (when (and iphone-frame-speech--subscriber (frame-live-p iphone-frame-speech--subscriber))
    (frame-parameter iphone-frame-speech--subscriber 'emacsvox-phone-speaker)))

(defun iphone-frame-speech--event (original &rest args)
  (let* ((owner (iphone-frame-speech--subscriber))
         (iphone-frame-speech--command-owner (or owner 'desktop))
         (data (plist-get args :data))
         (key (or (map-elt data :request-id) (map-elt data :tool-call-id)))
         (iphone-frame-speech--request-id
          (and owner key (eq (plist-get args :event) 'permission-request)
               (iphone-frame-speech--permission-id key))))
    (when (and owner (process-live-p owner) key (eq (plist-get args :event) 'permission-response))
      (iphone-frame-speech--packet owner "resolved" (iphone-frame-speech--permission-id key)))
    (apply original args)))

(defun iphone-frame-speech--deferred (original buffer &rest args)
  (when (buffer-live-p buffer)
    (let ((iphone-frame-speech--command-owner
           (or (with-current-buffer buffer (iphone-frame-speech--subscriber)) 'desktop)))
      (apply original buffer args))))

(defun iphone-frame-speech--focused (original &optional buffer)
  (let* ((target (or buffer (current-buffer)))
         (frame (buffer-local-value 'iphone-frame-speech--subscriber target)))
    (if (and frame (frame-live-p frame)
             (eq iphone-frame-speech--command-owner (frame-parameter frame 'emacsvox-phone-speaker)))
        (with-selected-frame frame (funcall original target))
      (funcall original target))))

(defun iphone-frame-speech--packet (owner kind id &optional text)
  (pcase kind
    ("permission" (cl-pushnew id (process-get owner 'iphone-requests) :test #'equal))
    ("resolved" (process-put owner 'iphone-requests (delete id (process-get owner 'iphone-requests)))))
  (process-send-string owner
                       (concat "iphone_event " (json-encode
                                               `((type . ,kind) (id . ,id) (text . ,text))) "\n")))

(defun iphone-frame-speech--announce (original facts occasion icon text &optional policy)
  ;; Preserve Agent Shell's request bookkeeping and its own spoken wording.
  (if (and iphone-frame-speech--request-id (eq policy 'urgent)
           (memq 'agent-permission-requested (plist-get facts :events)))
      (when-let* ((owner (iphone-frame-speech--subscriber)) ((process-live-p owner)))
        (iphone-frame-speech--packet owner "permission" iphone-frame-speech--request-id text))
    (funcall original facts occasion icon text policy)))

(defun iphone-frame-speech--sync (frame owner)
  (process-put owner 'iphone-synced t)
  (when-let* ((buffer (frame-parameter frame 'emacsvox-conversation))
              ((buffer-live-p buffer)))
    (with-current-buffer buffer
      (when (and (eq frame iphone-frame-speech--subscriber)
                 emacsvox-agent-shell-speak-permissions)
        (dolist (entry (reverse (copy-sequence (map-elt (agent-shell--state) :tool-calls))))
          (when-let* ((request (map-elt (cdr entry) :permission-request-id)))
            (let ((data `((:request-id . ,request) (:tool-call-id . ,(car entry))
                          (:tool-call . ,(cdr entry)))))
              (iphone-frame-speech--packet
               owner "permission" (iphone-frame-speech--permission-id request)
               (emacsvox-agent-shell--permission-announcement (list (cons :data data)))))))))))

(defun iphone-frame-speech-control (id action serial)
  "Stop, resynchronise or detach the phone frame owning ID."
  (when-let* ((frame (seq-find (lambda (f) (equal (frame-parameter f 'emacsvox-phone-id) id))
                               (frame-list)))
              (owner (frame-parameter frame 'emacsvox-phone-speaker)))
    (pcase action
      ('detach (iphone-frame-speech--close-terminal frame))
      ((guard (not (process-live-p owner))) nil)
      ('sync (iphone-frame-speech--sync frame owner))
      ('stop
       (let ((tts-speaker-process owner) (tts-notify-process owner)
             (iphone-frame-speech--bound t))
         (tts-stop t))
       ;; Acknowledge on the same stream, after the cancelled generation.
       (iphone-frame-speech--packet owner "reset-done" serial))))
  t)

(defconst iphone-frame-speech--entries
  '(emacsvox-aural-call-with-submission emacsvox-icon tts-letter
    tts-dispatch tts-tone tts-silence tts-notify-apply tts--protocol-set-punctuations))

(defconst iphone-frame-speech--deferred-entries
  '(emacsvox-agent-shell--deliver-pending-blocks emacsvox-agent-shell--deliver-out-of-turn-pending))

(defun iphone-frame-speech--native-frame ()
  (when (and iphone-frame-speech--directory (not (display-graphic-p))
             (frame-parameter nil 'emacsvox-native-ssh))
    (let ((id (frame-parameter nil 'emacsvox-phone-id)))
      (iphone-frame-speech-attach id)
      (iphone-frame-speech--open-terminal-buffer iphone-frame-speech--entry-buffer)
      (iphone-frame-speech--packet (frame-parameter nil 'emacsvox-phone-speaker) "attached" id))))

(defun iphone-frame-speech-use-server (directory name)
  "Attach an opt-in relay in DIRECTORY to Agent Shell buffer NAME."
  (when iphone-frame-speech--directory (user-error "A phone relay is already attached"))
  (unless (and (process-live-p tts-speaker-process) (fboundp 'tts--retire-process)
               (fboundp 'emacsvox-aural-call-with-submission))
    (user-error "Start Emacsvox in this Emacs server first"))
  (when (omnivox-remote-enabled-p)
    (user-error "This trial requires the desktop's local speech backend"))
  (let ((buffer (get-buffer name)))
    (unless (and buffer (with-current-buffer buffer (derived-mode-p 'agent-shell-mode)))
      (user-error "Choose an existing Agent Shell conversation buffer"))
    (set-marker iphone-frame-speech--position nil)
    (setq iphone-frame-speech--directory directory iphone-frame-speech--entry-buffer buffer
          iphone-frame-speech--last-terminal nil))
  (iphone-frame-speech-enable)
  (add-hook 'server-after-make-frame-hook #'iphone-frame-speech--native-frame)
  (expand-file-name "emacsclient" invocation-directory))

(defun iphone-frame-speech-release-server (directory)
  "Release the relay that owns DIRECTORY and its phone workers."
  (when (equal directory iphone-frame-speech--directory)
    (remove-hook 'server-after-make-frame-hook #'iphone-frame-speech--native-frame)
    (dolist (frame (frame-list))
      (when (frame-parameter frame 'emacsvox-phone-speaker)
        (if (frame-parameter frame 'emacsvox-native-ssh)
            (iphone-frame-speech--close-terminal frame)
          (iphone-frame-speech--detach frame))))
    (remove-hook 'pre-command-hook #'iphone-frame-speech--pre-command)
    (remove-hook 'post-command-hook #'iphone-frame-speech--post-command)
    (remove-hook 'delete-frame-functions #'iphone-frame-speech--detach)
    (advice-remove 'command-execute #'iphone-frame-speech--command)
    (advice-remove 'set-minibuffer-message #'iphone-frame-speech--key-echo)
    (advice-remove 'agent-shell--emit-event #'iphone-frame-speech--event)
    (advice-remove 'emacsvox-agent-shell--session-focused-p #'iphone-frame-speech--focused)
    (advice-remove 'emacsvox-agent-shell--deliver-announcement #'iphone-frame-speech--announce)
    (advice-remove 'tts-set-rate #'iphone-frame-speech--set-rate)
    (advice-remove 'tts-stop #'iphone-frame-speech--stop)
    (dolist (entry iphone-frame-speech--deferred-entries)
      (advice-remove entry #'iphone-frame-speech--deferred))
    (dolist (entry iphone-frame-speech--entries)
      (advice-remove entry #'iphone-frame-speech--route))
    (set-marker iphone-frame-speech--position nil)
    (setq iphone-frame-speech--directory nil iphone-frame-speech--entry-buffer nil
          iphone-frame-speech--last-terminal nil
          iphone-frame-speech--hook-owner nil))
  t)

(defun iphone-frame-speech-enable ()
  "Enable frame routing in the isolated trial server."
  (add-hook 'pre-command-hook #'iphone-frame-speech--pre-command -100)
  (add-hook 'post-command-hook #'iphone-frame-speech--post-command 100)
  (add-hook 'delete-frame-functions #'iphone-frame-speech--detach)
  (advice-add 'tts-set-rate :around #'iphone-frame-speech--set-rate)
  (advice-add 'tts-stop :around #'iphone-frame-speech--stop)
  (dolist (entry iphone-frame-speech--deferred-entries)
    (advice-add entry :around #'iphone-frame-speech--deferred))
  (advice-add 'agent-shell--emit-event :around #'iphone-frame-speech--event)
  (advice-add 'emacsvox-agent-shell--session-focused-p :around #'iphone-frame-speech--focused)
  (advice-add 'emacsvox-agent-shell--deliver-announcement :around #'iphone-frame-speech--announce)
  (advice-add 'command-execute :around #'iphone-frame-speech--command)
  (advice-add 'set-minibuffer-message :around #'iphone-frame-speech--key-echo '((depth . -90)))
  (dolist (entry iphone-frame-speech--entries)
    (advice-add entry :around #'iphone-frame-speech--route)))

;;; frame-speech.el ends here
