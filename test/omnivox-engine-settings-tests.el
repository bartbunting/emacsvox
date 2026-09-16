;;; omnivox-engine-settings-tests.el --- Engine startup checks -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Isolated settings, launchers and process lifecycle checks; no live speech.
;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'emacsvox-omnivox-components)

(defmacro omnivox-engine-settings-tests--isolated (&rest body)
  "Run BODY without inherited runtime settings."
  (declare (indent 0) (debug t))
  `(let ((process-environment (copy-sequence process-environment))
         (omnivox-piper-model-file nil) (omnivox-flite-voice-files nil)
         (omnivox-eloquence-runtime-file nil) (omnivox-dectalk-runtime-file nil)
         (tts-program "omnivox"))
     (dolist (provider omnivox-engine-settings--providers)
       (setenv (nth 2 provider) nil) (setenv (nth 3 provider) nil))
     (setenv "EMACSVOX_ECI_DLL" nil) (setenv "EMACSVOX_DECTALK_DLL" nil)
     (cl-letf (((symbol-function 'omnivox-remote-enabled-p) #'ignore)) ,@body)))

(ert-deftest omnivox-engine-settings-keeps-disabled-files-and-environment ()
  (omnivox-engine-settings-tests--isolated
    (let ((omnivox-flite-voice-files '((t "/voices/one.flitevox") (nil "/voices/two.flitevox"))))
      (let ((process-environment (omnivox-engine-settings--environment
                                  (expand-file-name "omnivox" emacsvox-servers-directory))))
        (should (equal (getenv "EMACSVOX_LOCAL_FLITE_VOICES") "/voices/one.flitevox")))
      (should-not (getenv "EMACSVOX_LOCAL_FLITE_VOICES"))
      (should (= (length omnivox-flite-voice-files) 2))
      (should (string-search "1 of 2" (omnivox-engine-settings--description "flite")))
      (setcar (car omnivox-flite-voice-files) nil)
      (let ((process-environment (omnivox-engine-settings--environment
                                  (expand-file-name "omnivox" emacsvox-servers-directory))))
        (should (equal (getenv "EMACSVOX_LOCAL_FLITE_VOICES") ""))))))

(ert-deftest omnivox-engine-settings-respects-native-and-legacy-overrides ()
  (omnivox-engine-settings-tests--isolated
    (let ((omnivox-eloquence-runtime-file "/voices/ECI.DLL")
          (omnivox-piper-model-file "/voices/model.onnx"))
      (setenv "OMNIVOX_PIPER_MODEL" "C:\\explicit\\model.onnx")
      (setenv "EMACSVOX_ECI_DLL" "C:\\explicit\\ECI.DLL")
      (let ((process-environment (omnivox-engine-settings--environment
                                  (expand-file-name "omnivox" emacsvox-servers-directory))))
        (should-not (getenv "EMACSVOX_LOCAL_PIPER_MODEL"))
        (should-not (getenv "EMACSVOX_LOCAL_ECI_DLL"))
        (should (equal (getenv "OMNIVOX_PIPER_MODEL") "C:\\explicit\\model.onnx")))
      (should (string-search "EMACSVOX_ECI_DLL" (omnivox-engine-settings--description "eloquence"))))))

(ert-deftest omnivox-engine-settings-rejects-ambiguous-and-remote-paths ()
  (should (equal (omnivox-engine-settings--path "~/voice.onnx" ".onnx")
                 (expand-file-name "~/voice.onnx")))
  (dolist (path '("relative.flitevox" "/ssh:host:/voice.flitevox" "/v;other.flitevox"
                  "/v:other.flitevox" "/v\nother.flitevox" "/v\"other.flitevox" "/v.onnx"))
    (should-error (omnivox-engine-settings--path path ".flitevox") :type 'user-error)))

(ert-deftest omnivox-engine-settings-local-launcher-converts-native-path-lists ()
  (omnivox-engine-settings-tests--isolated
    (let* ((root (make-temp-file "engine-settings-" t))
           (emacsvox-servers-directory root)
           (launcher (expand-file-name "omnivox" root))
           (program (expand-file-name "native.exe" root))
           (converter (expand-file-name "wslpath" root))
           (omnivox-piper-model-file "/voice files/model $(literal).onnx")
           (omnivox-flite-voice-files '((t "/voice files/one.flitevox") (nil "/missing.flitevox")
                                       (t "/voice files/two.flitevox"))))
      (unwind-protect
          (progn
            (copy-file (expand-file-name "servers/omnivox" emacsvox-directory) launcher)
            (with-temp-file program
              (insert "#!/bin/sh\nprintf 'MODEL=%s\\nVOICES=%s\\nWSLENV=%s\\n' \"${OMNIVOX_PIPER_MODEL-}\" \"${OMNIVOX_FLITE_VOICES-}\" \"${WSLENV-}\"\n"))
            (with-temp-file converter (insert "#!/bin/sh\nprintf 'W:%s\\n' \"$2\"\n"))
            (dolist (file (list launcher program converter)) (set-file-modes file #o700))
            (setenv "PATH" (concat root ":" (getenv "PATH")))
            (setenv "OMNIVOX_PROGRAM" program)
            (setenv "EMACSVOX_OMNIVOX_DIAGNOSTIC" "1")
            (setenv "EMACSVOX_OMNIVOX_PROBE_ONLY" nil)
            (setenv "WSLENV" "KEEP/p:OMNIVOX_PIPER_MODEL/p:OMNIVOX_FLITE_VOICES/pl")
            (let ((process-environment (omnivox-engine-settings--environment launcher)))
              (with-temp-buffer
                (should (zerop (call-process launcher nil t)))
                (should (string-search "MODEL=W:/voice files/model $(literal).onnx" (buffer-string)))
                (should (string-search "VOICES=W:/voice files/one.flitevox;W:/voice files/two.flitevox" (buffer-string)))
                (should (string-search "WSLENV=KEEP/p:OMNIVOX_PIPER_MODEL:OMNIVOX_FLITE_VOICES:" (buffer-string)))
                (should-not (string-search "missing.flitevox" (buffer-string))))
              (let ((native (expand-file-name "native" root)))
                (copy-file program native)
                (setenv "OMNIVOX_PROGRAM" native)
                (with-temp-buffer
                  (should (zerop (call-process launcher nil t)))
                  (should (string-search "MODEL=/voice files/model $(literal).onnx" (buffer-string)))
                  (should (string-search "VOICES=/voice files/one.flitevox:/voice files/two.flitevox" (buffer-string)))))))
        (delete-directory root t)))))

(ert-deftest omnivox-engine-settings-both-local-workers-receive-settings ()
  (require 'omnivox-library)
  (omnivox-engine-settings-tests--isolated
    (let ((omnivox-piper-model-file "/voices/model.onnx") processes received)
      (unwind-protect
          (cl-letf (((symbol-function 'make-process)
                     (lambda (&rest args)
                       (push (cons (plist-get args :name) (getenv "EMACSVOX_LOCAL_PIPER_MODEL")) received)
                       (make-pipe-process :name "engine-settings-fixture" :noquery t)))
                    ((symbol-function 'tts--initialize-output-volumes) #'ignore)
                    ((symbol-function 'omnivox-library--supported-p) (lambda (_) t)))
            (dolist (name '("Speaker" "Notify")) (push (tts-make-process name) processes))
            (should (equal (nreverse received) '(("Speaker" . "/voices/model.onnx") ("Notify" . "/voices/model.onnx")))))
        (dolist (process processes) (set-process-sentinel process #'ignore) (delete-process process))))))

(ert-deftest omnivox-engine-settings-remote-and-other-launchers-are-excluded ()
  (omnivox-engine-settings-tests--isolated
    (let ((omnivox-piper-model-file "/voices/model.onnx"))
      (should (eq process-environment (omnivox-engine-settings--environment "/other/omnivox")))
      (cl-letf (((symbol-function 'omnivox-remote-enabled-p) (lambda () t)))
        (should-not (omnivox-engine-settings--supported-p))
        (with-temp-buffer
          (emacsvox-omnivox-components-mode)
          (setq emacsvox-omnivox-components--records '((:id "piper" :name "Piper" :state "model-required" :size 0)))
          (let ((rows (emacsvox-omnivox-components--detail-rows "piper")))
            (should (assq 'settings-state rows))
            (should-not (assq 'settings rows))
            (should-not (assq 'check-settings rows))
            (should-not (assq 'restart-settings rows))))))))

(ert-deftest omnivox-engine-settings-configured-check-rejects-partial-discovery ()
  "Flite retaining SLT after a failed import does not make the check pass."
  (omnivox-engine-settings-tests--isolated
    (let* ((root (make-temp-file "engine-check-" t))
           (emacsvox-servers-directory root)
           (program (expand-file-name "omnivox" root))
           (manager (generate-new-buffer " *configured engine manager*"))
           (details (generate-new-buffer " *configured engine details*"))
           (output (generate-new-buffer " *configured engine result*"))
           (emacsvox-omnivox-components--output-buffer (buffer-name output))
           (omnivox-flite-voice-files '((t "/test.flitevox")))
           process)
      (unwind-protect
          (progn
            (with-temp-file program
              (insert "#!/bin/sh\nprintf 'Found 1 voices:\\ncmu_us_slt\\n'\necho 'Invalid external file' >&2\n"))
            (set-file-modes program #o700)
            (with-current-buffer manager
              (emacsvox-omnivox-components-mode)
              (setq emacsvox-omnivox-components--records
                    '((:id "flite" :name "Flite" :state "installed" :size 0))))
            (cl-letf (((symbol-function 'emacsvox-omnivox-components--request-records) #'ignore)
                      ((symbol-function 'emacsvox-omnivox-components--speak) #'ignore)
                      ((symbol-function 'emacsvox-omnivox-components--notice) #'ignore)
                      ((symbol-function 'tts-restart) (lambda () (ert-fail "Check restarted speech"))))
              (with-current-buffer details
                (emacsvox-omnivox-engine-details-mode)
                (setq emacsvox-omnivox-components--manager manager
                      emacsvox-omnivox-components--engine-id "flite")
                (emacsvox-omnivox-components--render-details)
                (should (emacsvox-aural-ui-goto-row 'startup-section))
                (emacsvox-omnivox-components--details-activate)
                (should (emacsvox-aural-ui-goto-row 'check-settings))
                (emacsvox-omnivox-components--details-activate))
              (with-current-buffer manager
                (setq process emacsvox-omnivox-components--process)
                (should (equal (cdr (process-command process)) '("--engine" "flite" "--list-voices")))
                (let ((deadline (+ (float-time) 3)))
                  (while (and emacsvox-omnivox-components--process (< (float-time) deadline))
                    (accept-process-output nil 0.05)))
                (should-not emacsvox-omnivox-components--process)
                (let ((result (alist-get "flite" emacsvox-omnivox-components--results nil nil #'equal)))
                  (should-not (plist-get result :success))
                  (should (string-search "Expected at least 2" (plist-get result :output)))
                  (should (string-search "Invalid external file" (plist-get result :output)))))
              ;; A stuck native check must also finish and retain its timeout.
              (with-temp-file program (insert "#!/bin/sh\nread -r unused\n"))
              (let ((schedule (symbol-function 'run-at-time)))
                (cl-letf (((symbol-function 'run-at-time)
                           (lambda (seconds repeat function &rest args)
                             (apply schedule (if (equal seconds 30) 0.05 seconds) repeat function args))))
                  (with-current-buffer details
                    (should (emacsvox-aural-ui-goto-row 'check-settings))
                    (emacsvox-omnivox-components--details-activate))
                  (with-current-buffer manager
                    (setq process emacsvox-omnivox-components--process)
                    (let ((deadline (+ (float-time) 3)))
                      (while (and emacsvox-omnivox-components--process (< (float-time) deadline))
                        (accept-process-output nil 0.05)))
                    (should-not (process-live-p process))
                    (should-not emacsvox-omnivox-components--process)
                    (let ((result (alist-get "flite" emacsvox-omnivox-components--results nil nil #'equal)))
                      (should-not (plist-get result :success))
                      (should (string-search "timed out" (plist-get result :output)))))))))
        (when (process-live-p process) (set-process-sentinel process #'ignore) (delete-process process))
        (dolist (buffer (list details manager output)) (when (buffer-live-p buffer) (kill-buffer buffer)))
        (delete-directory root t)))))

(ert-deftest omnivox-engine-settings-graphical-customize-returns-to-details ()
  "The settings action opens the right option and returns to its detail row."
  (skip-unless (display-graphic-p))
  (omnivox-engine-settings-tests--isolated
    (let ((manager (generate-new-buffer " *settings graphical manager*"))
          (details (generate-new-buffer " *settings graphical details*")) custom)
      (unwind-protect
          (save-window-excursion
            (cl-letf (((symbol-function 'tts-speak) #'ignore)
                      ((symbol-function 'emacsvox-icon) #'ignore)
                      ((symbol-function 'emacsvox-aural-ui-speak) #'ignore))
              (with-current-buffer manager
                (emacsvox-omnivox-components-mode)
                (setq emacsvox-omnivox-components--records
                      '((:id "flite" :name "Flite" :state "installed" :size 0))))
              (switch-to-buffer details)
              (emacsvox-omnivox-engine-details-mode)
              (setq emacsvox-omnivox-components--manager manager
                    emacsvox-omnivox-components--engine-id "flite")
              (emacsvox-omnivox-components--render-details)
              (should (emacsvox-aural-ui-goto-row 'startup-section))
              (emacsvox-omnivox-components--details-activate)
              (should (emacsvox-aural-ui-goto-row 'settings))
              (emacsvox-omnivox-components--details-activate)
              (setq custom (current-buffer))
              (redisplay t)
              (should (derived-mode-p 'Custom-mode))
              (should (string-search "Flite Voice Files" (buffer-string)))
              (call-interactively (key-binding (kbd "q")))
              (redisplay t)
              (should (eq (window-buffer (selected-window)) details))
              (should (eq (tabulated-list-get-id) 'settings))
              (should (pos-visible-in-window-p (point)))))
        (dolist (buffer (list custom details manager))
          (when (buffer-live-p buffer) (kill-buffer buffer)))))))

(ert-deftest omnivox-engine-settings-unset-files-do-not-deny-library-voices ()
  "No manual files does not imply that a worker has only its built-in voice."
  (omnivox-engine-settings-tests--isolated
    (dolist (id '("flite" "piper"))
      (should (equal (omnivox-engine-settings--description id)
                     "No manual file override; installed voice library or launcher defaults apply")))))

(provide 'omnivox-engine-settings-tests)
;;; omnivox-engine-settings-tests.el ends here
