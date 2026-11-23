;;; frame-speech.el --- Route foreground commands in the shared-frame trial -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Code:
(require 'cl-lib)
(require 'json)
(defvar tts-program)
(defvar tts-speech-rate)
(defvar tts-handle-unicode)
(defvar omnivox-control-capabilities)
(defvar omnivox-engine-inventory)
(defvar omnivox-engine-inventory-time)
(defvar omnivox-logical-voice-registration)
(defvar omnivox-routing-policy-registration)
(defvar omnivox-control-last-error)
(load (expand-file-name "wire-voices.el" (file-name-directory load-file-name)) nil t t)
(defconst iphone-frame-speech--assets
  (expand-file-name "wire-icons.sha256" (file-name-directory load-file-name)))
(defvar iphone-frame-speech--digests nil)
(defvar tts-speaker-process)
(defvar tts-notify-process)
(defvar emacsvox-play-program)
(defvar emacsvox-sounds-dir)
(defvar server-socket-dir)
(defvar-local iphone-frame-speech--subscriber nil)
(defvar-local iphone-frame-speech--buffer-id nil)
(defvar iphone-frame-speech--next-buffer-id 0)
(defvar iphone-frame-speech--request-id nil)
(defconst iphone-frame-speech--program
  (expand-file-name "phone-backend" (file-name-directory load-file-name)))
(defconst iphone-frame-speech--accent-file "packs/accent/open-object.ogg")
(defconst iphone-frame-speech--visual-line-file
  (expand-file-name "assets/visual-line.wav" (file-name-directory load-file-name)))
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
    (iphone-frame-speech--route original
     (and all (or (eq all 'iphone-explicit-stop) (not (and (processp owner) (process-get owner 'iphone-notify))))))
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
            (emacsvox-play-program nil)
            (tts-program iphone-frame-speech--program)
            (tts-speaker-process owner)
            (tts-speech-rate (or (process-get owner 'iphone-speech-rate) 150))
            (tts-notify-process (or (process-get owner 'iphone-notify) owner)))
        (if (process-get owner 'iphone-notify)
            (iphone-frame-speech--with-inventory owner original args)
          (apply original args)))))))

(defun iphone-frame-speech--with-inventory (owner function args)
  ;; The desktop adapter keeps a foreground cache in addition to each
  ;; worker's properties. Bind that cache for the duration of a phone call.
  (let ((omnivox-control-capabilities (process-get owner omnivox--control-capabilities-property))
        (omnivox-engine-inventory (process-get owner omnivox--control-inventory-property))
        (omnivox-engine-inventory-time (process-get owner 'omnivox-inventory-received-at))
        (omnivox-logical-voice-registration (process-get owner omnivox--control-registration-property))
        (omnivox-routing-policy-registration (plist-get (process-get owner omnivox--control-inventory-property) :routing_policy))
        (omnivox-control-last-error nil)
        (tts-handle-unicode tts-handle-unicode))
    (apply function args)))

(defun iphone-frame-speech--wire-filter (process output)
  (let* ((owner (or (process-get process 'iphone-main) process))
         (tts-speaker-process owner)
         (tts-notify-process (process-get owner 'iphone-notify))
         (tts-program iphone-frame-speech--program)
         (iphone-frame-speech--command-owner owner))
    (iphone-frame-speech--with-inventory owner #'omnivox--control-process-filter (list process output))
    (when (and (process-live-p owner) (not (process-get owner 'iphone-routing-ready))
               (cl-every (lambda (worker)
                           (and (process-get worker omnivox--control-capabilities-property)
                                (or (not (omnivox--process-supports-p worker "engine_inventory"))
                                    (process-get worker omnivox--control-inventory-property))
                                (or (not (omnivox--process-supports-p worker "logical_voice_registration"))
                                    (process-get worker omnivox--control-registration-property))))
                         (list owner tts-notify-process)))
      (process-put owner 'iphone-routing-ready t)
      (iphone-voices--ready owner)
      (iphone-frame-speech--packet owner "routing-ready" (process-get owner 'iphone-connection)))))

(defun iphone-frame-speech--wire-resource (file)
  (unless iphone-frame-speech--digests
    (setq iphone-frame-speech--digests (make-hash-table :test #'equal))
    (with-temp-buffer
      (insert-file-contents iphone-frame-speech--assets)
      (while (re-search-forward "^\\([a-f0-9]\\{64\\}\\)  \\(.+\\)$" nil t)
        (puthash (match-string 2) (match-string 1) iphone-frame-speech--digests))))
  (let* ((relative (if (equal file iphone-frame-speech--visual-line-file) "visual-line.wav"
                     (file-relative-name file emacsvox-sounds-dir)))
         (expected (gethash relative iphone-frame-speech--digests))
         (size (and (file-regular-p file) (file-attribute-size (file-attributes file))))
         (digest (and size (<= size (* 16 1024 1024)) (emacsvox-aural--file-digest file))))
    (cond ((and expected (equal expected digest)) (concat "omnivox-icon:" relative))
          (digest (concat "omnivox-icon:personal/" digest))
          (t "omnivox-icon:unavailable"))))

(defun iphone-frame-speech--resource (original file)
  ;; Different installations can resolve the same bundled cue to different
  ;; absolute paths. Use Omnivox's bundled-resource ID on the phone stream.
  (if (and iphone-frame-speech--bound (process-get tts-speaker-process 'iphone-wire))
      (or (iphone-frame-speech--wire-resource file) file)
    (if (and iphone-frame-speech--bound
           (equal file (expand-file-name iphone-frame-speech--accent-file emacsvox-sounds-dir))
           (equal (ignore-errors (emacsvox-aural--file-digest file))
                  "d5ee5d380a01d530f9a09336161b75e6426cb3604843967612d370b0fc547e96"))
      (concat "omnivox-icon:" iphone-frame-speech--accent-file)
    (funcall original file))))

(defun iphone-frame-speech--chime (original &optional tempo speed)
  ;; The visual-line indicator normally starts a local SoX process.
  (let ((owner (or iphone-frame-speech--command-owner iphone-frame-speech--hook-owner)))
    (if (and owner (not (eq owner 'desktop)) (equal tempo 2) (equal speed 2))
        (when (bound-and-true-p sox-gen-p)
          (iphone-frame-speech--route #'emacsvox-sounds-play-concrete-cue
                                      iphone-frame-speech--visual-line-file "visual-line"))
      (funcall original tempo speed))))

(defun iphone-frame-speech--set-rate (original rate &optional prefix)
  (let ((owner (or iphone-frame-speech--command-owner iphone-frame-speech--hook-owner)))
    (if (and (processp owner) (process-live-p owner))
        (progn
          (when (and (process-get owner 'iphone-wire) (numberp rate) (<= 1 rate 200))
            (iphone-voices--save (plist-put (copy-sequence iphone-frame-speech--settings) :rate rate)))
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
    (let* ((process-environment (copy-sequence process-environment))
           (tts-program iphone-frame-speech--program)
           (notify-path (expand-file-name (concat id ".n") directory))
           main notify attached)
      (unwind-protect
          (progn
            (setenv "EMACSVOX_PHONE_SOCKET" (expand-file-name (concat id ".sock") directory))
            (setq main (tts-make-process "Phone frame"))
            (when (file-exists-p notify-path)
              (require 'omnivox-voices)
              (setenv "EMACSVOX_PHONE_SOCKET" notify-path)
              (setq notify (tts-make-process "Notify"))
              (iphone-voices--load)
              (process-put main 'iphone-connection id)
              (process-put main 'iphone-notify notify)
              (process-put notify 'iphone-main main)
              (dolist (worker (list main notify))
                (process-put worker 'iphone-wire t)
                (omnivox--install-control-filter worker)
                (set-process-filter worker #'iphone-frame-speech--wire-filter)
                (let ((tts-handle-unicode tts-handle-unicode))
                  (omnivox--negotiate-process worker))
                (iphone-voices--restore worker)))
            (set-frame-parameter nil 'emacsvox-phone-speaker main)
            (setq attached t))
        (unless attached
          (dolist (worker (list notify main))
            (when (processp worker) (tts--retire-process worker))))))))

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
      (progn
        (switch-to-buffer saved)
        (goto-char iphone-frame-speech--position)
        (when (derived-mode-p 'iphone-voices-mode)
          (iphone-voices--resume (frame-parameter nil 'emacsvox-phone-speaker) conversation))
        t)
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
    (when-let* ((notify (process-get owner 'iphone-notify))) (tts--retire-process notify))
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
         (event (plist-get args :event))
         (iphone-frame-speech--command-owner
          (or (and (eq event 'elicitation-response)
                   (bound-and-true-p emacsvox-agent-shell--question-command-active)
                   (or iphone-frame-speech--command-owner iphone-frame-speech--hook-owner))
              owner 'desktop))
         (data (plist-get args :data))
         (key (or (map-elt data :request-id) (map-elt data :tool-call-id)))
         (iphone-frame-speech--request-id
          (and owner key (eq event 'permission-request)
               (iphone-frame-speech--permission-id key))))
    (when (and owner (process-live-p owner) key (eq event 'permission-response))
      (iphone-frame-speech--packet owner "resolved" (iphone-frame-speech--permission-id key)))
    (apply original args)))

(defun iphone-frame-speech--steering-request (original &rest args)
  ;; A later ACP reply can arrive while another frame is typing. Keep the
  ;; originating worker, including its identity across a phone reconnect.
  (let ((owner (or iphone-frame-speech--command-owner iphone-frame-speech--hook-owner)))
    (when (and owner (equal (map-elt (plist-get args :request) :method) "_session/steering"))
      (setq args (copy-sequence args))
      (dolist (key '(:on-success :on-failure))
        (when-let* ((callback (plist-get args key)))
          (setq args (plist-put args key
                                (lambda (&rest response)
                                  (let ((iphone-frame-speech--command-owner owner))
                                    (apply callback response))))))))
    (apply original args)))

(defun iphone-frame-speech--deferred (original buffer &rest args)
  (when (buffer-live-p buffer)
    (let ((iphone-frame-speech--command-owner
           (or (with-current-buffer buffer (iphone-frame-speech--subscriber)) 'desktop)))
      (apply original buffer args))))

(defun iphone-frame-speech--phonetic (original request)
  ;; The character reader saves the source window and speaker together.
  ;; It validates both the request and its speaker again when the timer fires.
  (let* ((window (nth 1 request))
         (owner (and (window-live-p window)
                     (frame-parameter (window-frame window) 'emacsvox-phone-speaker)))
         (iphone-frame-speech--command-owner (or owner 'desktop)))
    (iphone-frame-speech--route original request)))

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
      ((or 'trace-saved 'trace-failed)
       (with-selected-frame frame
         (let ((iphone-frame-speech--command-owner owner))
           (emacsvox-aural-submit-notification
            (if (eq action 'trace-saved) "Speech trace saved in WSL."
              "WSL could not save the speech trace.")
            :delivery-policy 'ordered :dont-log t))))
      ('stop
       (let ((tts-speaker-process owner) (tts-notify-process (or (process-get owner 'iphone-notify) owner))
             (iphone-frame-speech--bound t))
         (tts-stop t))
       ;; Acknowledge on the same stream, after the cancelled generation.
       (when-let* ((notify (process-get owner 'iphone-notify)))
         (iphone-frame-speech--packet notify "reset-done" serial))
       (iphone-frame-speech--packet owner "reset-done" serial))))
  t)

(defconst iphone-frame-speech--entries
  '(emacsvox-aural-call-with-submission emacsvox-icon tts-letter
    tts-voice-inventory tts-refresh-voice-inventory tts-preview-voices
    tts-dispatch tts-tone tts-silence tts-notify-apply tts--protocol-set-punctuations
    emacsvox--delayed-phonetic-schedule))

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
    (advice-remove 'emacsvox--delayed-phonetic-announce #'iphone-frame-speech--phonetic)
    (advice-remove 'agent-shell--emit-event #'iphone-frame-speech--event)
    (advice-remove 'agent-shell--send-request #'iphone-frame-speech--steering-request)
    (advice-remove 'emacsvox-agent-shell--session-focused-p #'iphone-frame-speech--focused)
    (advice-remove 'emacsvox-agent-shell--deliver-announcement #'iphone-frame-speech--announce)
    (advice-remove 'emacsvox-aural-voice-workbench #'iphone-voices--workbench)
    (advice-remove 'omnivox-list-voices #'iphone-voices--workbench)
    (advice-remove 'omnivox-select-voice #'iphone-voices--select)
    (advice-remove 'omnivox-refresh-voices #'iphone-voices--refresh-command)
    (advice-remove 'omnivox--process-logical-registry-content #'iphone-voices--registration)
    (advice-remove 'tts-set-rate #'iphone-frame-speech--set-rate)
    (advice-remove 'tts-stop #'iphone-frame-speech--stop)
    (advice-remove 'omnivox-remote-resource #'iphone-frame-speech--resource)
    (advice-remove 'sox-chime #'iphone-frame-speech--chime)
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
  (advice-add 'emacsvox-aural-voice-workbench :around #'iphone-voices--workbench)
  (advice-add 'omnivox-list-voices :around #'iphone-voices--workbench)
  (advice-add 'omnivox-select-voice :around #'iphone-voices--select)
  (advice-add 'omnivox-refresh-voices :around #'iphone-voices--refresh-command)
  (advice-add 'omnivox--process-logical-registry-content :around #'iphone-voices--registration)
  (advice-add 'tts-set-rate :around #'iphone-frame-speech--set-rate)
  (advice-add 'tts-stop :around #'iphone-frame-speech--stop)
  (advice-add 'omnivox-remote-resource :around #'iphone-frame-speech--resource)
  (advice-add 'sox-chime :around #'iphone-frame-speech--chime)
  (dolist (entry iphone-frame-speech--deferred-entries)
    (advice-add entry :around #'iphone-frame-speech--deferred))
  (advice-add 'agent-shell--emit-event :around #'iphone-frame-speech--event)
  ;; Capture the success and failure callbacks after Emacsvox adds feedback.
  (advice-add 'agent-shell--send-request :around #'iphone-frame-speech--steering-request '((depth . 50)))
  (advice-add 'emacsvox-agent-shell--session-focused-p :around #'iphone-frame-speech--focused)
  (advice-add 'emacsvox-agent-shell--deliver-announcement :around #'iphone-frame-speech--announce)
  (advice-add 'command-execute :around #'iphone-frame-speech--command)
  (advice-add 'set-minibuffer-message :around #'iphone-frame-speech--key-echo '((depth . -90)))
  (advice-add 'emacsvox--delayed-phonetic-announce :around #'iphone-frame-speech--phonetic)
  (dolist (entry iphone-frame-speech--entries)
    (advice-add entry :around #'iphone-frame-speech--route)))

;;; frame-speech.el ends here
