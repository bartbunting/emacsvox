;;; emacsvox-remote-install-tests.el --- Remote installer contracts -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Isolated fake releases and tools exercise acquisition without network,
;; Windows interoperability, system packages, audio, or a real source build.

;;; Code:

(require 'cl-lib)
(require 'emacsvox-wsl-install-tests)
(require 'emacsvox-launcher-tests)

(defun emacsvox-remote-install-tests--fixture (callback)
  "Call CALLBACK with a checkout, fake tools, and isolated environment."
  (let* ((root (emacsvox-wsl-install-tests--make-checkout))
         (tools (emacsvox-wsl-install-tests--make-tools root))
         (home (expand-file-name "home" root))
         (environment
          (emacsvox-wsl-install-tests--environment root tools home "unused" "/dev/null")))
    (dolist (name '("EMACSVOX_REMOTE_HOST" "EMACSVOX_REMOTE_PORT" "EMACSVOX_REMOTE_TOKEN_FILE"))
      (setq environment (emacsvox-wsl-install-tests--setenv environment name nil)))
    (unwind-protect
        (progn
          (make-directory home t)
          (dolist (file '("bin/emacsvox-install" "bin/emacsvox"
                          "utils/emacsvox-remote-startup.el" "utils/emacsvox-remote-check.el"))
            (copy-file (expand-file-name file emacsvox-wsl-install-tests--root)
                       (expand-file-name file root)))
          (make-directory (expand-file-name "lisp" root))
          (with-temp-file (expand-file-name "lisp/emacsvox-setup.el" root) (insert "; fixture\n"))
          (with-temp-file (expand-file-name "os-release" root) (insert "ID=debian\n"))
          (setq environment
                (emacsvox-wsl-install-tests--setenv environment "EMACSVOX_INSTALL_OS_RELEASE_FILE"
                                                   (expand-file-name "os-release" root))
                environment
                (emacsvox-wsl-install-tests--setenv environment "EMACSVOX_INSTALL_TEST_ROOT" root))
          (dolist (tool '("powershell.exe" "wslpath" "omnivox" "unzip" "curl" "sudo"))
            (emacsvox-wsl-install-tests--write-executable
             (expand-file-name tool tools)
             "#!/bin/sh\nprintf '%s\\n' \"$0\" >>\"$EMACSVOX_INSTALL_TEST_ROOT/forbidden\"\nexit 99\n"))
          (emacsvox-wsl-install-tests--write-executable
           (expand-file-name "emacs-31" tools)
           "#!/bin/sh\ncase $* in *EMACSVOX_VERSION*) printf EMACSVOX_VERSION=31.1 ;; *) printf 31.1 ;; esac\n")
          (emacsvox-wsl-install-tests--write-executable
           (expand-file-name "emacs" tools) "#!/bin/sh\nprintf 30.1\n")
          (emacsvox-wsl-install-tests--write-executable
           (expand-file-name "dpkg-query" tools) "#!/bin/sh\nprintf 'install ok installed'\n")
          (emacsvox-wsl-install-tests--write-executable
           (expand-file-name "make" tools)
           (concat "#!/bin/sh\nprintf '%s\\n' \"$*\" >>\"$EMACSVOX_INSTALL_TEST_ROOT/make-calls\"\n"
                   "if [ \"$1\" = install ]; then\n"
                   "  prefix=$(cat prefix); stage=${2#DESTDIR=}\n"
                   "  mkdir -p \"$stage$prefix/bin\"\n"
                   "  cp \"$EMACSVOX_INSTALL_TEST_ROOT/tools/emacs-31\" \"$stage$prefix/bin/emacs\"\n"
                   "fi\n"))
          (funcall callback root tools environment))
      (delete-directory root t))))

(defun emacsvox-remote-install-tests--call (root environment &rest arguments)
  "Run the installer in ROOT with ENVIRONMENT and ARGUMENTS."
  (apply #'emacsvox-wsl-install-tests--call
         (expand-file-name "bin/emacsvox-install" root) environment
         "--role" "remote-emacs" arguments))

(ert-deftest emacsvox-remote-install-reuses-emacs-without-local-speech ()
  "Doctor is non-mutating and installation uses no speech or download tools."
  (emacsvox-remote-install-tests--fixture
   (lambda (root _tools environment)
     (let ((check (emacsvox-remote-install-tests--call root environment "--check")))
       (should (zerop (car check)))
       (should (string-match-p "Local speech components: none" (cadr check)))
       (should-not (file-exists-p (expand-file-name "local.mk" root)))
       (should-not (file-exists-p (expand-file-name "make-calls" root))))
     (let ((install (emacsvox-remote-install-tests--call root environment)))
       (should (zerop (car install)))
       (should (string-match-p "Workstation speech has not been tested" (cadr install))))
     (should (file-exists-p (expand-file-name "local.mk" root)))
     (should-not (file-exists-p (expand-file-name "forbidden" root)))
     (should-not (file-exists-p (expand-file-name "home/config" root))))))

(ert-deftest emacsvox-remote-install-reuses-ubuntu-emacs-30-2 ()
  "A supported distro Emacs never triggers acquisition of the pinned Emacs."
  (emacsvox-remote-install-tests--fixture
   (lambda (root tools environment)
     (dolist (version '("30.2" "30.10" "31.1"))
       (emacsvox-wsl-install-tests--write-executable
        (expand-file-name "emacs-31" tools)
        (concat "#!/bin/sh\ncase $* in *EMACSVOX_VERSION*) "
                "printf '%s' 'EMACSVOX_VERSION=" version "' ;; "
                "*) printf '%s' '" version "' ;; esac\n"))
       (let ((result (emacsvox-remote-install-tests--call root environment)))
         (should (zerop (car result))))
       (should-not (file-exists-p (expand-file-name "forbidden" root)))
       (should-not (file-directory-p
                    (expand-file-name "home/.local/opt/emacs-31.1-terminal" root)))))))

(ert-deftest emacsvox-remote-install-offers-package-or-explicit-build ()
  "Default acquisition checks apt's upstream version and makes no changes."
  (emacsvox-remote-install-tests--fixture
   (lambda (root tools environment)
     (setq environment (emacsvox-wsl-install-tests--setenv environment "EMACS" nil))
     (dolist (entry '(("1:30.2+1-2ubuntu1" . t) ("1:31.1-1" . t)
                      ("1:29.4-1" . nil) ("2:30.1-1" . nil) ("(none)" . nil)))
       (emacsvox-wsl-install-tests--write-executable
        (expand-file-name "apt-cache" tools)
        (format "#!/bin/sh\nprintf '  Candidate: %%s\n' '%s'\n" (car entry)))
       (let* ((result (emacsvox-remote-install-tests--call root environment))
              (output (cadr result)))
         (should (= 2 (car result)))
         (should (eq (and (string-search "sudo apt install emacs-nox" output) t)
                     (cdr entry)))
         (should (string-search "--build-emacs" output))
         (should-not (string-search "libgnutls28-dev" output)))
       (should-not (file-exists-p (expand-file-name "forbidden" root)))
       (should-not (file-exists-p (expand-file-name "make-calls" root)))
       (should-not (file-exists-p (expand-file-name "local.mk" root)))))))

(ert-deftest emacsvox-remote-install-preserves-explicit-selections ()
  "Unsupported, empty, and conflicting explicit selections cannot be replaced."
  (emacsvox-remote-install-tests--fixture
   (lambda (root tools environment)
     (should-not (zerop (car (emacsvox-remote-install-tests--call
                             root environment "--build-emacs"))))
     (dolist (selection (list "" (expand-file-name "emacs" tools)))
       (let ((result
              (emacsvox-remote-install-tests--call
               root (emacsvox-wsl-install-tests--setenv environment "EMACS" selection))))
         (should-not (zerop (car result)))))
     (with-temp-file (expand-file-name "local.mk" root)
       (insert "EMACS=" (expand-file-name "emacs" tools) "\nJOBS=8\n"))
     (let ((result (emacsvox-remote-install-tests--call root environment)))
       (should-not (zerop (car result)))
       (should (string-match-p "different executables" (cadr result))))
     (should-not (file-exists-p (expand-file-name "make-calls" root))))))

(ert-deftest emacsvox-remote-install-reads-emacs-among-other-local-settings ()
  "Other local.mk settings do not obscure or get replaced by Emacs selection."
  (emacsvox-remote-install-tests--fixture
   (lambda (root tools environment)
     (let ((contents (concat "# Personal settings\nEMACS=" (expand-file-name "emacs-31" tools)
                             "\nJOBS=8\n")))
       (with-temp-file (expand-file-name "local.mk" root) (insert contents))
       (should (zerop (car (emacsvox-remote-install-tests--call
                           root (emacsvox-wsl-install-tests--setenv environment "EMACS" nil)))))
       (should (equal contents (with-temp-buffer
                                 (insert-file-contents (expand-file-name "local.mk" root))
                                 (buffer-string))))))))

(ert-deftest emacsvox-remote-install-build-prerequisites-are-terminal-only ()
  "A missing package report excludes GUI and local speech dependencies."
  (emacsvox-remote-install-tests--fixture
   (lambda (root tools environment)
     (emacsvox-wsl-install-tests--write-executable
      (expand-file-name "dpkg-query" tools) "#!/bin/sh\nexit 1\n")
     (let ((result (emacsvox-remote-install-tests--call
                    root (emacsvox-wsl-install-tests--setenv environment "EMACS" nil) "--check" "--build-emacs")))
       (should (= 2 (car result)))
       (should (string-match-p "sudo apt install .*libgnutls28-dev" (cadr result)))
       (should-not (string-match-p "libgtk\\|libasound\\|libxpm\\|unzip" (cadr result))))
     (should-not (file-exists-p (expand-file-name "forbidden" root)))
     (should-not (file-exists-p (expand-file-name "local.mk" root))))))

(ert-deftest emacsvox-remote-install-other-linux-requires-existing-emacs ()
  "Existing Emacs works on other Linux; automatic acquisition is explicit."
  (emacsvox-remote-install-tests--fixture
   (lambda (root _tools environment)
     (with-temp-file (expand-file-name "os-release" root) (insert "ID=fedora\n"))
     (should (zerop (car (emacsvox-remote-install-tests--call root environment "--check"))))
     (let ((result (emacsvox-remote-install-tests--call
                    root (emacsvox-wsl-install-tests--setenv environment "EMACS" nil) "--check" "--build-emacs")))
       (should-not (zerop (car result)))
       (should (string-match-p "requires Debian/Ubuntu" (cadr result)))))))

(ert-deftest emacsvox-remote-install-doctor-rejects-incomplete-installation ()
  "Doctor reports a conflicting partial installation without overwriting it."
  (emacsvox-remote-install-tests--fixture
   (lambda (root _tools environment)
     (make-directory (expand-file-name "home/.local/opt/emacs-31.1-terminal" root) t)
     (let ((result (emacsvox-remote-install-tests--call
                    root (emacsvox-wsl-install-tests--setenv environment "EMACS" nil) "--check")))
       (should-not (zerop (car result)))
       (should (string-match-p "installation is incomplete" (cadr result))))
     (should-not (file-exists-p (expand-file-name "local.mk" root))))))

(defun emacsvox-remote-install-tests--archive (root tools)
  "Create a fake Emacs archive for ROOT and a downloading tool in TOOLS."
  (let* ((source (expand-file-name "payload/emacs-31.1" root))
         (archive (expand-file-name "emacs-fixture.tar.xz" root)))
    (emacsvox-wsl-install-tests--write-executable
     (expand-file-name "configure" source)
     (concat "#!/bin/sh\nprintf '%s\\n' \"$@\" >\"$EMACSVOX_INSTALL_TEST_ROOT/configure-args\"\n"
             "for arg do case $arg in --prefix=*) printf '%s' \"${arg#--prefix=}\" >prefix ;; esac; done\n"))
    (should (zerop (call-process "tar" nil nil nil "-cJf" archive "-C"
                                (expand-file-name "payload" root) "emacs-31.1")))
    (emacsvox-wsl-install-tests--write-executable
     (expand-file-name "curl" tools)
     (concat "#!/bin/sh\nwhile [ \"$#\" -gt 0 ]; do\n"
             "if [ \"$1\" = --output ]; then cp \"$EMACSVOX_INSTALL_TEST_ROOT/emacs-fixture.tar.xz\" \"$2\"; exit; fi\n"
             "shift; done\nexit 1\n"))
    (with-temp-buffer
      (insert-file-contents (expand-file-name "etc/wsl-install.conf" root))
      (goto-char (point-min))
      (search-forward (make-string 64 ?a))
      (replace-match (emacsvox-wsl-install-tests--file-sha256 archive) t t)
      (write-region (point-min) (point-max) (expand-file-name "etc/wsl-install.conf" root) nil 'silent))))

(ert-deftest emacsvox-remote-install-builds-verified-terminal-emacs-and-reuses-it ()
  "Acquisition configures no GUI/audio, records its path, and reuses the build."
  (emacsvox-remote-install-tests--fixture
   (lambda (root tools environment)
     (emacsvox-remote-install-tests--archive root tools)
     (setq environment (emacsvox-wsl-install-tests--setenv environment "EMACS" nil))
     (let ((result (emacsvox-remote-install-tests--call root environment "--build-emacs")))
       (should (zerop (car result))))
     (let ((arguments (with-temp-buffer
                        (insert-file-contents (expand-file-name "configure-args" root))
                        (buffer-string))))
       (should (string-match-p "--without-x" arguments))
       (should (string-match-p "--without-sound" arguments))
       (should-not (string-match-p "gtk\\|alsa" arguments)))
     (should (file-executable-p (expand-file-name "home/.local/opt/emacs-31.1-terminal/bin/emacs" root)))
     (delete-file (expand-file-name "configure-args" root))
     (should (zerop (car (emacsvox-remote-install-tests--call root environment))))
     (should-not (file-exists-p (expand-file-name "configure-args" root)))
     (should-not (file-exists-p (expand-file-name "forbidden" root))))))

(ert-deftest emacsvox-remote-install-rejects-corrupt-emacs-archive ()
  "A checksum mismatch prevents extraction, compilation, and configuration."
  (emacsvox-remote-install-tests--fixture
   (lambda (root tools environment)
     (emacsvox-remote-install-tests--archive root tools)
     (with-temp-file (expand-file-name "emacs-fixture.tar.xz" root) (insert "corrupt"))
     (let ((result (emacsvox-remote-install-tests--call
                    root (emacsvox-wsl-install-tests--setenv environment "EMACS" nil) "--build-emacs")))
       (should-not (zerop (car result)))
       (should (string-match-p "checksum verification failed" (cadr result))))
     (dolist (file '("configure-args" "make-calls" "local.mk"))
       (should-not (file-exists-p (expand-file-name file root)))))))

(ert-deftest emacsvox-remote-launcher-skips-local-probes-and-selects-check-helper ()
  "Remote diagnosis needs no credentials; launch/check never resolve local TTS."
  (emacsvox-remote-install-tests--fixture
   (lambda (root tools environment)
     (emacsvox-launcher-tests--fake-emacs (expand-file-name "emacs-31" tools) "31.1")
     (setq environment (emacsvox-wsl-install-tests--setenv environment "OMNIVOX_PROGRAM" "/missing/omnivox")
           environment (emacsvox-wsl-install-tests--setenv environment "TTS_PROGRAM" "/missing/launcher/omnivox")
           environment (emacsvox-wsl-install-tests--setenv environment "EMACSVOX_PLAY" "/forbidden/audio"))
     (let ((launcher (expand-file-name "bin/emacsvox" root)))
       (dolist (arguments '(("--remote" "--diagnose") ("--diagnose" "--remote")))
         (let ((result (apply #'emacsvox-wsl-install-tests--call launcher environment arguments)))
           (should (zerop (car result)))
           (should (string-match-p "Token file is not ready" (cadr result)))))
       (let ((result (emacsvox-wsl-install-tests--call launcher environment "--remote" "--" "notes file.org")))
         (should (zerop (car result)))
         (should (string-match-p "ARG=-nw" (cadr result)))
         (should (string-match-p "PLAY=\n" (cadr result)))
         (should (string-match-p "remote-startup.el\nARG=--funcall\nARG=emacsvox-remote-startup" (cadr result)))
         (should (string-match-p "ARG=notes file.org" (cadr result))))
       (let ((result (emacsvox-wsl-install-tests--call launcher environment "--remote" "--check")))
         (should (zerop (car result)))
         (should (string-match-p "ARG=--batch" (cadr result)))
         (should (string-match-p "remote-check.el" (cadr result)))))
     (should-not (file-exists-p (expand-file-name "forbidden" root))))))

(ert-deftest emacsvox-remote-launcher-rejects-invalid-connection-selection ()
  "Remote mode rejects external hosts, invalid ports, and another speech backend."
  (emacsvox-remote-install-tests--fixture
   (lambda (root _tools environment)
     (dolist (setting '(("EMACSVOX_REMOTE_HOST" . "192.0.2.1")
                        ("EMACSVOX_REMOTE_PORT" . "65536")
                        ("EMACSVOX_REMOTE_PORT" . "0")
                        ("EMACSVOX_REMOTE_PORT" . "no")
                        ("EMACSVOX_REMOTE_TOKEN_FILE" . "relative-token")
                        ("TTS_PROGRAM" . "espeak")))
       (let ((result (emacsvox-wsl-install-tests--call
                      (expand-file-name "bin/emacsvox" root)
                      (emacsvox-wsl-install-tests--setenv environment (car setting) (cdr setting))
                      "--remote" "--diagnose")))
         (should-not (zerop (car result))))))))

(ert-deftest emacsvox-remote-launcher-loads-settings-before-setup-as-data ()
  "Fresh real Emacs sees remote settings before setup, without evaluating paths."
  (emacsvox-remote-install-tests--fixture
   (lambda (root _tools environment)
     (let ((token-path (expand-file-name "private \"quoted\" token" root)))
       (setq environment
             (emacsvox-wsl-install-tests--setenv
              environment "EMACS" (expand-file-name invocation-name invocation-directory))
             environment (emacsvox-wsl-install-tests--setenv environment "EMACSVOX_REMOTE_HOST" "::1")
             environment (emacsvox-wsl-install-tests--setenv environment "EMACSVOX_REMOTE_PORT" "6543")
             environment (emacsvox-wsl-install-tests--setenv environment "EMACSVOX_REMOTE_TOKEN_FILE" token-path))
       (with-temp-file (expand-file-name "lisp/emacsvox-setup.el" root)
         (insert "(unless (and (equal tts-program \"omnivox\")\n"
                 "             (equal omnivox-remote-host \"::1\")\n"
                 "             (= omnivox-remote-port 6543)\n"
                 "             (equal omnivox-remote-token-file (getenv \"EMACSVOX_REMOTE_TOKEN_FILE\")))\n"
                 "  (error \"Remote settings were not supplied before setup\"))\n"
                 "(princ \"Remote startup settings verified.\")\n"))
       (let ((result (emacsvox-wsl-install-tests--call
                      (expand-file-name "bin/emacsvox" root) environment "--remote" "--batch")))
         (should (zerop (car result)))
         (should (string-match-p "Remote startup settings verified" (cadr result))))))))

(ert-deftest emacsvox-remote-launcher-failure-does-not-print-authentication-frames ()
  "Startup errors unwind sensitive transport frames before batch reporting."
  (emacsvox-remote-install-tests--fixture
   (lambda (root _tools environment)
     (setq environment
           (emacsvox-wsl-install-tests--setenv
            environment "EMACS" (expand-file-name invocation-name invocation-directory)))
     (with-temp-file (expand-file-name "lisp/emacsvox-setup.el" root)
       (insert "(defun fixture-authenticate (token) (error \"Connection refused\"))\n"
               "(fixture-authenticate \"private-authentication-value\")\n"))
     (let ((result (emacsvox-wsl-install-tests--call
                    (expand-file-name "bin/emacsvox" root) environment "--remote" "--batch")))
       (should-not (zerop (car result)))
       (should (string-match-p "Remote Emacsvox startup failed: Connection refused" (cadr result)))
       (should-not (string-match-p "private-authentication-value" (cadr result)))))))

(provide 'emacsvox-remote-install-tests)
;;; emacsvox-remote-install-tests.el ends here
