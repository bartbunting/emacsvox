;;; emacsvox-launcher-tests.el --- Launcher smoke tests -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Verify the portable first-use launcher and the bundled Omnivox runtime
;; launcher without starting a real speech server.

;;; Code:

(require 'ert)

(defconst emacsvox-launcher-tests--root
  (expand-file-name "../" (file-name-directory load-file-name)))

(defun emacsvox-launcher-tests--write-executable (file contents)
  "Write executable FILE containing CONTENTS and return FILE."
  (make-directory (file-name-directory file) t)
  (with-temp-file file
    (insert contents))
  (set-file-modes file #o700)
  file)

(defun emacsvox-launcher-tests--make-checkout ()
  "Return a minimal launcher checkout in a path containing spaces."
  (let ((root (make-temp-file "emacsvox launcher checkout " t)))
    (dolist (relative '("bin/emacsvox" "bin/evox" "servers/omnivox"))
      (let ((destination (expand-file-name relative root)))
        (make-directory (file-name-directory destination) t)
        (copy-file
         (expand-file-name relative emacsvox-launcher-tests--root)
         destination)
        (set-file-modes destination #o700)))
    (make-directory (expand-file-name "lisp" root) t)
    (with-temp-file (expand-file-name "lisp/emacsvox-setup.el" root)
      (insert ";;; launcher test setup source\n"))
    root))

(defun emacsvox-launcher-tests--fake-emacs (file version)
  "Write a fake Emacs executable at FILE reporting VERSION."
  (emacsvox-launcher-tests--write-executable
   file
   (concat
    "#!/bin/sh\n"
    "case $* in\n"
    "  *EMACSVOX_VERSION*) printf '%s' 'EMACSVOX_VERSION=" version
    "'; exit 0 ;;\n"
    "esac\n"
    "printf 'ROOT=%s\\n' \"${EMACSVOX_DIR-}\"\n"
    "printf 'TTS=%s\\n' \"${TTS_PROGRAM-}\"\n"
    "printf 'PLAY=%s\\n' \"${EMACSVOX_PLAY-}\"\n"
    "printf 'LEGACY_DIR=%s\\n' \"${EMACSPEAK_DIR-}\"\n"
    "printf 'LEGACY_PLAY=%s\\n' \"${EMACSPEAK_PLAY-}\"\n"
    "for argument\n"
    "do\n"
    "  printf 'ARG=%s\\n' \"$argument\"\n"
    "done\n")))

(defun emacsvox-launcher-tests--fake-omnivox (file)
  "Write a fake native Omnivox executable at FILE."
  (emacsvox-launcher-tests--write-executable
   file
   "#!/bin/sh\nprintf 'OMNIVOX=%s\\n' \"$*\"\n"))

(defun emacsvox-launcher-tests--call (program &rest arguments)
  "Call PROGRAM with ARGUMENTS and return its status and combined output."
  (with-temp-buffer
    (let ((status
           (apply #'call-process program nil '(t t) nil arguments)))
      (list status (buffer-string)))))

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
          (setenv "OMNIVOX_PROGRAM" nil)
          (setenv "OMNIVOX_LOG_DIRECTORY" log-directory)
          (with-temp-buffer
            (should
             (zerop
              (call-process launcher nil t nil "--test-argument")))
            (should (equal (buffer-string) "native:--test-argument\n"))))
      (delete-directory directory t))))

(ert-deftest emacsvox-launcher-honors-configured-omnivox-program ()
  "A configured binary takes precedence over the staged WSL runtime."
  (let* ((directory (make-temp-file "emacsvox configured launcher-" t))
         (server-directory (expand-file-name "servers" directory))
         (runtime-directory
          (expand-file-name "omnivox-bin/current" server-directory))
         (launcher (expand-file-name "omnivox" server-directory))
         (filter (expand-file-name "omnivox-log-filter" server-directory))
         (program (expand-file-name "custom-omnivox.Exe" directory))
         (staged-program (expand-file-name "omnivox.exe" runtime-directory))
         (log-directory (expand-file-name "logs" directory))
         (process-environment (copy-sequence process-environment)))
    (unwind-protect
        (progn
          (make-directory runtime-directory t)
          (copy-file
           (expand-file-name
            "servers/omnivox" emacsvox-launcher-tests--root)
           launcher)
          (copy-file
           (expand-file-name
            "servers/omnivox-log-filter" emacsvox-launcher-tests--root)
           filter)
          (with-temp-file program
            (insert "#!/bin/sh\nprintf 'configured:%s\\n' \"$*\"\n"))
          (with-temp-file staged-program
            (insert "#!/bin/sh\nprintf 'staged:%s\\n' \"$*\"\n"))
          (dolist (file (list launcher filter program staged-program))
            (set-file-modes file #o700))
          (setenv "OMNIVOX_PROGRAM" program)
          (setenv "OMNIVOX_LOG_DIRECTORY" log-directory)
          (with-temp-buffer
            (should
             (zerop (call-process launcher nil t nil "--configured")))
            (should (equal (buffer-string) "configured:--configured\n"))))
      (delete-directory directory t))))

(ert-deftest emacsvox-launcher-starts-portably-and-in-isolation ()
  "The canonical launcher works outside a checkout whose path has spaces."
  (let* ((root (emacsvox-launcher-tests--make-checkout))
         (caller (make-temp-file "emacsvox launcher caller " t))
         (tools (expand-file-name "tool chain" root))
         (fake-emacs
          (emacsvox-launcher-tests--fake-emacs
           (expand-file-name "emacs 31" tools) "31.1"))
         (fake-omnivox
          (emacsvox-launcher-tests--fake-omnivox
           (expand-file-name "omnivox runtime" tools)))
         (launcher (expand-file-name "bin/emacsvox" root)))
    (unwind-protect
        (let ((process-environment (copy-sequence process-environment))
              (default-directory caller))
          (dolist
              (name
               '("EMACSVOX_DIR" "EMACSVOX_PLAY" "TTS_PROGRAM"
                 "EMACSPEAK_DIR" "EMACSPEAK_PLAY"
                 "EMACSVOX_OMNIVOX_PROBE_ONLY"))
            (setenv name nil))
          ;; An explicit override takes precedence over a broken local.mk.
          (with-temp-file (expand-file-name "local.mk" root)
            (insert "EMACS=/does/not/exist\n"))
          (setenv "EMACS" fake-emacs)
          (setenv "OMNIVOX_PROGRAM" fake-omnivox)
          (let* ((result
                  (emacsvox-launcher-tests--call
                   launcher "--" "--debug-init" "notes file.org"))
                 (status (car result))
                 (output (cadr result)))
            (should (zerop status))
            (should
             (string-search
              (format "ROOT=%s\n" (directory-file-name root)) output))
            (should (string-search "TTS=omnivox\n" output))
            (should (string-search "ARG=-Q\n" output))
            (should (string-search "ARG=--no-splash\n" output))
            (should (string-search "ARG=--load\n" output))
            (should
             (string-search
              (format "ARG=%s/lisp/emacsvox-setup.el\n"
                      (directory-file-name root))
              output))
            (should (string-search "ARG=--debug-init\n" output))
            (should (string-search "ARG=notes file.org\n" output))
            (should-not (string-search "init-directory" output))
            (should (string-search "LEGACY_DIR=\n" output))
            (should (string-search "LEGACY_PLAY=\n" output))))
      (delete-directory caller t)
      (delete-directory root t))))

(ert-deftest emacsvox-launcher-uses-local-mk-without-starting-audio ()
  "Diagnostics honor local.mk and leave Omnivox logging untouched."
  (let* ((root (emacsvox-launcher-tests--make-checkout))
         (tools (expand-file-name "selected tools" root))
         (fake-emacs
          (emacsvox-launcher-tests--fake-emacs
           (expand-file-name "selected emacs" tools) "31.2"))
         (fake-omnivox
          (emacsvox-launcher-tests--fake-omnivox
           (expand-file-name "selected omnivox" tools)))
         (log-directory (expand-file-name "logs must stay absent" root))
         (launcher (expand-file-name "bin/emacsvox" root)))
    (unwind-protect
        (let ((process-environment (copy-sequence process-environment)))
          (dolist (name '("EMACS" "EMACSVOX_DIR" "TTS_PROGRAM"))
            (setenv name nil))
          (with-temp-file (expand-file-name "local.mk" root)
            (insert "EMACS=" fake-emacs "\n"))
          (setenv "OMNIVOX_PROGRAM" fake-omnivox)
          (setenv "OMNIVOX_LOG_DIRECTORY" log-directory)
          (let* ((result
                  (emacsvox-launcher-tests--call launcher "--diagnose"))
                 (status (car result))
                 (output (cadr result)))
            (should (zerop status))
            (should
             (string-search (format "Emacs: %s\n" fake-emacs) output))
            (should (string-search "Emacs selection: local.mk\n" output))
            (should (string-search "Emacs version: 31.2\n" output))
            (should (string-search "Speech backend: omnivox\n" output))
            (should (string-search
                     (format "Omnivox runtime: %s\n" fake-omnivox)
                     output))
            (should-not (file-exists-p log-directory))))
      (delete-directory root t))))

(ert-deftest emacsvox-launcher-rejects-system-emacs-30 ()
  "PATH fallback does not start Emacsvox with an old system Emacs."
  (let* ((root (emacsvox-launcher-tests--make-checkout))
         (tools (expand-file-name "old system bin" root))
         (_fake-emacs
          (emacsvox-launcher-tests--fake-emacs
           (expand-file-name "emacs" tools) "30.4"))
         (launcher (expand-file-name "bin/emacsvox" root)))
    (unwind-protect
        (let ((process-environment (copy-sequence process-environment)))
          (dolist (name '("EMACS" "EMACSVOX_DIR" "TTS_PROGRAM"))
            (setenv name nil))
          (setenv "PATH" (concat tools path-separator "/usr/bin:/bin"))
          (let* ((result
                  (emacsvox-launcher-tests--call launcher "--diagnose"))
                 (status (car result))
                 (output (cadr result)))
            (should (and (integerp status) (not (zerop status))))
            (should
             (string-search
              "Emacsvox requires Emacs 31 or newer" output))))
      (delete-directory root t))))

(ert-deftest emacsvox-launcher-reports-a-missing-omnivox-runtime ()
  "The default backend fails before interactive Emacs when Omnivox is absent."
  (let* ((root (emacsvox-launcher-tests--make-checkout))
         (fake-emacs
          (emacsvox-launcher-tests--fake-emacs
           (expand-file-name "tools/emacs" root) "31.0"))
         (missing (expand-file-name "missing/omnivox" root))
         (launcher (expand-file-name "bin/emacsvox" root)))
    (unwind-protect
        (let ((process-environment (copy-sequence process-environment)))
          (dolist (name '("EMACSVOX_DIR" "TTS_PROGRAM"))
            (setenv name nil))
          (setenv "EMACS" fake-emacs)
          (setenv "OMNIVOX_PROGRAM" missing)
          (let* ((result
                  (emacsvox-launcher-tests--call launcher "--diagnose"))
                 (status (car result))
                 (output (cadr result)))
            (should (and (integerp status) (not (zerop status))))
            (should
             (string-search
              "Configured Omnivox executable is not runnable" output))
            (should
             (string-search
              "could not find a runnable Omnivox backend" output))))
      (delete-directory root t))))

(ert-deftest emacsvox-launcher-honors-root-and-backend-overrides ()
  "Explicit root and non-Omnivox backend paths are reported unchanged."
  (let* ((root (emacsvox-launcher-tests--make-checkout))
         (tools (expand-file-name "override tools" root))
         (fake-emacs
          (emacsvox-launcher-tests--fake-emacs
           (expand-file-name "emacs" tools) "31.3"))
         (backend
          (emacsvox-launcher-tests--write-executable
           (expand-file-name "custom speech" tools) "#!/bin/sh\nexit 0\n"))
         (launcher
          (expand-file-name
           "bin/emacsvox" emacsvox-launcher-tests--root)))
    (unwind-protect
        (let ((process-environment (copy-sequence process-environment)))
          (setenv "EMACSVOX_DIR" root)
          (setenv "EMACS" fake-emacs)
          (setenv "TTS_PROGRAM" backend)
          (let* ((result
                  (emacsvox-launcher-tests--call launcher "--diagnose"))
                 (status (car result))
                 (output (cadr result)))
            (should (zerop status))
            (should
             (string-search
              (format "Emacsvox root: %s\n" (directory-file-name root))
              output))
            (should
             (string-search (format "Speech backend: %s\n" backend) output))
            (should
             (string-search
              "Backend selection: TTS_PROGRAM environment variable\n"
              output))))
      (delete-directory root t))))

(ert-deftest emacsvox-launcher-check-runs-audible-omnivox-check ()
  "The explicit check mode forwards --check to Omnivox after diagnostics."
  (let* ((root (emacsvox-launcher-tests--make-checkout))
         (tools (expand-file-name "check tools" root))
         (fake-emacs
          (emacsvox-launcher-tests--fake-emacs
           (expand-file-name "emacs" tools) "31.0"))
         (fake-omnivox
          (emacsvox-launcher-tests--fake-omnivox
           (expand-file-name "omnivox" tools)))
         (launcher (expand-file-name "bin/emacsvox" root)))
    (unwind-protect
        (let ((process-environment (copy-sequence process-environment)))
          (dolist (name '("EMACSVOX_DIR" "TTS_PROGRAM"))
            (setenv name nil))
          (setenv "EMACS" fake-emacs)
          (setenv "OMNIVOX_PROGRAM" fake-omnivox)
          (setenv "OMNIVOX_LOG_DIRECTORY" (expand-file-name "logs" root))
          (let* ((result
                  (emacsvox-launcher-tests--call launcher "--check"))
                 (status (car result))
                 (output (cadr result)))
            (should (zerop status))
            (should
             (string-search "Running the audible Omnivox check" output))
            (should (string-search "OMNIVOX=--check\n" output))))
      (delete-directory root t))))

(ert-deftest emacsvox-launcher-evox-is-a-bounded-compatibility-shim ()
  "The old evox name warns and forwards to the isolated launcher."
  (let* ((root (emacsvox-launcher-tests--make-checkout))
         (tools (expand-file-name "shim tools" root))
         (fake-emacs
          (emacsvox-launcher-tests--fake-emacs
           (expand-file-name "emacs" tools) "31.0"))
         (fake-omnivox
          (emacsvox-launcher-tests--fake-omnivox
           (expand-file-name "omnivox" tools)))
         (launcher (expand-file-name "bin/evox" root)))
    (unwind-protect
        (let ((process-environment (copy-sequence process-environment)))
          (dolist (name '("EMACSVOX_DIR" "TTS_PROGRAM"))
            (setenv name nil))
          (setenv "EMACS" fake-emacs)
          (setenv "OMNIVOX_PROGRAM" fake-omnivox)
          (setenv "EMACSVOX_INIT_DIRECTORY" "/personal/evox/init")
          (let* ((result
                  (emacsvox-launcher-tests--call launcher "--diagnose"))
                 (status (car result))
                 (output (cadr result)))
            (should (zerop status))
            (should (string-search "evox: deprecated" output))
            (should
             (string-search
              "EMACSVOX_INIT_DIRECTORY is no longer used" output))
            (should
             (string-search
              "Startup configuration: isolated (-Q)" output))
            (should-not (string-search "/personal/evox/init" output))))
      (delete-directory root t))))

(ert-deftest emacsvox-launcher-configures-bundled-wsl-audio ()
  "The canonical launcher selects the bundled WSL auditory-icon player."
  (skip-unless (emacsvox-launcher-tests--wsl-p))
  (let ((fake-emacs (make-temp-file "emacsvox-launcher-emacs-"))
        (fake-omnivox (make-temp-file "emacsvox-launcher-omnivox-")))
    (unwind-protect
        (progn
          (emacsvox-launcher-tests--fake-emacs fake-emacs "31.0")
          (emacsvox-launcher-tests--fake-omnivox fake-omnivox)
          (let ((process-environment (copy-sequence process-environment)))
            (dolist
                (name
                 '("EMACSVOX_DIR" "EMACSVOX_PLAY" "TTS_PROGRAM"
                   "EMACSPEAK_DIR" "EMACSPEAK_PLAY"))
              (setenv name nil))
            (setenv "EMACS" fake-emacs)
            (setenv "OMNIVOX_PROGRAM" fake-omnivox)
            (let* ((result
                    (emacsvox-launcher-tests--call
                     (expand-file-name
                      "bin/emacsvox" emacsvox-launcher-tests--root)))
                   (status (car result))
                   (output (cadr result))
                   (root
                    (directory-file-name emacsvox-launcher-tests--root)))
              (should (zerop status))
              (should (string-search (format "ROOT=%s\n" root) output))
              (should (string-search "TTS=omnivox\n" output))
              (should
               (string-search
                (format "PLAY=%s/servers/windows-play\n" root) output))
              (should (string-search "LEGACY_DIR=\n" output))
              (should (string-search "LEGACY_PLAY=\n" output)))))
      (delete-file fake-emacs)
      (delete-file fake-omnivox))))

(provide 'emacsvox-launcher-tests)
;;; emacsvox-launcher-tests.el ends here
