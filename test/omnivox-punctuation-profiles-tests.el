;;; omnivox-punctuation-profiles-tests.el --- Negotiation and editor regressions -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'tts-speak)
(require 'omnivox-punctuation-tests)

(defmacro omnivox-profiles-tests--workers (&rest body)
  (declare (indent 0))
  `(let ((tts-speaker-process (make-pipe-process :name "profile main" :noquery t))
         (tts-notify-process (make-pipe-process :name "profile notify" :noquery t)))
     (unwind-protect
         (progn
           (dolist (process (list tts-speaker-process tts-notify-process))
             (omnivox-punctuation-profiles--receive
              process (list :type "punctuation_profiles_v1" :profiles
                            (vector (list :id "prose" :fallback "some" :sha256 (make-string 64 ?a))))))
           ,@body)
       (dolist (process (list tts-speaker-process tts-notify-process))
         (when (process-live-p process) (delete-process process))))))

(ert-deftest omnivox-profiles-require-matching-worker-content-and-fallback ()
  (omnivox-profiles-tests--workers
    (should (equal "tts_set_punctuation_profile prose\n"
                   (omnivox-punctuation-profiles--command '(profile "prose" some) tts-speaker-process)))
    (let ((tts-speaker-process tts-notify-process))
      (should (omnivox-punctuation-profiles--command '(profile "prose" some) tts-speaker-process)))
    (should-not (omnivox-punctuation-profiles--command '(profile "prose" all) tts-speaker-process))
    (process-put tts-notify-process 'omnivox-punctuation-profiles
                 (list (list :id "prose" :fallback "some" :sha256 (make-string 64 ?b))))
    (should-not (omnivox-punctuation-profiles--command '(profile "prose" some) tts-speaker-process))
    (let ((tts-speaker-process tts-notify-process))
      (should-not (omnivox-punctuation-profiles--command '(profile "prose" some) tts-speaker-process)))))

(ert-deftest omnivox-profiles-old-missing-and-dead-workers-use-saved-fallback ()
  (omnivox-profiles-tests--workers
    (let ((tts-punctuation-mode '(profile "prose" some)) packets)
      (process-put tts-notify-process 'omnivox-punctuation-profiles nil)
      (cl-letf (((symbol-function 'emacsvox-aural--delivery-send-typed)
                 (lambda (_ command &rest _) (push command packets))))
        (tts--protocol-sync))
      (should (string-prefix-p "tts_sync_state some " (car packets)))
      (should-not (seq-some (lambda (packet) (string-match-p "prose" packet)) packets))
      (should (string-match-p "fallback" (omnivox-punctuation-profiles--describe tts-punctuation-mode))))
    (delete-process tts-notify-process)
    (should-not (omnivox-punctuation-profiles--agreed))))

(ert-deftest omnivox-profiles-native-workers-negotiate-frozen-catalogues ()
  (skip-unless (getenv "OMNIVOX_PUNCTUATION_TEST_PROGRAM"))
  (require 'omnivox-voices)
  (let ((program (getenv "OMNIVOX_PUNCTUATION_TEST_PROGRAM"))
        (root (make-temp-file "punctuation-workers-" t))
        (process-environment
         (seq-remove (lambda (entry) (string-prefix-p "OMNIVOX_" entry))
                     process-environment))
        (tts-speaker-process nil) (tts-notify-process nil)
        processes)
    (unwind-protect
        (cl-labels
            ((save-profile (name)
               (with-temp-file (expand-file-name "config.json" root)
                 (insert (decode-coding-string
                          (json-serialize
                           (list :schema 4
                                 :routing '(:preferred_engine_ids ["espeak"]
                                            :disabled_engine_ids
                                            ["winrt" "macos" "piper" "rhvoice" "flite"
                                             "rutts" "tgspeechbox" "eloquence" "dectalk" "mbrola"])
                                 :speech
                                 (list :punctuation_profiles
                                       (list :prose
                                             (list :base "some" :overrides
                                                   (list :※ name))))))
                          'utf-8-unix))))
             (start-worker ()
               (let ((process (tts-queue--create
                               (lambda ()
                                 (make-process
                                  :name "punctuation worker test"
                                  :command (list program)
                                  :connection-type 'pipe :coding 'utf-8-unix :noquery t
                                  :filter #'omnivox--control-process-filter)) nil)))
                 (push process processes)
                 (omnivox--send-control-request
                  process '(:type "capabilities")
                  (lambda (owner response)
                    (omnivox-punctuation-profiles--negotiate owner response)))
                 process))
             (await-catalogue (process)
               (let ((deadline (+ (float-time) 10)))
                 (while (and (process-live-p process) (< (float-time) deadline)
                             (not (process-get process 'omnivox-punctuation-profiles)))
                   (accept-process-output nil 0.05)))
               (should (process-get process 'omnivox-punctuation-profiles))))
          (setenv "OMNIVOX_CONFIG_DIR" root)
          (setenv "OMNIVOX_VOICE_ROOT" (expand-file-name "voices" root))
          (setenv "OMNIVOX_AUDIO_OUTPUT" "null")
          (save-profile "reference mark")
          (setq tts-speaker-process (start-worker))
          (await-catalogue tts-speaker-process)
          (setq tts-notify-process (start-worker))
          (await-catalogue tts-notify-process)
          (should (omnivox-punctuation-profiles--command
                   '(profile "prose" some) tts-speaker-process))
          (let ((tts-speaker-process tts-notify-process))
            (should (omnivox-punctuation-profiles--command
                     '(profile "prose" some) tts-speaker-process)))
          ;; A replacement notification worker sees changed disk contents;
          ;; the existing main worker must retain its original catalogue.
          (save-profile "different mark")
          (setq tts-notify-process (start-worker))
          (await-catalogue tts-notify-process)
          (should-not (omnivox-punctuation-profiles--command
                       '(profile "prose" some) tts-speaker-process))
          (let ((tts-speaker-process tts-notify-process))
            (should-not (omnivox-punctuation-profiles--command
                         '(profile "prose" some) tts-speaker-process))))
      (dolist (process processes)
        (when (process-live-p process)
          (process-send-eof process)
          (let ((deadline (+ (float-time) 3)))
            (while (and (process-live-p process) (< (float-time) deadline))
              (accept-process-output process 0.05)))
          (when (process-live-p process) (delete-process process))))
      (delete-directory root t))))

(ert-deftest omnivox-profiles-sync-and-set-remain-valid-queue-and-frame-commands ()
  (omnivox-profiles-tests--workers
    (let (packets)
      (cl-letf (((symbol-function 'emacsvox-aural--delivery-send-typed)
                 (lambda (_ command effects &rest _)
                   (tts-queue--describe command effects)
                   (push command packets))))
        (tts--protocol-set-punctuations '(profile "prose" some)))
      (should (equal (car packets) "tts_set_punctuations some\ntts_set_punctuation_profile prose\nd\n"))
      (emacsvox-aural--validate-legacy-frame (car packets))
      (should-error (emacsvox-aural--validate-legacy-frame "tts_set_punctuation_profile bad name\nd\n")))))

(ert-deftest omnivox-profiles-mode-policy-and-explicit-level-override-round-trip ()
  (let ((tts-speaker-process nil) (tts-notify-process nil)
        (tts-punctuation-mode-policy-alist '((text-mode profile "prose" some))))
    (with-temp-buffer
      (text-mode)
      (tts-apply-punctuation-mode-policy)
      (should (equal tts-punctuation-mode '(profile "prose" some)))
      (tts-set-punctuations 'all)
      (should (eq tts-punctuation-mode 'all))
      (tts-reset-punctuation-mode)
      (should (equal tts-punctuation-mode '(profile "prose" some))))))

(ert-deftest omnivox-profiles-editor-inherits-drafts-and-removes-profiles-safely ()
  (omnivox-punctuation-tests--buffer
    (omnivox-punctuation--accept (append (omnivox-punctuation-tests--review) '(:profiles nil)))
    (omnivox-punctuation-new-profile "prose" "some")
    (should (omnivox-punctuation--dirty-p))
    (should (eq (omnivox-punctuation--value "’") :null))
    (omnivox-punctuation-level "some")
    (omnivox-punctuation--change "’" "Speak a name" "inherited")
    (omnivox-punctuation-level "prose")
    (should (equal (omnivox-punctuation--value "’") "inherited"))
    (omnivox-punctuation--change "’" "Speak a name" "profile only")
    (let (request)
      (cl-letf (((symbol-function 'omnivox-punctuation--request)
                 (lambda (command) (setq request command) (error "conflict"))))
        (should-error (omnivox-punctuation-save)))
      (should (string-match-p "profile only" (plist-get request :profiles_json)))
      (should-not (string-match-p "profile only" (plist-get request :punctuation_json))))
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
      (omnivox-punctuation-delete-profile))
    (should (equal omnivox-punctuation--levels '("none" "some" "all")))
    (should (equal (omnivox-punctuation--value "’") "inherited"))))

(ert-deftest omnivox-profiles-graphical-create-edit-and-switch ()
  (skip-unless (display-graphic-p))
  (omnivox-punctuation-tests--buffer
    (save-window-excursion
      (switch-to-buffer (current-buffer))
      (omnivox-punctuation--accept (append (omnivox-punctuation-tests--review) '(:profiles nil)))
      (omnivox-punctuation-new-profile "prose" "some")
      (omnivox-punctuation--change "’" "Speak a name" "quote")
      (emacsvox-aural-ui-goto-tabulated-column 1)
      (redisplay t)
      (should (equal (tabulated-list-get-id) "’"))
      (should (pos-visible-in-window-p (point) (selected-window)))
      (should (eq (key-binding (kbd "N")) #'omnivox-punctuation-new-profile))
      (omnivox-punctuation-level "all")
      (omnivox-punctuation-level "prose")
      (should (equal (omnivox-punctuation--value "’") "quote"))
      (should (omnivox-punctuation--dirty-p)))))

(provide 'omnivox-punctuation-profiles-tests)
;;; omnivox-punctuation-profiles-tests.el ends here
