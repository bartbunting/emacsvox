;;; wire-voices.el --- Voices on the connected iPhone -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Code:
(require 'tabulated-list)
(require 'json)
(require 'seq)
(defvar iphone-frame-speech--settings nil)
(defvar iphone-frame-speech--settings-file
  (locate-user-emacs-file "iphone-omnivox.json"))
(defvar-local iphone-voices--main nil)

(defun iphone-voices--id-p (s)
  (and (stringp s) (> (length s) 0) (<= (string-bytes s) 4096)
       (not (string-match-p "[[:cntrl:]]" s))))

(defun iphone-voices--load ()
  (setq iphone-frame-speech--settings
        (when (file-readable-p iphone-frame-speech--settings-file)
          (with-temp-buffer
            (insert-file-contents iphone-frame-speech--settings-file)
            (json-parse-buffer :object-type 'plist :array-type 'list :null-object nil)))))

(defun iphone-voices--save (settings)
  (let* ((target iphone-frame-speech--settings-file)
         (dir (file-name-directory target)))
    (make-directory dir t)
    (let ((tmp (make-temp-file (expand-file-name ".iphone-omnivox-" dir))))
      (unwind-protect
          (progn
            (with-temp-file tmp
              (insert (json-serialize (plist-put (copy-sequence settings) :roles
                                                 (vconcat (plist-get settings :roles))))))
            (rename-file tmp target t)
            (setq iphone-frame-speech--settings settings))
        (when (file-exists-p tmp) (delete-file tmp))))))

(defun iphone-voices--registration (original process)
  (let ((content (funcall original process)))
    (if (not (process-get process 'iphone-wire)) content
      (let* ((copy (copy-tree content t))
             (base (plist-get iphone-frame-speech--settings :reading))
             (roles (plist-get iphone-frame-speech--settings :roles))
             (exact (lambda (id) (list :kind "exact" :engine_id "ios" :voice_id id))))
        (seq-doseq (definition (plist-get copy :definitions))
          (let* ((role (seq-find (lambda (r) (equal (plist-get r :role) (plist-get definition :id))) roles))
                 (ids (seq-uniq (seq-filter #'iphone-voices--id-p (list (plist-get role :voice) base)))))
            (when ids
              (setf (plist-get definition :preferences)
                    (vconcat (mapcar exact ids) (plist-get definition :preferences))))))
        (when (iphone-voices--id-p base)
          (setf (plist-get (plist-get copy :fallback_policy) :global_default) (funcall exact base)))
        copy))))

(defconst iphone-voices--parameters
  '((:pitch "Pitch" "tts_set_pitch_multiplier" 0.5 2.0 1.0)
    (:rate "Reading rate (100 is normal)" "tts_set_speech_rate" 1 200 150)
    (:character "Character rate multiplier" "tts_set_character_scale" 0.1 4.0 1.0)
    (:voice "Speech volume" "tts_set_voice_volume" 0.0 1.0 1.0)
    (:tone "Tone volume" "tts_set_tone_volume" 0.0 1.0 1.0)
    (:sound "Earcon volume" "tts_set_sound_volume" 0.0 1.0 1.0)))

(defun iphone-voices--restore (worker)
  (let ((id (plist-get iphone-frame-speech--settings :reading)))
    (when (iphone-voices--id-p id)
      (process-send-string worker (format "tts_set_voice {%s}\n" id))))
  (pcase-dolist (`(,key ,_ ,command ,low ,high ,_) iphone-voices--parameters)
    (let ((value (plist-get iphone-frame-speech--settings key)))
      (when (and (numberp value) (<= low value high))
        (process-send-string worker (format "%s %s\n" command value)))))
  (let* ((saved (plist-get iphone-frame-speech--settings :rate))
         (rate (if (and (numberp saved) (<= 1 saved 200)) saved 150)))
    (process-put worker 'iphone-speech-rate rate)
    (process-send-string worker (format "tts_set_speech_rate %s\n" rate))))

(defun iphone-voices--owner ()
  (let ((main (frame-parameter nil 'emacsvox-phone-speaker)))
    (unless (and (processp main) (process-live-p main) (process-get main 'iphone-notify))
      (user-error "Connect the Omnivox phone workers first"))
    main))

(defun iphone-voices--rows (main)
  (let ((inventory (process-get main omnivox--control-inventory-property)))
    (cl-loop for engine in (plist-get inventory :engines) append
             (cl-loop for row in (plist-get engine :voices)
                      for id = (plist-get (plist-get row :id) :voice_id)
                      collect (list id (vector (plist-get row :display_name) (or (plist-get row :language) "")
                                               (plist-get row :quality) id))))))

(defun iphone-voices--draw (main)
  (setq tabulated-list-entries (iphone-voices--rows main))
  (tabulated-list-print t))

(defun iphone-voices-refresh ()
  "Ask both phone workers for the current installed voices."
  (interactive)
  (let* ((main (iphone-voices--owner)) (buffer (current-buffer)))
    (dolist (worker (list main (process-get main 'iphone-notify)))
      (omnivox--send-control-request
       worker '(:type "inventory")
       (lambda (process result)
         (omnivox--handle-inventory-response process result t)
         (when (and (eq main process) (buffer-live-p buffer))
           (with-current-buffer buffer
             (when (eq iphone-voices--main main) (iphone-voices--draw main)))))))))

(defun iphone-voices--selected ()
  (or (and (eq (iphone-voices--owner) iphone-voices--main) (tabulated-list-get-id))
      (user-error "Select an installed phone voice")))

(defun iphone-voices-preview ()
  "Speak a sample using the selected iOS identifier."
  (interactive)
  (let ((voice (iphone-voices--selected)))
    (omnivox--send-control-request
     iphone-voices--main
     (list :type "preview" :selector (list :kind "exact" :engine_id "ios" :voice_id voice)
           :text "The lighthouse keeper climbed the stairs to light the lamp.")
     (lambda (worker result)
       (when (and (process-live-p worker) (not (member (plist-get result :status) '("completed" "cancelled"))))
         (let ((iphone-frame-speech--command-owner worker))
           (iphone-frame-speech--route #'tts-speak "Phone voice preview failed"))))
     25)))

(defun iphone-voices--apply (voice &optional role)
  (let* ((main (iphone-voices--owner))
         (workers (list main (process-get main 'iphone-notify)))
         (settings (copy-tree iphone-frame-speech--settings))
         (roles (plist-get settings :roles)))
    (when role
      (setq roles (cons (list :role role :voice voice)
                        (seq-remove (lambda (r) (equal (plist-get r :role) role)) roles))))
    (iphone-voices--save (if role (plist-put settings :roles roles) (plist-put settings :reading voice)))
    (dolist (worker workers) (iphone-voices--restore worker))
    ;; Each acknowledgement is correlated to this exact registration and worker.
    (let ((remaining 2) failed)
      (dolist (worker workers)
        (let* ((content (omnivox--process-logical-registry-content worker))
               (generation (cl-incf omnivox--logical-registry-generation)))
          (omnivox--send-control-request
           worker (omnivox--registration-request generation content)
           (lambda (process response)
             (unless (omnivox--accept-registration-response process response generation content) (setq failed t))
             (when (and (= (cl-decf remaining) 0) (process-live-p main))
               (let ((iphone-frame-speech--command-owner main))
                 (iphone-frame-speech--route #'tts-speak
                  (if failed "Phone voice saved. Application unconfirmed." "Phone voice applied.")))))))))))

(defun iphone-voices-apply ()
  "Use the selected voice for ordinary reading on the phone."
  (interactive)
  (iphone-voices--apply (iphone-voices--selected)))

(defun iphone-voices-role ()
  "Use the selected voice for one named Emacsvox role on the phone."
  (interactive)
  (let* ((voice (iphone-voices--selected))
         (ids (mapcar (lambda (s) (format "%s" s)) (omnivox--logical-voice-ids)))
         (role (completing-read "Emacsvox voice role: " ids nil t)))
    (iphone-voices--apply voice role)))

(defun iphone-voices-adjust ()
  "Adjust reading rate, character scale, pitch or an audio volume on both phone workers."
  (interactive)
  (let* ((main (iphone-voices--owner))
         (label (completing-read "Phone parameter: " (mapcar #'cadr iphone-voices--parameters) nil t))
         (spec (seq-find (lambda (s) (equal (cadr s) label)) iphone-voices--parameters))
         (key (car spec))
         (value (read-number (format "%s from %s to %s: " label (nth 3 spec) (nth 4 spec))
                             (or (plist-get iphone-frame-speech--settings key) (nth 5 spec)))))
    (unless (<= (nth 3 spec) value (nth 4 spec)) (user-error "Value outside the supported range"))
    (iphone-voices--save (plist-put (copy-sequence iphone-frame-speech--settings) key value))
    (dolist (worker (list main (process-get main 'iphone-notify))) (iphone-voices--restore worker))
    (message "%s %s" label value)))

(define-derived-mode iphone-voices-mode tabulated-list-mode "iPhone Voices"
  "Browse installed iPhone voices. p previews, Return applies, r assigns a role and v adjusts speech."
  (setq tabulated-list-format [("Voice" 28 t) ("Language" 10 t) ("Quality" 12 t) ("Identifier" 40 t)])
  (tabulated-list-init-header))

(dolist (binding '(("p" . iphone-voices-preview) ("RET" . iphone-voices-apply)
                   ("r" . iphone-voices-role) ("v" . iphone-voices-adjust)
                   ("g" . iphone-voices-refresh) ("R" . iphone-voices-refresh)))
  (keymap-set iphone-voices-mode-map (car binding) (cdr binding)))

(defun iphone-voices--workbench (original &rest args)
  (let ((main (frame-parameter nil 'emacsvox-phone-speaker)))
    (if (not (and (processp main) (process-get main 'iphone-wire))) (apply original args)
      (pop-to-buffer-same-window (get-buffer-create "*iPhone Voices*"))
      (iphone-voices-mode)
      (setq iphone-voices--main main)
      (iphone-voices--draw main)
      (iphone-voices-refresh)
      (message "iPhone voices. p previews, Return applies, r assigns a role, v adjusts speech."))))

(provide 'iphone-wire-voices)
;;; wire-voices.el ends here
