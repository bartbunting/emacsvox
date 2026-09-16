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

(provide 'omnivox-espeak-variants-tests)
;;; omnivox-espeak-variants-tests.el ends here
