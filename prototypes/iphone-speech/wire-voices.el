;;; wire-voices.el --- Voices on the connected iPhone -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Code:
(require 'emacsvox-aural-ui)
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

(defun iphone-voices--project-choices (definition provenance voices native)
  "Give VOICES priority in a phone copy of DEFINITION and its client PROVENANCE."
  (let* ((remaining (copy-sequence (plist-get provenance :choices)))
         (used (mapcar (lambda (row) (plist-get row :id)) remaining))
         (wire (plist-get definition :choices))
         selected)
    (dolist (voice voices)
      (let ((match (seq-find
                    (lambda (row)
                      (let ((selector (plist-get row :selector)))
                        (and (eq (plist-get selector :kind) 'exact)
                             (equal (plist-get selector :engine-id) "ios")
                             (equal (plist-get selector :voice-id) voice))))
                    remaining)))
        (if match
            (progn (push match selected) (setq remaining (delq match remaining)))
          ;; New phone assignments inherit the shared style. Only the original
          ;; occurrence of a tuned choice owns its adjustments.
          (let* ((base (concat "iphone-" (secure-hash 'sha256 voice)))
                 (id base) (serial 0))
            (while (member id used) (setq id (format "%s-%d" base (cl-incf serial))))
            (push id used)
            (push (list :id id :selector (list :kind 'exact :scope 'local :engine-id "ios"
                                               :voice-id voice) :adjustments nil)
                  selected)))))
    (let ((rows (seq-take (append (nreverse selected) remaining) 32)))
      (setf (plist-get provenance :choices) rows
            (plist-get provenance :choice-source) 'local
            (plist-get definition :choices)
            (vconcat
             (mapcar (lambda (row)
                       (or (cl-find (plist-get row :id) wire :test #'equal
                                    :key (lambda (choice) (plist-get choice :id)))
                           (aref (if native (omnivox--native-choice-records-json (list row))
                                   (omnivox--choice-records-json (list row))) 0)))
                     rows))))))

(defun iphone-voices--registration (original process)
  (let ((content (funcall original process)))
    (if (not (process-get process 'iphone-wire)) content
      (let* ((copy (tts--dispatch-copy-data content))
             (base (plist-get iphone-frame-speech--settings :reading))
             (roles (plist-get iphone-frame-speech--settings :roles))
             (exact (lambda (id) (list :kind "exact" :engine_id "ios" :voice_id id))))
        (seq-doseq (row (plist-get copy :definitions))
          (let* ((mode (plist-get row :mode))
                 (definition (or (plist-get row :definition) row))
                 (id (plist-get definition :id))
                 (role (cl-find id roles :test #'equal :key (lambda (r) (plist-get r :role))))
                 (voices (seq-uniq (seq-filter #'iphone-voices--id-p (list (plist-get role :voice) base)))))
            (when voices
              (if (member mode '("layered" "engine_layered"))
                  (when-let* ((source (cl-find id (plist-get copy :choice-provenance)
                                              :test #'equal :key (lambda (r) (plist-get r :logical-id)))))
                    (iphone-voices--project-choices definition source voices (equal mode "engine_layered")))
                (let* ((first (mapcar exact voices))
                       (rest (seq-remove (lambda (s) (member s first))
                                         (plist-get definition :preferences))))
                  (setf (plist-get definition :preferences)
                        (vconcat (seq-take (append first rest) 32))))))))
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

(defun iphone-voices--parameter-value (worker spec)
  (let ((saved (plist-get iphone-frame-speech--settings (car spec)))
        (role (process-get worker tts--speech-process-role-property)))
    (if (and (numberp saved) (<= (nth 3 spec) saved (nth 4 spec))) saved
      (when-let* ((setting (seq-find (lambda (row)
                                      (and (eq (nth 1 row) role) (equal (nth 2 row) (nth 2 spec))))
                                    tts--output-volume-settings)))
        (/ (default-value (car setting)) 100.0)))))

(defun iphone-voices--restore (worker)
  (let ((id (plist-get iphone-frame-speech--settings :reading)))
    (when (iphone-voices--id-p id)
      (process-send-string worker (format "tts_set_voice {%s}\n" id))))
  (dolist (spec iphone-voices--parameters)
    (let ((value (iphone-voices--parameter-value worker spec)))
      (when (eq (car spec) :rate)
        (setq value (or value (nth 5 spec)))
        (process-put worker 'iphone-speech-rate value))
      (when value (process-send-string worker (format "%s %s\n" (nth 2 spec) value))))))

(defun iphone-voices--owner ()
  (let ((main (frame-parameter nil 'emacsvox-phone-speaker)))
    (unless (and (processp main) (process-live-p main) (process-get main 'iphone-wire)
                 (when-let* ((notify (process-get main 'iphone-notify))) (process-live-p notify)))
      (user-error "Connect with Use Omnivox on iPhone enabled to browse iPhone voices"))
    main))

(defun iphone-voices--rows (main)
  (let ((inventory (process-get main omnivox--control-inventory-property)))
    (cl-loop for engine in (plist-get inventory :engines) append
             (cl-loop for row in (plist-get engine :voices)
                      for id = (plist-get (plist-get row :id) :voice_id)
                      collect (list id (vector (plist-get row :display_name) (or (plist-get row :language) "")
                                               (plist-get row :quality) id))))))

(defun iphone-voices--draw (main &optional previous)
  (let* ((rows (iphone-voices--rows main))
         (selected (or previous (tabulated-list-get-id)))
         (reading (plist-get iphone-frame-speech--settings :reading)))
    (emacsvox-aural-ui-refresh-tabulated
     (lambda () (setq tabulated-list-entries rows))
     (cond ((assoc selected rows) selected) ((assoc reading rows) reading)))))

(defun iphone-voices--ready (main)
  (when-let* ((buffer (process-get main 'iphone-voice-buffer))
              ((buffer-live-p buffer)))
    (with-current-buffer buffer
      (when (eq iphone-voices--main main)
        (iphone-voices--draw main (process-get main 'iphone-voice-restore-row))
        (process-put main 'iphone-voice-restore-row nil)))))

(defun iphone-voices--resume (main conversation)
  "Restore this browser to MAIN when the phone reconnects."
  (setq emacsvox-aural-ui--return-function nil)
  (if (and (processp main) (process-get main 'iphone-wire))
      (progn
        (process-put main 'iphone-voice-restore-row (tabulated-list-get-id))
        (process-put main 'iphone-voice-buffer (current-buffer))
        (setq iphone-voices--main main tabulated-list-entries nil)
        (tabulated-list-print)
        (when (process-get main 'iphone-routing-ready) (iphone-voices--ready main)))
    (switch-to-buffer (if (buffer-live-p emacsvox-aural-ui-source-buffer)
                          emacsvox-aural-ui-source-buffer conversation))))

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
                             (or (iphone-voices--parameter-value main spec) (nth 5 spec)))))
    (unless (<= (nth 3 spec) value (nth 4 spec)) (user-error "Value outside the supported range"))
    (iphone-voices--save (plist-put (copy-sequence iphone-frame-speech--settings) key value))
    (dolist (worker (list main (process-get main 'iphone-notify))) (iphone-voices--restore worker))
    (message "%s %s" label value)))

(defun iphone-voices--row-description ()
  (when-let* ((row (tabulated-list-get-entry)))
    (string-join (list (aref row 0) (aref row 1) (aref row 2)) ", ")))

(defun iphone-voices--speak-row ()
  (when-let* ((description (iphone-voices--row-description))) (tts-speak description)))

(defun iphone-voices--choose (main prompt)
  (let* ((choices (cl-loop for (id row) in (iphone-voices--rows main)
                           collect (cons (string-join (append row nil) "  ") id))))
    (unless choices (user-error "Waiting for the iPhone voice inventory"))
    (cdr (assoc (emacsvox-aural-ui--read-choice prompt choices) choices))))

(defun iphone-voices-find ()
  "Find an installed phone voice by name, language or identifier."
  (interactive)
  (let ((id (iphone-voices--choose (iphone-voices--owner) "Find iPhone voice: ")))
    (emacsvox-aural-ui-goto-row id)
    (iphone-voices--speak-row)))

(defun iphone-voices-help ()
  "Show the iPhone voice browser keys."
  (interactive)
  (emacsvox-aural-ui-with-help-window
    (princ (concat "iPhone voices\n\n"
                   "Up and Down move by voice. Left and Right read columns. Space reads the row.\n"
                   "/ finds an installed voice. p or P auditions it. S stops a sample.\n"
                   "Return applies this reading voice to both phone workers. r assigns it to one named role.\n"
                   "v adjusts phone speech and audio levels. g refreshes the installed voices. q goes back.\n"))))

(define-derived-mode iphone-voices-mode emacsvox-aural-tabulated-mode "iPhone Voices"
  "Browse installed iPhone voices. p previews, Return applies, r assigns a role and v adjusts speech."
  (setq tabulated-list-format [("Voice" 28 t) ("Language" 10 t) ("Quality" 12 t) ("Identifier" 40 t)])
  (emacsvox-aural-ui-configure-tabulated "iPhone voices" #'iphone-voices--speak-row
                                         #'iphone-voices-refresh #'iphone-voices--speak-row)
  (tabulated-list-init-header))

(dolist (binding '(("p" . iphone-voices-preview) ("P" . iphone-voices-preview)
                   ("/" . iphone-voices-find) ("?" . iphone-voices-help) ("RET" . iphone-voices-apply)
                   ("r" . iphone-voices-role) ("v" . iphone-voices-adjust)
                   ("g" . iphone-voices-refresh) ("R" . iphone-voices-refresh)))
  (keymap-set iphone-voices-mode-map (car binding) (cdr binding)))

(defun iphone-voices--buffer (main)
  "Reuse MAIN's browser across visits. Another connected phone owns its own selection."
  (let ((buffer (process-get main 'iphone-voice-buffer)))
    (unless (buffer-live-p buffer)
      (setq buffer (get-buffer-create "*iPhone Voices*"))
      (with-current-buffer buffer
        (when (and (processp iphone-voices--main) (process-live-p iphone-voices--main)
                   (not (eq iphone-voices--main main)))
          (setq buffer (generate-new-buffer "*iPhone Voices*"))))
      (process-put main 'iphone-voice-buffer buffer))
    buffer))

(defun iphone-voices--workbench (original &rest args)
  (if (not (frame-parameter nil 'emacsvox-phone-id)) (apply original args)
    (let* ((main (iphone-voices--owner))
           (source (current-buffer))
           (buffer (iphone-voices--buffer main)))
      (with-current-buffer buffer
        (unless (and (derived-mode-p 'iphone-voices-mode) (eq iphone-voices--main main)
                     (eq emacsvox-aural-ui-row-speaker #'iphone-voices--speak-row))
          (iphone-voices-mode)
          ;; A reused buffer can still display the previous connection's row.
          (setq iphone-voices--main main tabulated-list-entries nil)
          (tabulated-list-print))
        (emacsvox-aural-ui-register-interface source)
        (setq emacsvox-aural-ui--return-function nil)
        (iphone-voices--draw main)
        (iphone-voices-refresh))
      (let ((display-buffer-overriding-action '((display-buffer-same-window))))
        (emacsvox-aural-ui--pop-to-buffer
         buffer (lambda ()
                  (tts-speak (format "iPhone voices. %d installed. %s. Up or Down moves, P previews."
                                     (length tabulated-list-entries)
                                     (or (iphone-voices--row-description) "Waiting for inventory"))))))
      buffer)))

(defun iphone-voices--select (original &rest args)
  (if (not (frame-parameter nil 'emacsvox-phone-id)) (apply original args)
    (iphone-voices--apply (iphone-voices--choose (iphone-voices--owner) "Use iPhone reading voice: "))))

(defun iphone-voices--refresh-command (original &rest args)
  (if (not (frame-parameter nil 'emacsvox-phone-id)) (apply original args)
    (iphone-voices-refresh)
    (mapcar (lambda (entry)
              (let ((row (cadr entry))) (list (car entry) (aref row 0) (aref row 1) (aref row 2))))
            (iphone-voices--rows (iphone-voices--owner)))))

(provide 'iphone-wire-voices)
;;; wire-voices.el ends here
