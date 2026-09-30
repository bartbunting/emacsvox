;;; emacsvox-aural-doctor-tests.el --- Aural Doctor tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Verify installation diagnostics, safe repairs, and spoken navigation.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-keymap)
(require 'emacsvox-aural-doctor)

(ert-deftest emacsvox-aural-doctor-summarizes-severity ()
  "The spoken summary distinguishes failures from warnings."
  (let ((findings
         (list
          (emacsvox-aural-doctor--finding
           'one 'error "One" "bad" "detail")
          (emacsvox-aural-doctor--finding
           'two 'warning "Two" "old" "detail")
          (emacsvox-aural-doctor--finding
           'three 'ok "Three" "good" "detail"))))
    (should
     (equal
      (emacsvox-aural-doctor-summary findings)
      "1 problem and 1 warning"))))

(ert-deftest emacsvox-aural-doctor-detects-stale-byte-code ()
  "A newer source file is reported against its loaded byte-code."
  (let* ((directory (make-temp-file "emacsvox-doctor-stale-" t))
         (source (expand-file-name "doctor-fixture.el" directory))
         (compiled (concat source "c"))
         (function 'emacsvox-test--doctor-fixture))
    (unwind-protect
        (progn
          (with-temp-file source
            (insert
             "(defun emacsvox-test--doctor-fixture () 'loaded)\n"))
          (byte-compile-file source)
          (load compiled nil nil t)
          (set-file-times source (time-add (current-time) 10))
          (let ((finding
                 (emacsvox-aural-doctor--loaded-file-finding
                  'fixture function)))
            (should
             (eq
              (emacsvox-aural-doctor-finding-severity finding)
              'warning))
            (should
             (equal
              (emacsvox-aural-doctor-finding-status finding)
              "stale byte-code"))
            (should
             (equal
              (emacsvox-aural-doctor-finding-repair finding)
              (list 'emacsvox-aural-doctor-reload-source source)))))
      (when (fboundp function) (fmakunbound function))
      (delete-directory directory t))))

(ert-deftest emacsvox-aural-doctor-restores-documented-bindings ()
  "The safe binding repair restores the live prefix map."
  (let ((global-map (copy-keymap global-map))
        (emacsvox-keymap (copy-keymap emacsvox-keymap)))
    (define-key emacsvox-keymap (kbd "H") #'ignore)
    (define-key emacsvox-keymap (kbd "E") #'ignore)
    (global-set-key emacsvox-prefix emacsvox-keymap)
    (emacsvox-aural-doctor-restore-bindings)
    (should (eq (key-binding (kbd "C-e H")) 'emacsvox-aural))
    (should
     (eq
      (key-binding (kbd "C-e E"))
      'emacsvox-aural-explain-presentation))))

(ert-deftest emacsvox-aural-doctor-reports-face-mapping-conflicts ()
  "Doctor names each conflicting face, declaration, and effective voice."
  (let ((voice-setup-face-voice-table
         (make-hash-table :test #'eq))
        (voice-setup-face-voice-provenance-table
         (make-hash-table :test #'eq))
        (voice-setup--face-mapping-sequence 0))
    (voice-setup-set-voice-for-face
     'font-lock-warning-face 'voice-brighten 'warning-a)
    (voice-setup-set-voice-for-face
     'font-lock-warning-face 'voice-animate 'warning-b)
    (voice-setup-set-voice-for-face
     'font-lock-comment-face 'voice-monotone 'comment-a)
    (voice-setup-set-voice-for-face
     'font-lock-comment-face 'voice-monotone 'comment-b)
    (let ((finding (emacsvox-aural-doctor--face-mapping-finding)))
      (should
       (eq
        (emacsvox-aural-doctor-finding-severity finding)
        'warning))
      (should
       (equal
        (emacsvox-aural-doctor-finding-status finding)
        "1 conflict"))
      (should
       (equal
        (emacsvox-aural-doctor-finding-detail finding)
        (concat
         "font-lock-warning-face: effective voice-animate; "
         "declared warning-a=voice-brighten, "
         "warning-b=voice-animate"))))))

(ert-deftest emacsvox-aural-doctor-accepts-unambiguous-face-mappings ()
  "Repeated declarations of one voice are not reported as conflicts."
  (let ((voice-setup-face-voice-table
         (make-hash-table :test #'eq))
        (voice-setup-face-voice-provenance-table
         (make-hash-table :test #'eq))
        (voice-setup--face-mapping-sequence 0))
    (voice-setup-set-voice-for-face
     'font-lock-comment-face 'voice-monotone 'comment-a)
    (voice-setup-set-voice-for-face
     'font-lock-comment-face 'voice-monotone 'comment-b)
    (let ((finding (emacsvox-aural-doctor--face-mapping-finding)))
      (should
       (eq
        (emacsvox-aural-doctor-finding-severity finding)
        'ok))
      (should
       (equal
        (emacsvox-aural-doctor-finding-status finding)
        "no conflicts")))))

(ert-deftest emacsvox-aural-doctor-runs-without-starting-speech ()
  "A complete diagnostic pass only reports the speech-server state."
  (let* ((directory (make-temp-file "emacsvox-doctor-data-" t))
         (emacsvox-aural-schemes-file
          (expand-file-name "absent.el" directory))
         (tts-speaker-process nil)
         (findings (emacsvox-aural-doctor-run))
         (server
          (cl-find
           'speech-server findings
           :key #'emacsvox-aural-doctor-finding-id))
         (face-policy
          (cl-find
           'face-presentation findings
           :key #'emacsvox-aural-doctor-finding-id))
         (compatibility-voice
          (cl-find
           'compatibility-voice findings
           :key #'emacsvox-aural-doctor-finding-id))
         (face-mappings
          (cl-find
           'face-mapping-conflicts findings
           :key #'emacsvox-aural-doctor-finding-id))
         (cue-delivery
          (cl-find
           'cue-delivery findings
           :key #'emacsvox-aural-doctor-finding-id)))
    (unwind-protect
        (progn
          (should server)
          (should
           (equal
            (emacsvox-aural-doctor-finding-status server)
            "not running"))
          (should
           (cl-find
            'baseline findings
            :key #'emacsvox-aural-doctor-finding-id))
          (should face-policy)
          (should compatibility-voice)
          (should face-mappings)
          (should cue-delivery)
          (should
           (string-match-p
            "explicit :legacy-face"
            (emacsvox-aural-doctor-finding-detail face-policy)))
          (should
           (string-match-p
            "Voice Lock remains its compatibility implementation"
            (emacsvox-aural-doctor-finding-detail
             compatibility-voice))))
      (delete-directory directory t))))

(ert-deftest emacsvox-aural-doctor-exposes-linux-cue-lifecycle-limits ()
  "Doctor says that Linux cue playback overlaps and cannot be cancelled."
  (let ((tts-program "outloud")
        (process-environment (copy-sequence process-environment)))
    (setenv "EMACSVOX_PLAY" "/usr/bin/paplay")
    (let ((finding (emacsvox-aural-doctor--cue-delivery-finding)))
      (should
       (equal
        (emacsvox-aural-doctor-finding-status finding)
        "launch ordered; not cancellable"))
      (should
       (equal
        (emacsvox-aural-doctor-finding-detail finding)
        (concat
         "Server outloud launches /usr/bin/paplay before following speech; "
         "playback may overlap; speech stop does not cancel the cue; cue "
         "completion is unobserved"))))))

(ert-deftest emacsvox-aural-doctor-exposes-native-windows-cue-cancellation ()
  "Doctor distinguishes native Windows cue acknowledgement and cancellation."
  (let ((tts-program "/servers/windows-dtk")
        (process-environment (copy-sequence process-environment)))
    (setenv "EMACSVOX_PLAY" "/servers/windows-play")
    (let ((finding (emacsvox-aural-doctor--cue-delivery-finding)))
      (should
       (equal
        (emacsvox-aural-doctor-finding-status finding)
        "accepted; scoped cancellation"))
      (should
       (string-match-p
        "speech stop cancels cues for this stream"
        (emacsvox-aural-doctor-finding-detail finding))))))

(ert-deftest emacsvox-aural-doctor-manager-is-spoken-and-refreshable ()
  "The doctor uses the shared titled-cell and boundary navigation contract."
  (let ((emacsvox-aural-schemes-file
         (expand-file-name
          "missing.el" (make-temp-file "emacsvox-doctor-mode-" t)))
        spoken)
    (unwind-protect
        (with-temp-buffer
          (emacsvox-aural-doctor-mode)
          (should
           (eq
            (lookup-key emacsvox-aural-doctor-mode-map (kbd "h"))
            #'emacsvox-aural))
          (should
           (eq
            (key-binding (kbd "q"))
            #'emacsvox-aural-quit))
          (cl-letf
              (((symbol-function 'tts-speak)
                (lambda (text) (push text spoken)))
               ((symbol-function 'emacsvox-icon) #'ignore))
            (emacsvox-aural-doctor-refresh)
            (emacsvox-aural-doctor-speak-current-cell)
            (should (string-match-p "Check" (car spoken)))
            (goto-char (point-min))
            (emacsvox-aural-doctor-previous)
            (should (string-match-p "top of aural doctor" (car spoken)))))
      (delete-directory
       (file-name-directory emacsvox-aural-schemes-file) t))))

(ert-deftest emacsvox-aural-doctor-reports-recent-unknown-voice-fallback ()
  "Doctor names the requested voice and the palette used at the failure."
  (let ((emacsvox-aural--unknown-voice-diagnostics nil))
    (emacsvox-aural-compile-voice-style 'doctor-missing-voice 'acss-default)
    (let ((finding (emacsvox-aural-doctor--unknown-voice-finding)))
      (should (eq (emacsvox-aural-doctor-finding-severity finding) 'warning))
      (should (string-match-p "doctor-missing-voice in acss-default"
                              (emacsvox-aural-doctor-finding-detail finding)))
      (should (string-match-p "used ordinary speech"
                              (emacsvox-aural-doctor-finding-detail finding))))))


(ert-deftest emacsvox-aural-doctor-separates-workers-and-rejects-stale-evidence ()
  (let ((main (make-pipe-process :name "doctor main" :noquery t))
        (notify (make-pipe-process :name "doctor notify" :noquery t)))
    (unwind-protect
        (let ((tts-speaker-process main) (tts-notify-process notify))
          (process-put main 'omnivox--control-inventory
                       '(:preferred_engine_id "espeak" :engines
                         ((:id "espeak" :availability (:status "available")))) )
          (process-put notify 'omnivox--control-inventory
                       '(:engines ((:id "espeak" :availability (:status "unavailable")))))
          (process-put main 'omnivox-engine-activation "main-startup")
          (process-put notify 'omnivox-engine-activation "notify-startup")
          (cl-letf (((symbol-function 'tts-start) (lambda (&rest _) (ert-fail "Doctor started speech")))
                    ((symbol-function 'omnivox-refresh-voice-inventory) (lambda (&rest _) (ert-fail "Doctor sent probe"))))
            (should (eq 'info (emacsvox-aural-doctor-finding-severity
                              (nth 2 (emacsvox-aural-doctor--worker-findings "main" main)))))
            (should (eq 'warning (emacsvox-aural-doctor-finding-severity
                                 (nth 2 (emacsvox-aural-doctor--worker-findings "notification" notify)))))
            (should (equal "workers differ" (emacsvox-aural-doctor-finding-status
                                             (emacsvox-aural-doctor--configuration-finding))))
            (delete-process notify)
            (should (equal "not observed" (emacsvox-aural-doctor-finding-status
                                           (nth 2 (emacsvox-aural-doctor--worker-findings "notification" notify)))))
            (should (equal "not fully observed" (emacsvox-aural-doctor-finding-status
                                                 (emacsvox-aural-doctor--configuration-finding))))))
      (when (process-live-p main) (delete-process main))
      (when (process-live-p notify) (delete-process notify)))))

(ert-deftest emacsvox-aural-doctor-disabled-engine-is-not-a-failure ()
  (let ((process (make-pipe-process :name "doctor disabled" :noquery t)))
    (unwind-protect
        (progn
          (process-put process 'omnivox--control-inventory
                       '(:engines ((:id "flite" :availability (:status "unavailable")))
                         :engine_runtime ((:engine_id "flite" :disabled_by_policy t))))
          (let ((finding (nth 2 (emacsvox-aural-doctor--worker-findings "main" process))))
            (should (eq 'info (emacsvox-aural-doctor-finding-severity finding)))
            (should (string-match-p "disabled by policy" (emacsvox-aural-doctor-finding-detail finding)))))
      (delete-process process))))

(ert-deftest emacsvox-aural-doctor-copies-observations-without-log-contents ()
  (let ((emacsvox-aural-diagnostic-log-file "/unread/private.log")
        (emacsvox-aural-last-diagnostic-log-error nil)
        (kill-ring nil))
    (with-temp-buffer
      (emacsvox-aural-doctor-mode)
      (setq emacsvox-aural-doctor-findings (list (emacsvox-aural-doctor--speech-log-finding)))
      (cl-letf (((symbol-function 'emacsvox-aural-ui-speak) #'ignore)
                ((symbol-function 'insert-file-contents) (lambda (&rest _) (ert-fail "Doctor read log"))))
        (call-interactively (key-binding (kbd "y"))))
      (should (string-match-p "/unread/private.log" (car kill-ring)))
      (should (string-match-p "does not read or copy" (car kill-ring))))))

(provide 'emacsvox-aural-doctor-tests)
;;; emacsvox-aural-doctor-tests.el ends here
