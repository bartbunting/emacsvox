;;; frame-speech.el --- Route foreground commands in the shared-frame trial -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Code:
(require 'cl-lib)
(require 'json)
(require 'browse-url)
(require 'emacsvox-frame-speech (expand-file-name "../../lisp/speech/emacsvox-frame-speech"
                                                  (file-name-directory load-file-name)))
(require 'emacsvox-agent-shell-frames (expand-file-name "../../lisp/integrations/emacsvox-agent-shell-frames"
                                                       (file-name-directory load-file-name)))
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
(defvar iphone-frame-speech--bundled-paths nil)
(defvar tts-speaker-process)
(defvar tts-notify-process)
(defvar emacsvox-play-program)
(defvar emacsvox-sounds-dir)
(defvar server-socket-dir)
(defvar-local iphone-frame-speech--buffer-id nil)
(defvar iphone-frame-speech--next-buffer-id 0)
(defvar iphone-frame-speech--receiver-stop nil)
(defconst iphone-frame-speech--program
  (expand-file-name "phone-backend" (file-name-directory load-file-name)))
(defconst iphone-frame-speech--accent-file "packs/accent/open-object.ogg")
(defconst iphone-frame-speech--visual-line-file
  (expand-file-name "assets/visual-line.wav" (file-name-directory load-file-name)))
(defvar iphone-frame-speech--directory nil)
(defvar iphone-frame-speech--entry-buffer nil)
(defvar iphone-frame-speech--last-terminal nil)
(defvar iphone-frame-speech--position (make-marker))
(defun iphone-frame-speech--command-worker ()
  (let ((endpoint (emacsvox-frame-speech--origin)))
    (when (emacsvox-frame-speech--valid-p endpoint)
      (let ((main (emacsvox-frame-speech--endpoint-main endpoint)))
        (and (process-get main 'iphone-connection) main)))))

(defun iphone-frame-speech--worker-call (main function &rest args)
  (apply #'emacsvox-frame-speech-call (or (process-get main 'iphone-endpoint) 'disconnected)
         function args))

(defun iphone-frame-speech--post-command ()
  (when (frame-parameter nil 'emacsvox-phone-speaker)
    (when-let* ((shell (cond ((derived-mode-p 'agent-shell-mode) (current-buffer))
                             ((derived-mode-p 'agent-shell-viewport-view-mode 'agent-shell-viewport-edit-mode)
                              (emacsvox-agent-shell--viewport-session-buffer (current-buffer))))))
      (iphone-frame-speech-subscribe shell))
    (iphone-frame-speech--remember (selected-frame))))

(defun iphone-frame-speech--stop (original &optional all)
  (interactive (list 'iphone-explicit-stop))
  (let ((owner (iphone-frame-speech--command-worker)))
    (funcall original (cond ((eq all 'iphone-explicit-stop) t)
                            ((and owner (process-get owner 'iphone-notify)
                                  (not iphone-frame-speech--receiver-stop)) nil)
                            (t all)))
    (when (and owner (eq all 'iphone-explicit-stop))
      (iphone-frame-speech--packet owner "stop-all" 0))))

(defun iphone-frame-speech--wire-filter (process output)
  (let ((owner (or (process-get process 'iphone-main) process)))
    (iphone-frame-speech--worker-call owner #'omnivox--control-process-filter process output)
    (when (and (process-live-p owner) (not (process-get owner 'iphone-routing-ready))
               (cl-every (lambda (worker)
                           (and (process-get worker omnivox--control-capabilities-property)
                                (or (not (omnivox--process-supports-p worker "engine_inventory"))
                                    (process-get worker omnivox--control-inventory-property))
                                (or (not (omnivox--process-supports-p worker "logical_voice_registration"))
                                    (member (plist-get (process-get worker omnivox--control-registration-property) :type)
                                            '("logical_voices_registered" "logical_voices_registered_v2"
                                              "logical_voices_registered_v3")))))
                         (list owner (process-get owner 'iphone-notify))))
      (process-put owner 'iphone-routing-ready t)
      (iphone-voices--ready owner)
      (iphone-frame-speech--packet owner "routing-ready" (process-get owner 'iphone-connection)))))

(defun iphone-frame-speech--wire-resource (file)
  (unless (and iphone-frame-speech--digests iphone-frame-speech--bundled-paths)
    (setq iphone-frame-speech--digests (make-hash-table :test #'equal)
          iphone-frame-speech--bundled-paths (make-hash-table :test #'equal))
    (with-temp-buffer
      (insert-file-contents iphone-frame-speech--assets)
      (while (re-search-forward "^\\([a-f0-9]\\{64\\}\\)  \\(.+\\)$" nil t)
        (let ((path (match-string 2)) (digest (match-string 1)))
          (puthash path digest iphone-frame-speech--digests)
          (puthash digest path iphone-frame-speech--bundled-paths)))))
  (let* ((relative (if (equal file iphone-frame-speech--visual-line-file) "visual-line.wav"
                     (file-relative-name file emacsvox-sounds-dir)))
         (expected (gethash relative iphone-frame-speech--digests))
         (size (and (file-regular-p file) (file-attribute-size (file-attributes file))))
         (digest (and size (<= size (* 16 1024 1024)) (emacsvox-aural--file-digest file)))
         (alias (gethash digest iphone-frame-speech--bundled-paths)))
    (cond ((and expected (equal expected digest)) (concat "omnivox-icon:" relative))
          (alias (concat "omnivox-icon:" alias))
          (digest (concat "omnivox-icon:personal/" digest))
          (t "omnivox-icon:unavailable"))))

(defun iphone-frame-speech--resource (original file)
  ;; Different installations can resolve the same bundled cue to different
  ;; absolute paths. Use Omnivox's bundled-resource ID on the phone stream.
  (if (and emacsvox-frame-speech--active (process-get tts-speaker-process 'iphone-wire))
      (or (iphone-frame-speech--wire-resource file) file)
    (if (and emacsvox-frame-speech--active (process-get tts-speaker-process 'iphone-connection)
           (equal file (expand-file-name iphone-frame-speech--accent-file emacsvox-sounds-dir))
           (equal (ignore-errors (emacsvox-aural--file-digest file))
                  "d5ee5d380a01d530f9a09336161b75e6426cb3604843967612d370b0fc547e96"))
      (concat "omnivox-icon:" iphone-frame-speech--accent-file)
    (funcall original file))))

(defun iphone-frame-speech--chime (original &optional tempo speed)
  ;; The visual-line indicator normally starts a local SoX process.
  (let ((owner (iphone-frame-speech--command-worker)))
    (if (and owner (equal tempo 2) (equal speed 2))
        (when (bound-and-true-p sox-gen-p)
          (iphone-frame-speech--worker-call owner #'emacsvox-sounds-play-concrete-cue
                                      iphone-frame-speech--visual-line-file "visual-line"))
      (funcall original tempo speed))))

(defun iphone-frame-speech--set-rate (original rate &optional prefix)
  (let ((owner (iphone-frame-speech--command-worker)))
    (when (and owner (process-get owner 'iphone-wire) (numberp rate) (<= 1 rate 200))
      (iphone-voices--save (plist-put (copy-sequence iphone-frame-speech--settings) :rate rate)))
    (funcall original rate prefix)))

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
              (process-put main 'iphone-notify notify)
              (process-put notify 'iphone-main main))
            (process-put main 'iphone-connection id)
            (process-put main 'iphone-endpoint
                         (emacsvox-frame-speech-attach
                          (selected-frame) main notify tts-program
                          (or (plist-get iphone-frame-speech--settings :rate) 150)))
            (when notify
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
          (when (and main (eq (process-get main 'iphone-endpoint) (emacsvox-frame-speech-endpoint)))
            (emacsvox-frame-speech-detach))
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
    (emacsvox-frame-speech-detach frame)
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
        (emacsvox-agent-shell-unsubscribe-frame old frame))
      (when (or iphone-frame-speech--directory (frame-parameter frame 'emacsvox-native-ssh))
        (setq iphone-frame-speech--entry-buffer buffer))
      (set-frame-parameter frame 'emacsvox-conversation buffer)
      (emacsvox-agent-shell-subscribe-frame buffer frame)
      (when (process-get owner 'iphone-synced)
        (iphone-frame-speech-control (frame-parameter frame 'emacsvox-phone-id) 'sync 0)))))

(defun iphone-frame-speech--permission-id (key)
  (unless iphone-frame-speech--buffer-id
    (setq iphone-frame-speech--buffer-id (cl-incf iphone-frame-speech--next-buffer-id)))
  (format "%d:%S" iphone-frame-speech--buffer-id key))

(defun iphone-frame-speech--packet (owner kind id &optional text)
  (pcase kind
    ("permission" (cl-pushnew id (process-get owner 'iphone-requests) :test #'equal))
    ("resolved" (process-put owner 'iphone-requests (delete id (process-get owner 'iphone-requests)))))
  (process-send-string owner
                       (concat "iphone_event " (json-encode
                                               `((type . ,kind) (id . ,id) (text . ,text)
                                                 ,@(when (equal kind "attached") '((browseUrl . t)))
                                                 ,@(when (and (equal kind "attached")
                                                              (terminal-parameter nil 'emacsvox-phone-hyper))
                                                     '((keyTiming . t))))) "\n")))

(defun iphone-frame-speech--permission (frame key text)
  (when-let* ((owner (frame-parameter frame 'emacsvox-phone-speaker))
              ((process-live-p owner)))
    (iphone-frame-speech--packet owner (if text "permission" "resolved")
                               (iphone-frame-speech--permission-id key) text)
    t))

(defun iphone-frame-speech--sync (frame owner)
  (process-put owner 'iphone-synced t)
  (when-let* ((buffer (frame-parameter frame 'emacsvox-conversation))
              ((buffer-live-p buffer)))
    (with-current-buffer buffer
      (when (and (assq frame (emacsvox-agent-shell--subscribers))
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
      ('browser-ready (process-put owner 'iphone-web-browser t))
      ('sync (iphone-frame-speech--sync frame owner))
      ((or 'trace-saved 'trace-failed)
       (with-selected-frame frame
         (let ((emacsvox-frame-speech--command-owner (process-get owner 'iphone-endpoint)))
           (emacsvox-aural-submit-notification
            (if (eq action 'trace-saved) "Speech trace saved in WSL."
              "WSL could not save the speech trace.")
            :delivery-policy 'ordered :dont-log t))))
      ('stop
       (let ((iphone-frame-speech--receiver-stop t))
         (iphone-frame-speech--worker-call owner #'tts-stop t))
       ;; Acknowledge on the same stream, after the cancelled generation.
       (when-let* ((notify (process-get owner 'iphone-notify)))
         (iphone-frame-speech--packet notify "reset-done" serial))
       (iphone-frame-speech--packet owner "reset-done" serial))))
  t)

(defun iphone-frame-speech--web-link-p (url)
  "Recognise a web URL opened by a command on a browser-capable phone frame."
  (when-let* ((owner (iphone-frame-speech--command-worker)))
    (and (process-get owner 'iphone-web-browser)
         (string-match-p "\\`https?://" (downcase url)))))

(defun iphone-frame-speech--browse-url (url &rest _args)
  "Ask the phone that issued the command to open URL."
  (when (or (> (length url) 8192) (string-match-p "[[:cntrl:]]" url))
    (user-error "The phone cannot open this web link"))
  (when-let* ((owner (iphone-frame-speech--command-worker)))
    (iphone-frame-speech--packet owner "open-url" (process-get owner 'iphone-connection) url)))

(function-put 'iphone-frame-speech--browse-url 'browse-url-browser-kind 'external)

(defun iphone-frame-speech--timing-key (serial)
  "Return the fixed diagnostic sample numbered SERIAL through this phone."
  (when-let* (((frame-parameter nil 'emacsvox-native-ssh))
              (owner (frame-parameter nil 'emacsvox-phone-speaker))
              ((process-live-p owner)))
    (iphone-frame-speech--worker-call
     owner
     (lambda ()
       (tts--protocol-queue-text (format "timing sample %d" serial))
       (tts--protocol-dispatch))))
  [])

(defvar iphone-frame-speech--hyper-map nil)

(defun iphone-frame-speech--install-function-keys (map)
  "Decode the phone's explicit F1 through F12 modifiers in MAP.
Terminfo can name Shift+F6 as F18, which has a separate Emacs binding."
  (dolist (bits (append (number-sequence 1 7) (number-sequence 16 23)))
    (let ((mods (append (when (/= 0 (logand bits 1)) '(shift))
                        (when (/= 0 (logand bits 2)) '(meta))
                        (when (/= 0 (logand bits 4)) '(control))
                        (when (/= 0 (logand bits 16)) '(hyper)))))
      (dolist (key '((f1 . "\e[1;%dP") (f2 . "\e[1;%dQ") (f3 . "\e[1;%dR") (f4 . "\e[1;%dS")
                     (f5 . "\e[15;%d~") (f6 . "\e[17;%d~") (f7 . "\e[18;%d~") (f8 . "\e[19;%d~")
                     (f9 . "\e[20;%d~") (f10 . "\e[21;%d~") (f11 . "\e[23;%d~") (f12 . "\e[24;%d~")))
        (define-key map (format (cdr key) (1+ bits))
                    (vector (event-convert-list (append mods (list (car key))))))))))

;; Connected phone terminals share this map when the launcher reloads.
(when iphone-frame-speech--hyper-map
  (iphone-frame-speech--install-function-keys iphone-frame-speech--hyper-map))

(defun iphone-frame-speech--enable-hyper ()
  "Decode the phone keyboard's extended modifier sequences on its SSH terminal."
  (unless iphone-frame-speech--hyper-map
    (let ((map (make-sparse-keymap)))
      (iphone-frame-speech--install-function-keys map)
      (dolist (bits '(1 3 4 5 6 7))
        (let ((mods (append (when (/= 0 (logand bits 1)) '(shift))
                            (when (/= 0 (logand bits 2)) '(meta))
                            (when (/= 0 (logand bits 4)) '(control)))))
          (dolist (pair '((127 . backspace) (27 . escape)))
            (define-key map (format "\e[%d;%du" (car pair) (1+ bits))
                        (vector (event-convert-list (append mods (list (cdr pair)))))))))
      (dolist (code (number-sequence ?a ?z))
        (dolist (modifier '(6 8))
          (define-key map (format "\e[%d;%du" code modifier)
                      (vector (event-convert-list
                               (append '(control shift) (when (= modifier 8) '(meta))
                                       (list code)))))))
      (dotimes (bits 8)
        (let ((modifier (+ 17 bits))
              (mods (append '(hyper)
                            (when (/= 0 (logand bits 1)) '(shift))
                            (when (/= 0 (logand bits 2)) '(meta))
                            (when (/= 0 (logand bits 4)) '(control)))))
          (dolist (code (append (number-sequence 32 126) '(9 13 27 127)))
            (define-key map (format "\e[%d;%du" code modifier)
                        (vector (event-convert-list (append mods (list code))))))
          (dolist (pair '((up . "1;%dA") (down . "1;%dB") (right . "1;%dC") (left . "1;%dD")
                          (home . "1;%dH") (end . "1;%dF") (insert . "2;%d~") (delete . "3;%d~")
                          (prior . "5;%d~") (next . "6;%d~")))
            (define-key map (concat "\e[" (format (cdr pair) modifier))
                        (vector (event-convert-list (append mods (list (car pair)))))))))
      ;; A diagnostic key carries a trial number without entering the buffer.
      (dotimes (index 255)
        (let ((serial (1+ index)))
          (define-key map (format "\e[57343;%du" serial)
                      (lambda (_prompt) (iphone-frame-speech--timing-key serial)))))
      (setq iphone-frame-speech--hyper-map map)))
  (unless (terminal-parameter nil 'emacsvox-phone-hyper)
    (setq input-decode-map (make-composed-keymap iphone-frame-speech--hyper-map input-decode-map))
    (set-terminal-parameter nil 'emacsvox-phone-hyper t)))

(defun iphone-frame-speech--native-frame ()
  (when (and iphone-frame-speech--directory (not (display-graphic-p))
             (frame-parameter nil 'emacsvox-native-ssh))
    (let ((id (frame-parameter nil 'emacsvox-phone-id)))
      (iphone-frame-speech--enable-hyper)
      (iphone-frame-speech-attach id)
      (iphone-frame-speech--open-terminal-buffer iphone-frame-speech--entry-buffer)
      (iphone-frame-speech--packet (frame-parameter nil 'emacsvox-phone-speaker) "attached" id))))

(defun iphone-frame-speech-use-server (directory name)
  "Attach an opt-in relay in DIRECTORY to Agent Shell buffer NAME."
  (when iphone-frame-speech--directory (user-error "A phone relay is already attached"))
  (unless (and (process-live-p tts-speaker-process) (fboundp 'tts--retire-process)
               (fboundp 'emacsvox-aural-call-with-submission))
    (user-error "Start Emacsvox in this Emacs server first"))
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
    (remove-hook 'post-command-hook #'iphone-frame-speech--post-command)
    (setq browse-url-default-handlers
          (delete '(iphone-frame-speech--web-link-p . iphone-frame-speech--browse-url) browse-url-default-handlers))
    (remove-hook 'delete-frame-functions #'iphone-frame-speech--detach)
    (remove-hook 'emacsvox-agent-shell-frame-permission-functions #'iphone-frame-speech--permission)
    (advice-remove 'emacsvox-aural-voice-workbench #'iphone-voices--workbench)
    (advice-remove 'omnivox-list-voices #'iphone-voices--workbench)
    (advice-remove 'omnivox-select-voice #'iphone-voices--select)
    (advice-remove 'omnivox-refresh-voices #'iphone-voices--refresh-command)
    (advice-remove 'omnivox--process-logical-registry-content #'iphone-voices--registration)
    (advice-remove 'tts-set-rate #'iphone-frame-speech--set-rate)
    (advice-remove 'tts-stop #'iphone-frame-speech--stop)
    (advice-remove 'omnivox-remote-resource #'iphone-frame-speech--resource)
    (advice-remove 'sox-chime #'iphone-frame-speech--chime)
    (set-marker iphone-frame-speech--position nil)
    (setq iphone-frame-speech--directory nil iphone-frame-speech--entry-buffer nil
          iphone-frame-speech--last-terminal nil))
  t)

(defun iphone-frame-speech-enable ()
  "Enable frame routing in the isolated trial server."
  (add-hook 'post-command-hook #'iphone-frame-speech--post-command 90)
  (add-to-list 'browse-url-default-handlers '(iphone-frame-speech--web-link-p . iphone-frame-speech--browse-url))
  (add-hook 'delete-frame-functions #'iphone-frame-speech--detach)
  (advice-add 'emacsvox-aural-voice-workbench :around #'iphone-voices--workbench)
  (advice-add 'omnivox-list-voices :around #'iphone-voices--workbench)
  (advice-add 'omnivox-select-voice :around #'iphone-voices--select)
  (advice-add 'omnivox-refresh-voices :around #'iphone-voices--refresh-command)
  (advice-add 'omnivox--process-logical-registry-content :around #'iphone-voices--registration)
  (advice-add 'tts-set-rate :around #'iphone-frame-speech--set-rate '((depth . -15)))
  (advice-add 'tts-stop :around #'iphone-frame-speech--stop '((depth . -15)))
  (advice-add 'omnivox-remote-resource :around #'iphone-frame-speech--resource)
  (advice-add 'sox-chime :around #'iphone-frame-speech--chime)
  (add-hook 'emacsvox-agent-shell-frame-permission-functions #'iphone-frame-speech--permission)
  t)

;;; frame-speech.el ends here
