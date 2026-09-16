;;; omnivox-espeak-variants-tests.el --- Bundled variant checks -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Native catalogue boundaries and non-destructive desired selection.
;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'omnivox-espeak-variants)

(defconst omnivox-espeak-variants-tests--catalogue
  "{\"schema_version\":1,\"bases\":[{\"id\":{\"engine_id\":\"espeak\",\"voice_id\":\"espeak:gmw/en-US\"},\"display_name\":\"English US\",\"language\":\"en-us\"}],\"variants\":[{\"id\":\"m1\",\"display_name\":\"Male one\"},{\"id\":\"f1\",\"display_name\":\"Female one\"}]}")

(ert-deftest omnivox-espeak-variants-keeps-disabled-choices-and-native-overrides ()
  (let ((process-environment (copy-sequence process-environment))
        (omnivox-espeak-variants '((t "espeak:gmw\\en-US" "m1") (nil "espeak:gmw\\en-US" "f1"))))
    (setenv "OMNIVOX_ESPEAK_VARIANTS" nil)
    (let* ((process-environment (omnivox-engine-settings--environment
                                (expand-file-name "omnivox" emacsvox-servers-directory)))
           (decoded (json-parse-string (getenv "EMACSVOX_LOCAL_ESPEAK_VARIANTS")
                                       :object-type 'plist :array-type 'list)))
      (should (equal (plist-get (car decoded) :base_voice_id) "espeak:gmw\\en-US"))
      (should (eq (plist-get (car decoded) :enabled) t))
      (should (eq (plist-get (cadr decoded) :enabled) :false)))
    (setenv "OMNIVOX_ESPEAK_VARIANTS" "[]")
    (let ((process-environment (omnivox-engine-settings--environment
                                (expand-file-name "omnivox" emacsvox-servers-directory))))
      (should-not (getenv "EMACSVOX_LOCAL_ESPEAK_VARIANTS"))
      (should (equal (getenv "OMNIVOX_ESPEAK_VARIANTS") "[]")))
    (should (= (length omnivox-espeak-variants) 2))))

(ert-deftest omnivox-espeak-variants-rejects-aliases-overflow-and-duplicate-choices ()
  (dolist (entries '(((t "en" "m1")) ((t "espeak:en" "1")) ((t "espeak:en" "../m1"))
                    ((t "espeak:en" "m1") (nil "espeak:en" "m1"))
                    ((t "espeak:en" "variant-name-too-long-for-the-native-buffer"))))
    (should-error (omnivox-engine-settings--variants-json entries) :type 'user-error)))

(ert-deftest omnivox-espeak-variants-discovery-keeps-launcher-diagnostics-out-of-json ()
  (skip-unless (and (not (eq system-type 'windows-nt)) (executable-find "sh")))
  (let* ((directory (make-temp-file "omnivox-variant-launcher-" t))
         (emacsvox-servers-directory (file-name-as-directory directory))
         (tts-program "omnivox")
         (process-environment (copy-sequence process-environment))
         (launcher (expand-file-name "omnivox" directory)))
    (unwind-protect
        (progn
          (with-temp-file launcher
            (insert "#!/bin/sh\n"
                    "printf '%s\\n' 'Omnivox check target: fixture' >&2\n"
                    "printf '%s\\n' '" omnivox-espeak-variants-tests--catalogue "'\n"))
          (set-file-modes launcher #o700)
          (with-temp-buffer
            (omnivox-espeak-variants-mode)
            (unwind-protect
                (progn
                  (omnivox-espeak-variants-refresh)
                  (let ((deadline (+ (float-time) 5)))
                    (while (and omnivox-espeak-variants--process
                                (< (float-time) deadline))
                      (accept-process-output nil 0.05)))
                  (should-not omnivox-espeak-variants--process)
                  (should (= (length tabulated-list-entries) 2))
                  (should (equal omnivox-espeak-variants--base "espeak:gmw/en-US")))
              (omnivox-espeak-variants--stop))))
      (delete-directory directory t))))

(ert-deftest omnivox-espeak-variants-toggle-never-saves-restarts-or-rewrites-palettes ()
  (let ((omnivox-espeak-variants nil) (process-environment (copy-sequence process-environment)))
    (setenv "OMNIVOX_ESPEAK_VARIANTS" nil)
    (with-temp-buffer
      (omnivox-espeak-variants-mode)
      (setq omnivox-espeak-variants--source (omnivox-espeak-variants--source-key))
      (omnivox-espeak-variants--accept omnivox-espeak-variants-tests--catalogue)
      (omnivox-espeak-variants--render)
      (goto-char (point-min))
      (cl-letf (((symbol-function 'omnivox-engine-settings--supported-p) (lambda () t))
                ((symbol-function 'emacsvox-aural-ui-announce-result) #'ignore)
                ((symbol-function 'tts-restart) (lambda () (ert-fail "unexpected restart")))
                ((symbol-function 'customize-save-variable) (lambda (&rest _) (ert-fail "unexpected save"))))
        (omnivox-espeak-variants-toggle)
        (should (equal omnivox-espeak-variants '((t "espeak:gmw/en-US" "m1"))))
        (should (equal (tabulated-list-get-id) "m1"))
        (omnivox-espeak-variants-toggle)
        (should (equal omnivox-espeak-variants '((nil "espeak:gmw/en-US" "m1"))))
        (should-error (omnivox-espeak-variants-preview) :type 'user-error)))))

(ert-deftest omnivox-espeak-variants-preview-requires-live-availability ()
  (let ((omnivox-espeak-variants '((t "espeak:gmw/en-US" "m1")))
        (inventory '(:status "available" :engines
                     ((:engine-id "espeak" :availability "available" :voices nil))))
        previews announcements)
    (cl-letf (((symbol-function 'tts-voice-inventory) (lambda () inventory))
              ((symbol-function 'tts-preview-voices)
               (lambda (entries callback)
                 (push entries previews)
                 (funcall callback '(:status completed))))
              ((symbol-function 'emacsvox-aural-ui-announce-result)
               (lambda (&rest args) (push args announcements))))
      (with-temp-buffer
        (omnivox-espeak-variants-mode)
        (omnivox-espeak-variants--accept omnivox-espeak-variants-tests--catalogue)
        (omnivox-espeak-variants--render)
        (should (equal (aref (tabulated-list-get-entry) 2) "Restart required"))
        (should-error (omnivox-espeak-variants-preview) :type 'user-error)
        (should-not previews)
        (setq inventory
              '(:status "available" :engines
                ((:engine-id "espeak" :availability "available" :voices
                  ((:voice-id "espeak:gmw/en-US+m1" :availability "available"))))))
        (omnivox-espeak-variants--inventory-changed)
        (should (equal (aref (tabulated-list-get-entry) 2) "Ready"))
        (omnivox-espeak-variants-preview)
        (should (= (length previews) 1))
        (should (equal (plist-get (plist-get (caar previews) :selector) :voice-id)
                       "espeak:gmw/en-US+m1"))
        (should (equal omnivox-espeak-variants--status "Male one sample: completed"))
        (should-not announcements)
        (setq inventory (plist-put inventory :stale t))
        (omnivox-espeak-variants--inventory-changed)
        (should (equal (aref (tabulated-list-get-entry) 2) "Waiting for inventory"))
        (should-error (omnivox-espeak-variants-preview) :type 'user-error)
        (should (= (length previews) 1))
        (setq inventory (plist-put inventory :stale nil)
              omnivox-espeak-variants nil)
        (omnivox-espeak-variants--render)
        (should (equal (aref (tabulated-list-get-entry) 2) "Disable pending"))
        (should-error (omnivox-espeak-variants-preview) :type 'user-error)))))

(ert-deftest omnivox-espeak-variants-graphical-refresh-keeps-focus-and-parent ()
  (skip-unless (display-graphic-p))
  (let ((parent (get-buffer-create " *variant-parent*"))
        (picker (get-buffer-create " *variant-picker*"))
        (draft (get-buffer-create " *variant-draft*"))
        (omnivox-espeak-variants nil))
    (unwind-protect
        (save-window-excursion
          (pop-to-buffer picker)
          (omnivox-espeak-variants-mode)
          (setq omnivox-espeak-variants--parent parent)
          (omnivox-espeak-variants--accept omnivox-espeak-variants-tests--catalogue)
          (omnivox-espeak-variants--render)
          (goto-char (point-min))
          (pop-to-buffer draft)
          (insert "Unsubmitted draft")
          (with-current-buffer picker (omnivox-espeak-variants--render))
          (should (eq (window-buffer (selected-window)) draft))
          (should (equal (buffer-string) "Unsubmitted draft"))
          (pop-to-buffer picker)
          (should (equal (tabulated-list-get-id) "m1"))
          (omnivox-espeak-variants-back)
          (should (eq (window-buffer (selected-window)) parent)))
      (mapc #'kill-buffer (list parent picker draft)))))

(ert-deftest omnivox-espeak-variants-graphical-navigation-speaks-every-row ()
  (skip-unless (display-graphic-p))
  (require 'emacsvox-tabulated-list)
  (let ((picker (get-buffer-create " *variant-navigation*"))
        (omnivox-espeak-variants nil)
        spoken)
    (unwind-protect
        (save-window-excursion
          (pop-to-buffer picker)
          (omnivox-espeak-variants-mode)
          (omnivox-espeak-variants--accept omnivox-espeak-variants-tests--catalogue)
          (omnivox-espeak-variants--render)
          (goto-char (point-min))
          (setq-local emacsvox-aural-ui-speech-function
                      (lambda (text) (push (substring-no-properties text) spoken)))
          (cl-letf (((symbol-function 'emacsvox-aural-submit)
                     (lambda (text &rest _) (push (substring-no-properties text) spoken))))
            (dolist (step '(("<down>" "f1" "Female one")
                            ("<up>" "m1" "Male one")
                            ("C-n" "f1" "Female one")
                            ("C-p" "m1" "Male one")))
              (setq spoken nil)
              (execute-kbd-macro (kbd (car step)))
              (should (equal (tabulated-list-get-id) (nth 1 step)))
              (should (equal (get-text-property (point) 'tabulated-list-column-name) "Variant"))
              (should (= (length spoken) 1))
              (should (string-match-p (nth 2 step) (car spoken)))))
          (execute-kbd-macro (kbd "<right>"))
          (should (= (emacsvox-aural-ui-tabulated-column-index) 1))
          (omnivox-espeak-variants--render)
          (should (= (emacsvox-aural-ui-tabulated-column-index) 1))
          (should (= (window-point) (point)))
          (execute-kbd-macro (kbd "<left>"))
          (setq spoken nil)
          (execute-kbd-macro (kbd "<up>"))
          (should (equal (tabulated-list-get-id) "m1"))
          (should (string-match-p "Top of" (car spoken))))
      (kill-buffer picker))))

(provide 'omnivox-espeak-variants-tests)
;;; omnivox-espeak-variants-tests.el ends here
