;;; emacsvox-omnivox-components-tests.el --- Omnivox module tests -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:

;; Exercise the spoken module manager and its isolated, verified WSL2
;; installer without network access or changes to the real Windows profile.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-wsl-install-tests)
(require 'emacsvox-omnivox-components)

(defun emacsvox-omnivox-components-tests--write-manifest
    (root sha256 size)
  "Write a component manifest below ROOT using SHA256 and SIZE."
  (with-temp-file (expand-file-name "etc/omnivox-components.conf" root)
    (insert
     "EMACSVOX_OMNIVOX_COMPONENTS_SCHEMA=1\n"
     "EMACSVOX_OMNIVOX_COMPONENTS_VERSION=1.7.0\n"
     "EMACSVOX_OMNIVOX_FLITE_WINDOWS_X64_ARCHIVE=flite-x64.zip\n"
     "EMACSVOX_OMNIVOX_FLITE_WINDOWS_X64_SHA256=" sha256 "\n"
     "EMACSVOX_OMNIVOX_FLITE_WINDOWS_X64_SIZE=" (number-to-string size) "\n"
     "EMACSVOX_OMNIVOX_FLITE_WINDOWS_ARM64_ARCHIVE=flite-arm64.zip\n"
     "EMACSVOX_OMNIVOX_FLITE_WINDOWS_ARM64_SHA256=" sha256 "\n"
     "EMACSVOX_OMNIVOX_FLITE_WINDOWS_ARM64_SIZE=" (number-to-string size) "\n"
     "EMACSVOX_OMNIVOX_RUTTS_WINDOWS_X64_ARCHIVE=rutts-x64.zip\n"
     "EMACSVOX_OMNIVOX_RUTTS_WINDOWS_X64_SHA256=" sha256 "\n"
     "EMACSVOX_OMNIVOX_RUTTS_WINDOWS_X64_SIZE=" (number-to-string size) "\n"
     "EMACSVOX_OMNIVOX_RUTTS_WINDOWS_ARM64_ARCHIVE=rutts-arm64.zip\n"
     "EMACSVOX_OMNIVOX_RUTTS_WINDOWS_ARM64_SHA256=" sha256 "\n"
     "EMACSVOX_OMNIVOX_RUTTS_WINDOWS_ARM64_SIZE=" (number-to-string size) "\n"
     "EMACSVOX_OMNIVOX_PIPER_WINDOWS_X64_ARCHIVE=piper-x64.zip\n"
     "EMACSVOX_OMNIVOX_PIPER_WINDOWS_X64_SHA256=" sha256 "\n"
     "EMACSVOX_OMNIVOX_PIPER_WINDOWS_X64_SIZE=" (number-to-string size) "\n"
     "EMACSVOX_OMNIVOX_TGSPEECHBOX_WINDOWS_X64_ARCHIVE=tgspeechbox-x64.zip\n"
     "EMACSVOX_OMNIVOX_TGSPEECHBOX_WINDOWS_X64_SHA256=" sha256 "\n"
     "EMACSVOX_OMNIVOX_TGSPEECHBOX_WINDOWS_X64_SIZE="
     (number-to-string size) "\n")))

(defun emacsvox-omnivox-components-tests--make-archive (root)
  "Create a minimal Flite component archive below ROOT and return its path."
  (let* ((payload (expand-file-name "payload" root))
         (directory (expand-file-name "flite" payload))
         (archive (expand-file-name "flite-x64.zip" root)))
    (emacsvox-wsl-install-tests--write-executable
     (expand-file-name "omnivox-flite-helper.exe" directory)
     "#!/bin/sh\nprintf 'flite-slt\\n'\n")
    (with-temp-file (expand-file-name "SOURCE-PROVENANCE.json" directory)
      (insert "{\"source\":\"test fixture\"}\n"))
    (let ((default-directory payload))
      (unless (zerop (call-process "zip" nil nil nil "-qr" archive "flite"))
        (error "Could not create component fixture archive")))
    archive))

(defun emacsvox-omnivox-components-tests--make-checkout
    (archive &optional manifest-sha256)
  "Create an isolated component-installer checkout for ARCHIVE.

Use MANIFEST-SHA256 when supplied instead of ARCHIVE's real digest."
  (let* ((sha256 (emacsvox-wsl-install-tests--file-sha256 archive))
         (root (emacsvox-wsl-install-tests--make-checkout sha256))
         (installer (expand-file-name
                     "bin/emacsvox-omnivox-components" root)))
    (copy-file
     (expand-file-name
      "bin/emacsvox-omnivox-components"
      emacsvox-wsl-install-tests--root)
     installer)
    (set-file-modes installer #o700)
    (emacsvox-omnivox-components-tests--write-manifest
     root (or manifest-sha256 sha256)
     (file-attribute-size (file-attributes archive)))
    root))

(defun emacsvox-omnivox-components-tests--install-core
    (windows-root)
  "Install a fake Omnivox core below WINDOWS-ROOT and return its program."
  (let ((program
         (expand-file-name
          "Emacsvox/Omnivox/releases/1.7.0-windows-x64/omnivox.exe"
          windows-root)))
    (emacsvox-wsl-install-tests--write-executable
     program
     (concat
      "#!/bin/sh\n"
      "if [ \"${1-}\" = --version ]; then\n"
      "  printf 'omnivox 1.7.0\\n'\n"
      "  exit 0\n"
      "fi\n"
      "if [ \"${1-}\" = --engine ] && [ \"${2-}\" = flite ]; then\n"
      "  [ -x \"$OMNIVOX_FLITE_HELPER\" ] || exit 3\n"
      "  \"$OMNIVOX_FLITE_HELPER\" --list-voices\n"
      "  exit $?\n"
      "fi\n"
      "printf 'fixture voice\\n'\n"))
    (let ((data-file
           (expand-file-name "espeak-ng-data/phontab"
                             (file-name-directory program))))
      (make-directory (file-name-directory data-file) t)
      (with-temp-file data-file
        (insert "fixture\n")))
    program))

(defun emacsvox-omnivox-components-tests--make-tools (root archive)
  "Create fake WSL tools below ROOT that serve ARCHIVE."
  (let ((tools (emacsvox-wsl-install-tests--make-tools root)))
    (emacsvox-wsl-install-tests--write-executable
     (expand-file-name "wslpath" tools)
     (concat
      "#!/bin/sh\n"
      "if [ \"${1-}\" = -w ]; then printf '%s\\n' \"$2\"; exit 0; fi\n"
      "printf '%s\\n' \"$EMACSVOX_WSL_TEST_WINDOWS_ROOT\"\n"))
    (emacsvox-wsl-install-tests--write-executable
     (expand-file-name "curl" tools)
     (concat
      "#!/bin/sh\n"
      "output=\n"
      "while [ $# -gt 0 ]; do\n"
      "  if [ \"$1\" = --output ]; then shift; output=$1; fi\n"
      "  shift\n"
      "done\n"
      "cp \"$EMACSVOX_COMPONENT_TEST_ARCHIVE\" \"$output\"\n"))
    (cons
     tools
     (lambda (environment)
       (emacsvox-wsl-install-tests--setenv
        environment "EMACSVOX_COMPONENT_TEST_ARCHIVE" archive)))))

(cl-defmacro emacsvox-omnivox-components-tests--with-fixture
    ((root installer environment windows-root archive) &rest body)
  "Run BODY with an isolated component installer fixture."
  (declare (indent 1) (debug t))
  `(let* ((outer (make-temp-file "emacsvox components " t))
          (,archive
           (emacsvox-omnivox-components-tests--make-archive outer))
          (,root
           (emacsvox-omnivox-components-tests--make-checkout ,archive))
          (tool-data
           (emacsvox-omnivox-components-tests--make-tools ,root ,archive))
          (tools (car tool-data))
          (add-archive (cdr tool-data))
          (home (expand-file-name "home" ,root))
          (,windows-root (expand-file-name "windows" ,root))
          (proc-version (expand-file-name "proc-version" ,root))
          (,installer
           (expand-file-name "bin/emacsvox-omnivox-components" ,root))
          (,environment nil))
     (unwind-protect
         (progn
           (make-directory home t)
           (with-temp-file proc-version (insert "Microsoft WSL2\n"))
           (setq ,environment
                 (funcall
                  add-archive
                  (emacsvox-wsl-install-tests--environment
                   ,root tools home ,windows-root proc-version)))
           ,@body)
       (delete-directory outer t)
       (delete-directory ,root t))))

(ert-deftest emacsvox-omnivox-component-list-is-machine-readable ()
  "The installer reports stable states and architecture availability."
  (emacsvox-omnivox-components-tests--with-fixture
      (root installer environment windows-root archive)
    (ignore root archive)
    (emacsvox-omnivox-components-tests--install-core windows-root)
    (let* ((result
            (emacsvox-wsl-install-tests--call
             installer environment "--machine"))
           (output (cadr result)))
      (should (zerop (car result)))
      (should (string-search
               "windows\tWindows\tinstalled\t0\t" output))
      (should (string-search
               "flite\tFlite\tavailable\t" output))
      (should (string-search
               "eloquence\tEloquence\tcore-update-required\t0\t" output)))
    (let* ((arm-environment
            (emacsvox-wsl-install-tests--setenv
             environment "EMACSVOX_WSL_WINDOWS_ARCHITECTURE" "Arm64"))
           (arm-result
            (emacsvox-wsl-install-tests--call
             installer arm-environment "--machine"))
           (arm-output (cadr arm-result)))
      (should (zerop (car arm-result)))
      (should (string-search "flite\tFlite\tavailable\t" arm-output))
      (should (string-search "piper\tPiper\tunavailable\t0\t" arm-output)))))

(ert-deftest emacsvox-omnivox-component-installer-verifies-and-stages ()
  "A verified module is checked through Omnivox before atomic installation."
  (emacsvox-omnivox-components-tests--with-fixture
      (root installer environment windows-root archive)
    (ignore root archive)
    (emacsvox-omnivox-components-tests--install-core windows-root)
    (let* ((result
            (emacsvox-wsl-install-tests--call
             installer environment "--install" "flite"))
           (destination
            (expand-file-name
             (concat
              "Emacsvox/Omnivox/releases/1.7.0-windows-x64/"
             "flite/omnivox-flite-helper.exe")
             windows-root)))
      (ert-info ((cadr result))
        (should (zerop (car result))))
      (should (string-search "Installed Flite" (cadr result)))
      (should (file-executable-p destination))
      (should (file-readable-p
               (expand-file-name "SOURCE-PROVENANCE.json"
                                 (file-name-directory destination))))
      (let ((again
             (emacsvox-wsl-install-tests--call
              installer environment "--install" "flite")))
        (should (zerop (car again)))
        (should (string-search "already installed" (cadr again)))))))

(ert-deftest emacsvox-omnivox-component-uninstaller-removes-managed-module ()
  "Uninstall removes the selected module while retaining its download cache."
  (emacsvox-omnivox-components-tests--with-fixture
      (root installer environment windows-root archive)
    (ignore root archive)
    (emacsvox-omnivox-components-tests--install-core windows-root)
    (let* ((install
            (emacsvox-wsl-install-tests--call
             installer environment "--install" "flite"))
           (destination
            (expand-file-name
             "Emacsvox/Omnivox/releases/1.7.0-windows-x64/flite"
             windows-root))
           (receipt (expand-file-name ".emacsvox-component" destination)))
      (ert-info ((cadr install))
        (should (zerop (car install))))
      (should (file-readable-p receipt))
      (let ((uninstall
             (emacsvox-wsl-install-tests--call
              installer environment "--uninstall" "flite")))
        (ert-info ((cadr uninstall))
          (should (zerop (car uninstall))))
        (should (string-search "Uninstalled Flite" (cadr uninstall)))
        (should (string-search "download cache was kept" (cadr uninstall)))
        (should-not (file-exists-p destination))
        (should
         (file-exists-p
          (expand-file-name
           "home/cache/emacsvox/downloads/flite-x64.zip" root))))
      (let ((again
             (emacsvox-wsl-install-tests--call
              installer environment "--uninstall" "flite")))
        (should (zerop (car again)))
        (should (string-search "Flite is not installed" (cadr again)))))))

(ert-deftest emacsvox-omnivox-component-uninstaller-refuses-unowned-directory ()
  "Uninstall leaves a component-shaped directory without provenance intact."
  (emacsvox-omnivox-components-tests--with-fixture
      (root installer environment windows-root archive)
    (ignore root archive)
    (let* ((destination
            (expand-file-name
             "Emacsvox/Omnivox/releases/1.7.0-windows-x64/flite"
             windows-root))
           (helper (expand-file-name "omnivox-flite-helper.exe" destination)))
      (emacsvox-wsl-install-tests--write-executable helper "#!/bin/sh\n")
      (with-temp-file (expand-file-name "user-file.txt" destination)
        (insert "not owned by the component manager\n"))
      (let ((result
             (emacsvox-wsl-install-tests--call
              installer environment "--uninstall" "flite")))
        (should-not (zerop (car result)))
        (should (string-search "without source provenance" (cadr result)))
        (should (file-exists-p helper))))))

(ert-deftest emacsvox-omnivox-component-uninstaller-recovers-interrupted-removal ()
  "Uninstall completes when an earlier locked helper is the only residue."
  (emacsvox-omnivox-components-tests--with-fixture
      (root installer environment windows-root archive)
    (ignore root archive)
    (let* ((destination
            (expand-file-name
             "Emacsvox/Omnivox/releases/1.7.0-windows-x64/flite"
             windows-root))
           (helper (expand-file-name "omnivox-flite-helper.exe" destination)))
      (emacsvox-wsl-install-tests--write-executable helper "#!/bin/sh\n")
      (let ((result
             (emacsvox-wsl-install-tests--call
              installer environment "--uninstall" "flite")))
        (ert-info ((cadr result))
          (should (zerop (car result))))
        (should (string-search "Completing interrupted removal of Flite"
                               (cadr result)))
        (should-not (file-exists-p destination))))))

(ert-deftest emacsvox-omnivox-component-uninstaller-retries-locked-helper-first ()
  "Transient helper locks do not remove module metadata prematurely."
  (emacsvox-omnivox-components-tests--with-fixture
      (root installer environment windows-root archive)
    (ignore archive)
    (let* ((destination
            (expand-file-name
             "Emacsvox/Omnivox/releases/1.7.0-windows-x64/flite"
             windows-root))
           (helper (expand-file-name "omnivox-flite-helper.exe" destination))
           (provenance (expand-file-name "SOURCE-PROVENANCE.json" destination))
           (counter (expand-file-name "remove-attempts" root))
           (tool-directory tools))
      (emacsvox-wsl-install-tests--write-executable helper "#!/bin/sh\n")
      (with-temp-file provenance
        (insert "{\"source\":\"fixture\"}\n"))
      (emacsvox-wsl-install-tests--write-executable
       (expand-file-name "rm" tool-directory)
       (concat
        "#!/bin/sh\n"
        "for argument do last=$argument; done\n"
        "case $last in\n"
        "  *omnivox-flite-helper.exe)\n"
        "    [ -f \"$EMACSVOX_COMPONENT_TEST_PROVENANCE\" ] || exit 9\n"
        "    count=0\n"
        "    [ ! -f \"$EMACSVOX_COMPONENT_TEST_RM_COUNT\" ] || "
        "count=$(cat \"$EMACSVOX_COMPONENT_TEST_RM_COUNT\")\n"
        "    count=$((count + 1))\n"
        "    printf '%s\\n' \"$count\" >\"$EMACSVOX_COMPONENT_TEST_RM_COUNT\"\n"
        "    [ \"$count\" -ge 3 ] || exit 1\n"
        "    ;;\n"
        "esac\n"
        "exec /bin/rm \"$@\"\n"))
      (emacsvox-wsl-install-tests--write-executable
       (expand-file-name "sleep" tool-directory) "#!/bin/sh\nexit 0\n")
      (setq environment
            (emacsvox-wsl-install-tests--setenv
             environment "EMACSVOX_COMPONENT_TEST_PROVENANCE" provenance)
            environment
            (emacsvox-wsl-install-tests--setenv
             environment "EMACSVOX_COMPONENT_TEST_RM_COUNT" counter))
      (let ((result
             (emacsvox-wsl-install-tests--call
              installer environment "--uninstall" "flite")))
        (ert-info ((cadr result))
          (should (zerop (car result))))
        (should (equal (string-trim
                        (with-temp-buffer
                          (insert-file-contents counter)
                          (buffer-string)))
                       "3"))
        (should-not (file-exists-p destination))))))

(ert-deftest emacsvox-omnivox-component-uninstaller-supports-legacy-install ()
  "A pinned pre-receipt module remains removable using its provenance marker."
  (emacsvox-omnivox-components-tests--with-fixture
      (root installer environment windows-root archive)
    (ignore root archive)
    (let* ((destination
            (expand-file-name
             "Emacsvox/Omnivox/releases/1.7.0-windows-x64/flite"
             windows-root))
           (helper (expand-file-name "omnivox-flite-helper.exe" destination)))
      (emacsvox-wsl-install-tests--write-executable helper "#!/bin/sh\n")
      (with-temp-file (expand-file-name "SOURCE-PROVENANCE.json" destination)
        (insert "{\"source\":\"legacy fixture\"}\n"))
      (let ((result
             (emacsvox-wsl-install-tests--call
              installer environment "--uninstall" "flite")))
        (ert-info ((cadr result))
          (should (zerop (car result))))
        (should-not (file-exists-p destination))))))

(ert-deftest emacsvox-omnivox-component-uninstaller-rejects-wrong-receipt ()
  "Uninstall leaves a managed-looking directory with a mismatched receipt."
  (emacsvox-omnivox-components-tests--with-fixture
      (root installer environment windows-root archive)
    (ignore root archive)
    (let* ((destination
            (expand-file-name
             "Emacsvox/Omnivox/releases/1.7.0-windows-x64/flite"
             windows-root))
           (helper (expand-file-name "omnivox-flite-helper.exe" destination)))
      (emacsvox-wsl-install-tests--write-executable helper "#!/bin/sh\n")
      (with-temp-file (expand-file-name "SOURCE-PROVENANCE.json" destination)
        (insert "{\"source\":\"fixture\"}\n"))
      (with-temp-file (expand-file-name ".emacsvox-component" destination)
        (insert
         "EMACSVOX_OMNIVOX_COMPONENT_RECEIPT=1\n"
         "component=rutts\n"
         "version=1.7.0\n"
         "platform=windows-x64\n"))
      (let ((result
             (emacsvox-wsl-install-tests--call
              installer environment "--uninstall" "flite")))
        (should-not (zerop (car result)))
        (should (string-search "invalid install receipt" (cadr result)))
        (should (file-exists-p helper))))))

(ert-deftest emacsvox-omnivox-component-installer-rejects-bad-checksum ()
  "A checksum mismatch leaves neither a module nor a staging directory."
  (let* ((outer (make-temp-file "emacsvox bad component " t))
         (archive (emacsvox-omnivox-components-tests--make-archive outer))
         (root
          (emacsvox-omnivox-components-tests--make-checkout
           archive (make-string 64 ?a))))
    (unwind-protect
        (let* ((tool-data
                (emacsvox-omnivox-components-tests--make-tools root archive))
               (tools (car tool-data))
               (home (expand-file-name "home" root))
               (windows-root (expand-file-name "windows" root))
               (proc-version (expand-file-name "proc-version" root))
               environment)
          (make-directory home t)
          (with-temp-file proc-version (insert "Microsoft WSL2\n"))
          (emacsvox-omnivox-components-tests--install-core windows-root)
          (setq environment
                (funcall
                 (cdr tool-data)
                 (emacsvox-wsl-install-tests--environment
                  root tools home windows-root proc-version)))
          (let ((result
                 (emacsvox-wsl-install-tests--call
                  (expand-file-name "bin/emacsvox-omnivox-components" root)
                  environment "--install" "flite")))
            (should-not (zerop (car result)))
            (should (string-search "checksum verification failed"
                                   (cadr result)))
            (should-not
             (file-exists-p
              (expand-file-name
               (concat
                "Emacsvox/Omnivox/releases/1.7.0-windows-x64/flite")
               windows-root)))))
      (delete-directory outer t)
      (delete-directory root t))))

(ert-deftest emacsvox-omnivox-components-parse-and-render ()
  "Machine records become accessible rows with readable state and size."
  (let* ((records
          (emacsvox-omnivox-components--parse
           (concat
            "flite\tFlite\tavailable\t2992085\tCompact voice\n"
            "eloquence\tEloquence\truntime-required\t0\tUser runtime\n")))
         (entries (emacsvox-omnivox-components--entries records)))
    (should (= (length records) 2))
    (should (equal (plist-get (car records) :id) "flite"))
    (should (equal (aref (cadar entries) 1) "available"))
    (should (equal (aref (cadar entries) 2) "2.9 MiB"))
    (should (equal (aref (cadadr entries) 1) "runtime required"))))

(ert-deftest emacsvox-omnivox-components-test-result-announces-voices ()
  "A successful voice check reports the count and points to its list."
  (should
   (equal
    (emacsvox-omnivox-components--result-message
     "TGSpeechBox" 'test t
     "Found 154 voices:\n\n en (1 voice):\n  TGSpeechBox Adam [en/adam]\n"
     "finished\n")
    "TGSpeechBox is available with 154 voices. Voice list opened")))

(ert-deftest emacsvox-omnivox-components-uninstall-result-is-concise ()
  "A successful removal has an unambiguous spoken result."
  (should
   (equal
    (emacsvox-omnivox-components--result-message
     "Flite" 'uninstallation t "Uninstalled Flite.\n" "finished\n")
    "Flite uninstalled")))

(ert-deftest emacsvox-omnivox-components-failure-announces-diagnostic ()
  "A failed voice check reports Omnivox's diagnostic, not only its exit code."
  (let ((message
         (emacsvox-omnivox-components--result-message
          "RHVoice" 'test nil
          (concat
           "Error: rhvoice TTS helper is not available: "
           "RHVoice native library was not found\n")
          "exited abnormally with code 1\n")))
    (should (string-search "RHVoice native library was not found" message))
    (should-not (string-search "code 1" message))))

(ert-deftest emacsvox-omnivox-components-failure-ignores-process-marker ()
  "A stderr-process marker does not hide the installer's diagnostic."
  (should
   (string-search
    "its helper is still in use"
    (emacsvox-omnivox-components--result-message
     "Flite" 'uninstallation nil
     (concat
      "emacsvox-omnivox-components: could not remove Flite; "
      "its helper is still in use by an Omnivox session\n\n"
      "Process emacsvox-omnivox-component stderr finished\n")
     "exited abnormally with code 1\n"))))

(ert-deftest emacsvox-omnivox-components-suspends-both-omnivox-streams ()
  "Removal retires speaker and notification streams before deleting files."
  (let* ((speaker (make-pipe-process :name "omnivox speaker fixture"))
         (notifier (make-pipe-process :name "omnivox notifier fixture"))
         retired)
    (unwind-protect
        (cl-progv '(tts-speaker-process tts-notify-process tts-program)
            (list speaker notifier "omnivox")
          (cl-letf (((symbol-function 'tts--retire-process)
                     (lambda (process) (push process retired))))
            (should (emacsvox-omnivox-components--suspend-omnivox))
            (should (equal retired (list speaker notifier)))
            (should-not tts-speaker-process)
            (should-not tts-notify-process)))
      (dolist (process (list speaker notifier))
        (when (process-live-p process)
          (delete-process process))))))

(ert-deftest emacsvox-omnivox-components-restores-omnivox-after-failure ()
  "A failed removal restores the Omnivox stream stopped for file release."
  (let ((output (get-buffer-create
                 emacsvox-omnivox-components--output-buffer))
        restarted)
    (unwind-protect
        (with-temp-buffer
          (cl-letf (((symbol-function
                      'emacsvox-omnivox-components--check-installer)
                     (lambda () "/bin/false"))
                    ((symbol-function
                      'emacsvox-omnivox-components--running-omnivox-p)
                     (lambda () t))
                    ((symbol-function
                      'emacsvox-omnivox-components--suspend-omnivox)
                     (lambda () t))
                    ((symbol-function
                      'emacsvox-omnivox-components--show-output)
                     #'ignore)
                    ((symbol-function
                      'emacsvox-omnivox-components--speak)
                     #'identity)
                    ((symbol-function 'tts-restart)
                     (lambda () (setq restarted t))))
            (let ((process
                   (emacsvox-omnivox-components--start
                    '(:id "flite" :name "Flite")
                    'uninstallation '("--uninstall" "flite"))))
              (while (process-live-p process)
                (accept-process-output process 0.1))
              (accept-process-output process 0.1)
              (should restarted))))
      (when (buffer-live-p output)
        (kill-buffer output)))))

(ert-deftest emacsvox-omnivox-components-output-is-accessible ()
  "Voice and error results use aural dismissal and home navigation."
  (let ((buffer (generate-new-buffer " *Omnivox component result test*")))
    (unwind-protect
        (cl-letf (((symbol-function 'emacsvox-aural-ui-pop-to-buffer)
                   (lambda (candidate) candidate)))
          (with-current-buffer buffer
            (insert "Found 1 voice:\n"))
          (emacsvox-omnivox-components--show-output buffer)
          (with-current-buffer buffer
            (should emacsvox-aural-ui-interface-buffer)
            (should (eq (key-binding (kbd "q")) #'emacsvox-aural-quit))
            (should (eq (key-binding (kbd "h")) #'emacsvox-aural))))
      (kill-buffer buffer))))

(ert-deftest emacsvox-omnivox-components-manager-is-spoken-and-actionable ()
  "The component manager exposes common aural navigation and module actions."
  (with-temp-buffer
    (emacsvox-omnivox-components-mode)
    (dolist
        (binding
         '(("RET" . emacsvox-omnivox-components-activate)
           ("i" . emacsvox-omnivox-components-install)
           ("u" . emacsvox-omnivox-components-uninstall)
           ("t" . emacsvox-omnivox-components-test)
           ("h" . emacsvox-aural)
           ("q" . emacsvox-aural-quit)))
      (should (eq (key-binding (kbd (car binding))) (cdr binding))))))

(ert-deftest emacsvox-omnivox-components-install-requires-explicit-consent ()
  "Installing the selected downloadable module uses its exact manifest ID."
  (with-temp-buffer
    (emacsvox-omnivox-components-mode)
    (setq emacsvox-omnivox-components--records
          '((:id "flite" :name "Flite" :state "available"
             :size 1024 :detail "fixture"))
          tabulated-list-entries
          (emacsvox-omnivox-components--entries
           emacsvox-omnivox-components--records))
    (tabulated-list-print)
    (goto-char (point-min))
    (let (started)
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                ((symbol-function 'emacsvox-omnivox-components--start)
                 (lambda (record operation arguments)
                   (setq started (list record operation arguments)))))
        (emacsvox-omnivox-components-install))
      (should (eq (cadr started) 'installation))
      (should (equal (caddr started) '("--install" "flite"))))))

(ert-deftest emacsvox-omnivox-components-uninstall-requires-explicit-consent ()
  "Uninstalling a managed module requires consent and uses its exact ID."
  (with-temp-buffer
    (emacsvox-omnivox-components-mode)
    (setq emacsvox-omnivox-components--records
          '((:id "flite" :name "Flite" :state "installed"
             :size 1024 :detail "fixture"))
          tabulated-list-entries
          (emacsvox-omnivox-components--entries
           emacsvox-omnivox-components--records))
    (tabulated-list-print)
    (goto-char (point-min))
    (let (started prompt)
      (cl-letf (((symbol-function 'yes-or-no-p)
                 (lambda (text) (setq prompt text) t))
                ((symbol-function 'emacsvox-omnivox-components--start)
                 (lambda (record operation arguments)
                   (setq started (list record operation arguments)))))
        (emacsvox-omnivox-components-uninstall))
      (should (string-search "manually added" prompt))
      (should (eq (cadr started) 'uninstallation))
      (should (equal (caddr started) '("--uninstall" "flite"))))))

(provide 'emacsvox-omnivox-components-tests)
;;; emacsvox-omnivox-components-tests.el ends here
