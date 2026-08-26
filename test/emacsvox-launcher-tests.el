;;; emacsvox-launcher-tests.el --- Launcher smoke tests -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Verify that the tracked launcher resolves its own checkout and bundled
;; Windows speech runtime.

;;; Code:

(require 'ert)

(defconst emacsvox-launcher-tests--root
  (expand-file-name "../" (file-name-directory load-file-name)))

(defun emacsvox-launcher-tests--wsl-p ()
  "Return non-nil when these tests are running under WSL."
  (and
   (file-readable-p "/proc/version")
   (with-temp-buffer
     (insert-file-contents "/proc/version")
     (search-forward-regexp "microsoft" nil t))))

(defun emacsvox-launcher-tests--omnivox-log-files (directory)
  "Return sorted Omnivox log files immediately inside DIRECTORY."
  (directory-files directory t "\\`omnivox-.*\\.log\\'" t))

(ert-deftest emacsvox-launcher-log-filter-secures-and-bounds-history ()
  "The log filter should secure retained files and prune older diagnostics."
  (let* ((directory (make-temp-file "emacsvox-log-filter-" t))
         (filter
          (expand-file-name
           "servers/omnivox-log-filter" emacsvox-launcher-tests--root))
         (process-environment (copy-sequence process-environment))
         (base-time (encode-time 0 0 0 1 1 2026 t)))
    (unwind-protect
        (progn
          (dotimes (index 3)
            (let ((file
                   (expand-file-name
                    (format
                     "omnivox-20260101T00000%dZ-90000%d.log"
                     (1+ index) (1+ index))
                    directory)))
              (with-temp-file file
                (insert (make-string 40 (+ ?a index))))
              (set-file-modes file #o644)
              (set-file-times file (time-add base-time (1+ index)))))
          ;; A recycled PID belonging to this Emacs is not a live Omnivox log.
          (let ((recycled
                 (expand-file-name
                  (format
                   "omnivox-20200101T000000Z-%d.log" (emacs-pid))
                  directory)))
            (with-temp-file recycled
              (insert (make-string 40 ?z)))
            (set-file-modes recycled #o644)
            (set-file-times recycled (time-subtract base-time 1)))
          (let ((current
                 (expand-file-name
                  "omnivox-20260101T000004Z-900004-part000001.log"
                  directory)))
            (setenv "OMNIVOX_LOG_FILTER_DIRECTORY" directory)
            (setenv "OMNIVOX_LOG_RETAINED_FILES" "2")
            (setenv "OMNIVOX_LOG_RETAINED_BYTES" "100")
            (with-temp-buffer
              (insert "current diagnostic\n")
              (should
               (zerop
                (call-process-region
                 (point-min) (point-max) filter nil nil nil
                 "--stream"
                 (expand-file-name
                  "omnivox-20260101T000004Z-900004-part" directory)
                 "64"))))
            (let ((logs
                   (emacsvox-launcher-tests--omnivox-log-files directory)))
              (should (= (length logs) 2))
              (should (member current logs))
              (dolist (log logs)
                (should (= (file-modes log) #o600))))))
      (delete-directory directory t))))

(ert-deftest emacsvox-launcher-rotates-omnivox-stderr-by-size ()
  "The launcher should stream stderr into private bounded session parts."
  (let* ((directory (make-temp-file "emacsvox-launcher-logs-" t))
         (server-directory (expand-file-name "servers" directory))
         (runtime-directory
          (expand-file-name "omnivox-bin/current" server-directory))
         (log-directory (expand-file-name "logs" directory))
         (launcher (expand-file-name "omnivox" server-directory))
         (filter (expand-file-name "omnivox-log-filter" server-directory))
         (program (expand-file-name "omnivox.exe" runtime-directory))
         (process-environment (copy-sequence process-environment)))
    (unwind-protect
        (progn
          (make-directory runtime-directory t)
          (make-directory log-directory t)
          (set-file-modes log-directory #o755)
          (copy-file
           (expand-file-name
            "servers/omnivox" emacsvox-launcher-tests--root)
           launcher)
          (copy-file
           (expand-file-name
            "servers/omnivox-log-filter" emacsvox-launcher-tests--root)
           filter)
          (with-temp-file program
            (insert
             "#!/bin/sh\n"
             "printf 'protocol-ready\\n'\n"
             "index=0\n"
             "while [ \"$index\" -lt 30 ]; do\n"
             "  printf 'diagnostic-%02d %064d\\n' \"$index\" \"$index\" >&2\n"
             "  if [ \"$index\" -eq 0 ]; then sleep 0.5; fi\n"
             "  index=$((index + 1))\n"
             "done\n"))
          (dolist (file (list launcher filter program))
            (set-file-modes file #o700))
          (setenv "OMNIVOX_LOG_DIRECTORY" log-directory)
          (setenv "OMNIVOX_LOG_MAX_FILE_BYTES" "512")
          (setenv "OMNIVOX_LOG_RETAINED_FILES" "16")
          (setenv "OMNIVOX_LOG_RETAINED_BYTES" "8192")
          (let ((output (generate-new-buffer " *omnivox-launcher-output*"))
                process logs combined saw-live-diagnostic)
            (unwind-protect
                (progn
                  (setq process
                        (make-process
                         :name "omnivox-launcher-test"
                         :buffer output
                         :command (list launcher)
                         :connection-type 'pipe
                         :noquery t
                         :sentinel #'ignore))
                  (let ((deadline (+ (float-time) 0.4)))
                    (while
                        (and (< (float-time) deadline)
                             (not saw-live-diagnostic))
                      (setq logs
                            (emacsvox-launcher-tests--omnivox-log-files
                             log-directory))
                      (setq combined
                            (mapconcat
                             (lambda (file)
                               (with-temp-buffer
                                 (insert-file-contents file)
                                 (buffer-string)))
                             logs ""))
                      (setq saw-live-diagnostic
                            (string-search "diagnostic-00" combined))
                      (unless saw-live-diagnostic
                        (accept-process-output process 0.02))))
                  (should saw-live-diagnostic)
                  (should (process-live-p process))
                  (let ((deadline (+ (float-time) 2.0)))
                    (while (and (< (float-time) deadline)
                                (process-live-p process))
                      (accept-process-output process 0.02)))
                  (should (eq (process-status process) 'exit))
                  (should (zerop (process-exit-status process)))
                  (with-current-buffer output
                    (should (equal (buffer-string) "protocol-ready\n")))
                  (let ((deadline (+ (float-time) 2.0)))
                    (while
                        (progn
                          (setq logs
                                (emacsvox-launcher-tests--omnivox-log-files
                                 log-directory))
                          (setq combined
                                (mapconcat
                                 (lambda (file)
                                   (with-temp-buffer
                                     (insert-file-contents file)
                                     (buffer-string)))
                                 logs ""))
                          (and (< (float-time) deadline)
                               (not (string-search
                                     "diagnostic-29" combined))))
                      (sleep-for 0.02)))
                  (should (> (length logs) 1))
                  (should (string-search "session_start session_id=" combined))
                  (should (string-search "diagnostic-00" combined))
                  (should (string-search "diagnostic-29" combined))
                  ;; Let the orphaned writer observe EOF before removing its
                  ;; temporary log directory.
                  (sleep-for 0.05)
                  (should (= (file-modes log-directory) #o700))
                  (dolist (log logs)
                    (should
                     (<= (file-attribute-size (file-attributes log)) 512))
                    (should (= (file-modes log) #o600))))
              (when (and process (process-live-p process))
                (delete-process process))
              (kill-buffer output))))
      (delete-directory directory t))))

(ert-deftest emacsvox-launcher-falls-back-to-native-omnivox ()
  "Without a staged WSL runtime, the launcher uses Omnivox from PATH."
  (let* ((directory (make-temp-file "emacsvox-native-launcher-" t))
         (server-directory (expand-file-name "servers" directory))
         (binary-directory (expand-file-name "bin" directory))
         (launcher (expand-file-name "omnivox" server-directory))
         (filter (expand-file-name "omnivox-log-filter" server-directory))
         (program (expand-file-name "omnivox" binary-directory))
         (log-directory (expand-file-name "logs" directory))
         (process-environment (copy-sequence process-environment)))
    (unwind-protect
        (progn
          (make-directory server-directory t)
          (make-directory binary-directory t)
          (copy-file
           (expand-file-name
            "servers/omnivox" emacsvox-launcher-tests--root)
           launcher)
          (copy-file
           (expand-file-name
            "servers/omnivox-log-filter" emacsvox-launcher-tests--root)
           filter)
          (with-temp-file program
            (insert "#!/bin/sh\nprintf 'native:%s\\n' \"$*\"\n"))
          (dolist (file (list launcher filter program))
            (set-file-modes file #o700))
          (setenv "PATH"
                  (concat binary-directory path-separator (getenv "PATH")))
          (setenv "OMNIVOX_LOG_DIRECTORY" log-directory)
          (with-temp-buffer
            (should
             (zerop
              (call-process launcher nil t nil "--test-argument")))
            (should (equal (buffer-string) "native:--test-argument\n"))))
      (delete-directory directory t))))

(ert-deftest emacsvox-launcher-uses-bundled-windows-runtime ()
  "The tracked launcher prefers its checkout's staged Omnivox runtime."
  (skip-unless (emacsvox-launcher-tests--wsl-p))
  (let ((fake-emacs (make-temp-file "emacsvox-launcher-emacs-")))
    (unwind-protect
        (progn
          (with-temp-file fake-emacs
            (insert
             "#!/bin/sh\n"
             "printf 'ROOT=%s\\n' \"$EMACSVOX_DIR\"\n"
             "printf 'TTS=%s\\n' \"$TTS_PROGRAM\"\n"
             "printf 'PLAY=%s\\n' \"$EMACSVOX_PLAY\"\n"
             "printf 'LEGACY_DIR=%s\\n' \"${EMACSPEAK_DIR-}\"\n"
             "printf 'LEGACY_PLAY=%s\\n' \"${EMACSPEAK_PLAY-}\"\n"))
          (set-file-modes fake-emacs #o700)
          (let ((process-environment (copy-sequence process-environment)))
            (dolist
                (name
                 '("EMACSVOX_DIR" "EMACSVOX_PLAY" "TTS_PROGRAM"
                   "EMACSPEAK_DIR" "EMACSPEAK_PLAY"))
              (setenv name nil))
            (setenv "EMACS" fake-emacs)
            (with-temp-buffer
              (should
               (zerop
                (call-process
                 (expand-file-name "bin/evox"
                                   emacsvox-launcher-tests--root)
                 nil t nil)))
              (let ((root (directory-file-name
                           emacsvox-launcher-tests--root))
                    (server
                     (if
                         (file-executable-p
                          (expand-file-name
                           "servers/omnivox-bin/current/omnivox.exe"
                           emacsvox-launcher-tests--root))
                         "omnivox"
                       "windows-outloud")))
                (should
                 (equal
                  (buffer-string)
                  (format
                   (concat
                    "ROOT=%s\n"
                    "TTS=%s/servers/%s\n"
                    "PLAY=%s/servers/windows-play\n"
                    "LEGACY_DIR=\n"
                    "LEGACY_PLAY=\n")
                   root root server root)))))))
      (delete-file fake-emacs))))

(provide 'emacsvox-launcher-tests)
;;; emacsvox-launcher-tests.el ends here
