;;; omnivox-engine-configuration-tests.el --- Local engine editor tests -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'omnivox-engine-configuration)

(defun omnivox-engine-configuration-test--review ()
  (list :path "/speech/config.json" :sha256 (make-string 64 ?a)
        :settings '(:routing (:fallback_engine_ids []) :engine_overrides nil)
        :engines (vector '(:engine_id "espeak" :in_process t :enabled t :program :null)
                         '(:engine_id "flite" :in_process :false :enabled t :program :null)
                         '(:engine_id "org.example.test" :in_process :false :enabled :false :program "/opt/helper"))
        :diagnostics []))

(defmacro omnivox-engine-configuration-test--buffer (&rest body)
  (declare (indent 0))
  `(cl-letf (((symbol-function 'emacsvox-aural-ui-speak) #'ignore))
     (with-temp-buffer
       (omnivox-engine-configuration-mode)
       (omnivox-engine-configuration--accept (omnivox-engine-configuration-test--review))
       (omnivox-engine-configuration--render 'enabled)
       (unwind-protect (progn ,@body)
         (setq kill-buffer-query-functions nil)))))

(ert-deftest omnivox-engine-configuration-retains-independent-engine-drafts ()
  (omnivox-engine-configuration-test--buffer
    (should-not (omnivox-engine-configuration--dirty-p))
    (omnivox-engine-configuration-edit)
    (should (omnivox-engine-configuration--dirty-p))
    (should (equal (aref (tabulated-list-get-entry) 1) "No"))
    (setq omnivox-engine-configuration--engine "org.example.test")
    (omnivox-engine-configuration--render 'enabled)
    (omnivox-engine-configuration-edit)
    (let ((overrides (gethash "engine_overrides" omnivox-engine-configuration--draft)))
      (should (eq :false (gethash "enabled" (gethash "espeak" overrides))))
      (should (eq t (gethash "enabled" (gethash "org.example.test" overrides)))))
    (should (equal (gethash "fallback_engine_ids" (gethash "routing" omnivox-engine-configuration--draft)) []))))

(ert-deftest omnivox-engine-configuration-conflict-retains-draft-and-running-speech ()
  (omnivox-engine-configuration-test--buffer
    (omnivox-engine-configuration-edit)
    (let ((draft (omnivox-engine-configuration--json omnivox-engine-configuration--draft)))
      (cl-letf (((symbol-function 'omnivox-engine-configuration--request)
                 (lambda (_) (error "file changed")))
                ((symbol-function 'tts-restart) (lambda () (ert-fail "Save restarted speech")))
                ((symbol-function 'omnivox-library-apply) (lambda (_) (ert-fail "Save applied settings"))))
        (should-error (omnivox-engine-configuration-save)))
      (should (equal draft (omnivox-engine-configuration--json omnivox-engine-configuration--draft)))
      (should (omnivox-engine-configuration--dirty-p)))))

(ert-deftest omnivox-engine-configuration-save-and-apply-are-separate ()
  (omnivox-engine-configuration-test--buffer
    (omnivox-engine-configuration-edit)
    (let ((review (omnivox-engine-configuration-test--review)) requests applied)
      (setq review (plist-put review :settings '(:routing (:fallback_engine_ids []) :engine_overrides (:espeak (:enabled :false)))))
      (cl-letf (((symbol-function 'omnivox-engine-configuration--request)
                 (lambda (command) (push command requests) review))
                ((symbol-function 'omnivox-library-apply) (lambda (providers) (setq applied providers))))
        (should-error (omnivox-engine-configuration-apply) :type 'user-error)
        (should-not applied)
        (omnivox-engine-configuration-save)
        (should-not applied)
        (should-not (omnivox-engine-configuration--dirty-p))
        (should (equal (plist-get (car requests) :command) "engine-settings-save"))
        (omnivox-engine-configuration-apply)
        (should (equal applied "both"))))))

(ert-deftest omnivox-engine-configuration-old-service-keeps-legacy-speech ()
  (let ((process (make-pipe-process :name "engine settings old host" :noquery t)) calls)
    (cl-letf (((symbol-function 'omnivox-library--service) (lambda () process))
              ((symbol-function 'omnivox-library--request)
               (lambda (_ command) (push command calls) '(:type "host"))))
      (should-error (omnivox-engine-configuration--request '(:command "engine-settings-review")) :type 'user-error)
      (should (equal calls '((:command "host"))))
      (should-not (process-live-p process)))))

(ert-deftest omnivox-engine-configuration-spoken-row-and-native-actions ()
  (omnivox-engine-configuration-test--buffer
    (let (spoken)
      (cl-letf (((symbol-function 'emacsvox-aural-ui-speak) (lambda (text) (setq spoken text))))
        (call-interactively (key-binding (kbd "SPC"))))
      (should (equal spoken "espeak. Enabled. Yes.")))
    (should (eq (key-binding (kbd "RET")) #'omnivox-engine-configuration-edit))
    (should (eq (key-binding (kbd "s")) #'omnivox-engine-configuration-save))
    (should (eq (key-binding (kbd "A")) #'omnivox-engine-configuration-apply))))


(ert-deftest omnivox-engine-configuration-cancelled-startup-edit-keeps-clean-draft ()
  (omnivox-engine-configuration-test--buffer
    (setq omnivox-engine-configuration--engine "flite"
          omnivox-engine-configuration--advanced t)
    (omnivox-engine-configuration--render 'startup_ms)
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) (signal 'quit nil))))
      (condition-case nil (omnivox-engine-configuration-edit) (quit nil)))
    (should-not (omnivox-engine-configuration--dirty-p))
    (omnivox-engine-configuration--render 'program)
    (should (equal (aref (tabulated-list-get-entry) 1) "Installed helper"))))

(ert-deftest omnivox-engine-configuration-native-service-round-trip ()
  (skip-unless (getenv "OMNIVOX_ENGINE_SETTINGS_TEST_PROGRAM"))
  (let ((root (make-temp-file "engine-settings-ui-" t))
        (process-environment (copy-sequence process-environment)))
    (unwind-protect
        (progn
          (setenv "OMNIVOX_CONFIG_DIR" root)
          (setenv "OMNIVOX_VOICE_ROOT" (expand-file-name "voices" root))
          (with-temp-file (expand-file-name "config.json" root)
            (insert "{\"schema\":3,\"speech\":{\"defaults\":{\"rate\":0.7}}}"))
          (cl-letf (((symbol-function 'omnivox-library--service)
                     (lambda (&optional _role)
                       (make-process :name "engine settings native test"
                                     :command (list (getenv "OMNIVOX_ENGINE_SETTINGS_TEST_PROGRAM") "--voice-library-service")
                                     :connection-type 'pipe :coding 'utf-8-unix :noquery t
                                     :filter #'omnivox-library--service-filter)))
                    ((symbol-function 'tts-restart) (lambda () (ert-fail "Unexpected restart"))))
            (omnivox-engine-configuration-test--buffer
              (omnivox-engine-configuration--accept
               (omnivox-engine-configuration--request '(:command "engine-settings-review")))
              (omnivox-engine-configuration--render 'enabled)
              (omnivox-engine-configuration-edit)
              (omnivox-engine-configuration-save)
              (should-not (omnivox-engine-configuration--dirty-p))
              (should (eq :false (gethash "enabled" (gethash "espeak" (gethash "engine_overrides" omnivox-engine-configuration--draft))))))
            (with-temp-buffer
              (insert-file-contents (expand-file-name "config.json" root))
              (let ((data (json-parse-buffer :object-type 'plist)))
                (should (= (plist-get (plist-get (plist-get data :speech) :defaults) :rate) 0.7))))))
      (delete-directory root t))))

(ert-deftest omnivox-engine-configuration-graphical-navigation-retains-draft ()
  (skip-unless (display-graphic-p))
  (omnivox-engine-configuration-test--buffer
    (save-window-excursion
      (switch-to-buffer (current-buffer))
      (omnivox-engine-configuration-edit)
      (setq omnivox-engine-configuration--engine "flite")
      (omnivox-engine-configuration--render 'program)
      (emacsvox-aural-ui-goto-tabulated-column 1)
      (redisplay t)
      (should (pos-visible-in-window-p (point) (selected-window)))
      (should (eq (tabulated-list-get-id) 'program))
      (should (= (emacsvox-aural-ui-tabulated-column-index) 1))
      (should (omnivox-engine-configuration--dirty-p))
      (should (eq (key-binding (kbd "RET")) #'omnivox-engine-configuration-edit)))))


(ert-deftest omnivox-engine-configuration-displays-actual-worker-inventory ()
  (let ((process (make-pipe-process :name "settings inventory" :noquery t))
        (omnivox-engine-configuration--engine "espeak"))
    (unwind-protect
        (progn
          (process-put process 'omnivox--control-inventory
                       '(:engines ((:id "espeak" :availability (:status "available")))))
          (should (equal "Last reported: available" (omnivox-engine-configuration--live-state process)))
          (delete-process process)
          (should (equal "No current worker inventory" (omnivox-engine-configuration--live-state process))))
      (when (process-live-p process) (delete-process process)))))

(provide 'omnivox-engine-configuration-tests)
;;; omnivox-engine-configuration-tests.el ends here
