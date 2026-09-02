;;; emacsvox-wsl-install-tests.el --- WSL installer tests -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:

;; Exercise the per-user WSL installation plan with isolated fake Windows and
;; release inputs.  No network, sudo, shell startup file, or real audio is used.

;;; Code:

(require 'ert)

(defconst emacsvox-wsl-install-tests--root
  (file-name-as-directory
   (expand-file-name
    "../" (file-name-directory (or load-file-name buffer-file-name)))))

(defun emacsvox-wsl-install-tests--write-executable (file contents)
  "Write executable FILE containing CONTENTS and return FILE."
  (make-directory (file-name-directory file) t)
  (with-temp-file file (insert contents))
  (set-file-modes file #o700)
  file)

(defun emacsvox-wsl-install-tests--file-sha256 (file)
  "Return the lowercase SHA-256 digest of FILE."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (secure-hash 'sha256 (current-buffer))))

(defun emacsvox-wsl-install-tests--write-manifest (root omnivox-sha256)
  "Write a test release manifest below ROOT using OMNIVOX-SHA256."
  (make-directory (expand-file-name "etc" root) t)
  (with-temp-file (expand-file-name "etc/wsl-install.conf" root)
    (insert
     "EMACSVOX_WSL_INSTALL_SCHEMA=1\n"
     "EMACSVOX_WSL_EMACS_VERSION=31.1\n"
     "EMACSVOX_WSL_EMACS_ARCHIVE=emacs-31.1.tar.xz\n"
     "EMACSVOX_WSL_EMACS_URL=https://example.invalid/emacs-31.1.tar.xz\n"
     "EMACSVOX_WSL_EMACS_SHA256=" (make-string 64 ?a) "\n"
     "EMACSVOX_WSL_OMNIVOX_VERSION=1.6.4\n"
     "EMACSVOX_WSL_OMNIVOX_RELEASE_URL=https://example.invalid/v1.6.4\n"
     "EMACSVOX_WSL_OMNIVOX_WINDOWS_X64_ARCHIVE=omnivox-1.6.4-windows-x64.zip\n"
     "EMACSVOX_WSL_OMNIVOX_WINDOWS_X64_SHA256=" omnivox-sha256 "\n"
     "EMACSVOX_WSL_OMNIVOX_WINDOWS_ARM64_ARCHIVE=omnivox-1.6.4-windows-arm64.zip\n"
     "EMACSVOX_WSL_OMNIVOX_WINDOWS_ARM64_SHA256=" omnivox-sha256 "\n")))

(defun emacsvox-wsl-install-tests--make-checkout (&optional omnivox-sha256)
  "Return a minimal installer checkout using OMNIVOX-SHA256."
  (let ((root (make-temp-file "emacsvox wsl installer " t)))
    (make-directory (expand-file-name "bin" root) t)
    (copy-file
     (expand-file-name
      "bin/emacsvox-wsl-install" emacsvox-wsl-install-tests--root)
     (expand-file-name "bin/emacsvox-wsl-install" root))
    (set-file-modes (expand-file-name "bin/emacsvox-wsl-install" root) #o700)
    (emacsvox-wsl-install-tests--write-manifest
     root (or omnivox-sha256 (make-string 64 ?b)))
    root))

(defun emacsvox-wsl-install-tests--make-tools (root)
  "Create minimal fake WSL tools below ROOT and return their directory."
  (let ((tools (expand-file-name "tools" root)))
    (emacsvox-wsl-install-tests--write-executable
     (expand-file-name "emacs-31" tools)
     "#!/bin/sh\nprintf '31.1'\n")
    (emacsvox-wsl-install-tests--write-executable
     (expand-file-name "powershell.exe" tools)
     "#!/bin/sh\nexit 0\n")
    (emacsvox-wsl-install-tests--write-executable
     (expand-file-name "wslpath" tools)
     "#!/bin/sh\nprintf '%s\\n' \"$EMACSVOX_WSL_TEST_WINDOWS_ROOT\"\n")
    tools))

(defun emacsvox-wsl-install-tests--environment
    (root tools home windows-root proc-version)
  "Return an isolated installer environment for the supplied paths."
  (let ((process-environment (copy-sequence process-environment)))
    (dolist
        (entry
         `(("HOME" . ,home)
           ("XDG_CONFIG_HOME" . ,(expand-file-name "config" home))
           ("XDG_CACHE_HOME" . ,(expand-file-name "cache" home))
           ("EMACS" . ,(expand-file-name "emacs-31" tools))
           ("PATH" . ,(concat tools path-separator "/usr/bin:/bin"))
           ("WSL_INTEROP" . "test")
           ("EMACSVOX_WSL_PROC_VERSION_FILE" . ,proc-version)
           ("EMACSVOX_WSL_WINDOWS_ARCHITECTURE" . "X64")
           ("EMACSVOX_WSL_WINDOWS_LOCAL_APP_DATA" . "C:\\Fake\\Local")
           ("EMACSVOX_WSL_TEST_WINDOWS_ROOT" . ,windows-root)))
      (setenv (car entry) (cdr entry)))
    (dolist
        (name
         '("EMACSVOX_DIR" "OMNIVOX_PROGRAM" "TTS_PROGRAM"
           "EMACSVOX_OMNIVOX_CONFIG_FILE"))
      (setenv name nil))
    process-environment))

(defun emacsvox-wsl-install-tests--setenv (environment name value)
  "Return ENVIRONMENT with NAME set to VALUE."
  (let ((process-environment environment))
    (setenv name value)
    process-environment))

(defun emacsvox-wsl-install-tests--call (program environment &rest arguments)
  "Call PROGRAM with ENVIRONMENT and ARGUMENTS, returning status and output."
  (with-temp-buffer
    (let ((process-environment environment)
          (default-directory "/"))
      (let ((status
             (apply #'call-process program nil '(t t) nil arguments)))
        (list status (buffer-string))))))

(ert-deftest emacsvox-wsl-installer-check-is-non-mutating-and-architecture-aware ()
  "Doctor mode should explain x64 and ARM64 plans without creating config."
  (let* ((root (emacsvox-wsl-install-tests--make-checkout))
         (tools (emacsvox-wsl-install-tests--make-tools root))
         (home (expand-file-name "home" root))
         (windows-root (expand-file-name "windows" root))
         (proc-version (expand-file-name "proc-version" root))
         (installer (expand-file-name "bin/emacsvox-wsl-install" root)))
    (unwind-protect
        (progn
          (make-directory home t)
          (with-temp-file proc-version (insert "Microsoft WSL2\n"))
          (dolist
              (case '(("X64" "windows-x64") ("Arm64" "windows-arm64")))
            (let ((environment
                   (emacsvox-wsl-install-tests--environment
                    root tools home windows-root proc-version)))
              (setq environment
                    (emacsvox-wsl-install-tests--setenv
                     environment "EMACSVOX_WSL_WINDOWS_ARCHITECTURE"
                     (car case)))
              (let* ((result
                      (emacsvox-wsl-install-tests--call
                       installer environment "--check"))
                     (status (car result))
                     (output (cadr result)))
                (should (zerop status))
                (should (string-search (cadr case) output))
                (should (string-search "No files were changed" output)))))
          (should-not
           (file-exists-p
            (expand-file-name "config/emacsvox/omnivox-program" home))))
      (delete-directory root t))))

(ert-deftest emacsvox-wsl-installer-reports-one-reviewed-package-command ()
  "Missing distribution packages should not cause automatic privileged work."
  (let* ((root (emacsvox-wsl-install-tests--make-checkout))
         (tools (emacsvox-wsl-install-tests--make-tools root))
         (home (expand-file-name "home" root))
         (windows-root (expand-file-name "windows" root))
         (proc-version (expand-file-name "proc-version" root))
         (installer (expand-file-name "bin/emacsvox-wsl-install" root)))
    (unwind-protect
        (progn
          (make-directory home t)
          (with-temp-file proc-version (insert "Microsoft WSL2\n"))
          (emacsvox-wsl-install-tests--write-executable
           (expand-file-name "dpkg-query" tools)
           (concat
            "#!/bin/sh\n"
            "for argument do package=$argument; done\n"
            "[ \"$package\" = curl ] && exit 1\n"
            "printf 'install ok installed\\n'\n"))
          (let* ((environment
                  (emacsvox-wsl-install-tests--environment
                   root tools home windows-root proc-version))
                 (result
                  (emacsvox-wsl-install-tests--call
                   installer environment "--check"))
                 (status (car result))
                 (output (cadr result)))
            (should (= status 2))
            (should (string-search "sudo apt update" output))
            (should (string-search "sudo apt install curl" output))
            (should (string-search "No packages were installed automatically"
                                   output))
            (should-not
             (file-exists-p
              (expand-file-name "config/emacsvox/omnivox-program" home)))))
      (delete-directory root t))))

(ert-deftest emacsvox-wsl-installer-check-recognizes-selected-release ()
  "Doctor mode should not recommend reinstalling the selected release."
  (let* ((root (emacsvox-wsl-install-tests--make-checkout))
         (tools (emacsvox-wsl-install-tests--make-tools root))
         (home (expand-file-name "home" root))
         (windows-root (expand-file-name "windows" root))
         (proc-version (expand-file-name "proc-version" root))
         (installer (expand-file-name "bin/emacsvox-wsl-install" root))
         (installed-program
          (expand-file-name
           "Emacsvox/Omnivox/releases/1.6.4-windows-x64/omnivox.exe"
           windows-root))
         (config-file
          (expand-file-name "config/emacsvox/omnivox-program" home)))
    (unwind-protect
        (progn
          (make-directory home t)
          (with-temp-file proc-version (insert "Microsoft WSL2\n"))
          (emacsvox-wsl-install-tests--write-executable
           installed-program
           "#!/bin/sh\nprintf 'omnivox 1.6.4\\n'\n")
          (make-directory (file-name-directory config-file) t)
          (with-temp-file config-file
            (insert installed-program "\n"))
          (let* ((environment
                  (emacsvox-wsl-install-tests--environment
                   root tools home windows-root proc-version))
                 (result
                  (emacsvox-wsl-install-tests--call
                   installer environment "--check"))
                 (status (car result))
                 (output (cadr result)))
            (should (zerop status))
            (should
             (string-search
              "Omnivox 1.6.4 is already installed and selected" output))
            (should-not (string-search "to install" output))))
      (delete-directory root t))))

(ert-deftest emacsvox-wsl-installer-installs-a-verified-release-per-user ()
  "The complete binary route should persist selection without shell edits."
  (skip-unless (executable-find "zip"))
  (let* ((fixture (make-temp-file "emacsvox omnivox archive " t))
         (payload (expand-file-name "payload" fixture))
         (archive (expand-file-name "omnivox.zip" fixture)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "espeak-ng-data" payload) t)
          (make-directory (expand-file-name "third-party-licenses" payload) t)
          (emacsvox-wsl-install-tests--write-executable
           (expand-file-name "omnivox.exe" payload)
           (concat
            "#!/bin/sh\n"
            "case ${1-} in\n"
            "  --version) printf 'omnivox 1.6.4\\n' ;;\n"
            "  *) printf 'omnivox:%s\\n' \"$*\" ;;\n"
            "esac\n"))
          (with-temp-file (expand-file-name "espeak-ng-data/data" payload)
            (insert "data"))
          (let ((default-directory payload))
            (should (zerop (call-process "zip" nil nil nil "-qr" archive "."))))
          (let* ((hash (emacsvox-wsl-install-tests--file-sha256 archive))
                 (root (emacsvox-wsl-install-tests--make-checkout hash))
                 (tools (emacsvox-wsl-install-tests--make-tools root))
                 (home (expand-file-name "home" root))
                 (windows-root (expand-file-name "windows" root))
                 (proc-version (expand-file-name "proc-version" root))
                 (make-log (expand-file-name "make.log" root))
                 (installer
                  (expand-file-name "bin/emacsvox-wsl-install" root))
                 (installed-program
                  (expand-file-name
                   (concat
                    "Emacsvox/Omnivox/releases/"
                    "1.6.4-windows-x64/omnivox.exe")
                   windows-root)))
            (unwind-protect
                (progn
                  (make-directory home t)
                  (with-temp-file proc-version (insert "Microsoft WSL2\n"))
                  (emacsvox-wsl-install-tests--write-executable
                   (expand-file-name "curl" tools)
                   (concat
                    "#!/bin/sh\n"
                    "output=\n"
                    "while [ \"$#\" -gt 0 ]; do\n"
                    "  case $1 in\n"
                    "    --output) output=$2; shift 2 ;;\n"
                    "    *) shift ;;\n"
                    "  esac\n"
                    "done\n"
                    "cp \"$EMACSVOX_WSL_TEST_ARCHIVE\" \"$output\"\n"))
                  (emacsvox-wsl-install-tests--write-executable
                   (expand-file-name "make" tools)
                   "#!/bin/sh\nprintf '%s\\n' \"$*\" >>\"$EMACSVOX_WSL_TEST_MAKE_LOG\"\n")
                  (emacsvox-wsl-install-tests--write-executable
                   (expand-file-name "bin/emacsvox" root)
                   "#!/bin/sh\nprintf 'launcher:%s\\n' \"$*\"\n")
                  (let ((environment
                         (emacsvox-wsl-install-tests--environment
                          root tools home windows-root proc-version)))
                    (setq environment
                          (emacsvox-wsl-install-tests--setenv
                           environment "EMACSVOX_WSL_TEST_ARCHIVE" archive))
                    (setq environment
                          (emacsvox-wsl-install-tests--setenv
                           environment "EMACSVOX_WSL_TEST_MAKE_LOG" make-log))
                    (let* ((result
                            (emacsvox-wsl-install-tests--call
                             installer environment))
                           (status (car result))
                           (output (cadr result))
                           (config-file
                            (expand-file-name
                             "config/emacsvox/omnivox-program" home)))
                      (should (zerop status))
                      (should (file-executable-p installed-program))
                      (should (file-exists-p config-file))
                      (with-temp-buffer
                        (insert-file-contents config-file)
                        (should (equal (buffer-string)
                                       (concat installed-program "\n"))))
                      (should (string-search "launcher:--diagnose" output))
                      (should (string-search "launcher:--check" output))
                      (should (string-search "WSL installation complete" output))
                      (should-not (file-exists-p
                                   (expand-file-name ".profile" home)))
                      (with-temp-buffer
                        (insert-file-contents make-log)
                        (should
                         (string-search
                          "bytecode-rebuild" (buffer-string)))))))
              (delete-directory root t))))
      (delete-directory fixture t))))

(provide 'emacsvox-wsl-install-tests)
;;; emacsvox-wsl-install-tests.el ends here
