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
  "Managed prerequisites alone leave live availability and count unknown."
  (let* ((records
          (emacsvox-omnivox-components--parse
           (concat
            "flite\tFlite\tavailable\t2992085\tCompact voice\n"
            "eloquence\tEloquence\truntime-required\t0\tUser runtime\n")))
         (entries (emacsvox-omnivox-components--entries records)))
    (should (= (length records) 2))
    (should (equal (plist-get (car records) :id) "flite"))
    (should (equal (aref (cadar entries) 1) "Not checked"))
    (should (equal (aref (cadar entries) 2) "Unknown"))
    (should (equal (aref (cadadr entries) 1) "Not checked"))))

(ert-deftest emacsvox-omnivox-components-show-operation-until-completion ()
  "Rows and speech reflect active operations, refresh, success, and failure."
  (dolist (case '((installation "installing" "available" "installed")
                  (uninstallation "uninstalling" "installed" "available")
                  (test "testing" "installed" "installed")))
    (dolist (exit-code '(0 1))
      (let ((output (generate-new-buffer " *component status output*"))
            (tts-speaker-process nil)
            (tts-notify-process nil))
        (unwind-protect
            (with-temp-buffer
              (emacsvox-omnivox-components-mode)
              (let* ((record (list :id "flite" :name "Flite"
                                   :state (nth 2 case) :size 1024 :detail "fixture"))
                     (records (list record
                                    '(:id "piper" :name "Piper" :state "available"
                                      :size 2048 :detail "fixture")))
                     (emacsvox-omnivox-components--output-buffer (buffer-name output))
                     refresh-fails spoken)
                (cl-letf (((symbol-function 'emacsvox-omnivox-components--check-installer)
                           (lambda () "/bin/sh"))
                          ((symbol-function 'emacsvox-omnivox-components--request-records)
                           (lambda ()
                             (setq emacsvox-omnivox-components--records records
                                   emacsvox-omnivox-components--listing-error
                                   (and refresh-fails "fixture refresh failed"))))
                          ((symbol-function 'emacsvox-omnivox-components--running-omnivox-p)
                           #'ignore)
                          ((symbol-function 'emacsvox-omnivox-components--show-output) #'ignore)
                          ((symbol-function 'emacsvox-omnivox-components--speak)
                           (lambda (text) (setq spoken text)))
                          ((symbol-function 'emacsvox-omnivox-components--notice)
                           (lambda (text) (setq spoken text))))
                  (emacsvox-omnivox-components--request-records)
                  (emacsvox-omnivox-components-refresh "flite")
                  (emacsvox-aural-ui-goto-tabulated-column 1)
                  (let ((process (emacsvox-omnivox-components--start
                                  record (car case)
                                  '("-c" "read -r result; exit \"$result\""))))
                    (unwind-protect
                        (progn
                          (should (equal (aref (tabulated-list-get-entry) 1) (cadr case)))
                          (should (string-search (cadr case)
                                                 (emacsvox-omnivox-components-speak-current)))
                          (emacsvox-omnivox-components-refresh)
                          (should (equal (aref (tabulated-list-get-entry) 1) (cadr case)))
                          (should (= (emacsvox-aural-ui-tabulated-column-index) 1))
                          (should (equal (aref (cadr (assoc "piper" tabulated-list-entries)) 1)
                                         "Not checked"))
                          (should-error (emacsvox-omnivox-components--start record 'test nil)
                                        :type 'user-error)
                          (when (zerop exit-code)
                            (setf (plist-get record :state) (nth 3 case)))
                          ;; A failed refresh must also clear the busy label.
                          (setq refresh-fails (and (= exit-code 1) (eq (car case) 'test)))
                          (process-send-string process (format "%d\n" exit-code))
                          (let ((deadline (+ (float-time) 5)))
                            (while (and emacsvox-omnivox-components--process
                                        (< (float-time) deadline))
                              (accept-process-output nil 0.05)))
                          (should-not emacsvox-omnivox-components--process)
                          (should (equal (aref (tabulated-list-get-entry) 1)
                                         "Not checked"))
                          (when (= exit-code 1)
                            (should (string-search "failed" spoken)))
                          (when refresh-fails
                            (emacsvox-omnivox-components--request-records)
                            (should (string-search "refresh failed"
                                                   emacsvox-omnivox-components--listing-error))))
                      (when (process-live-p process)
                        (set-process-sentinel process #'ignore)
                        (delete-process process)))))))
          (kill-buffer output))))))

(ert-deftest emacsvox-omnivox-components-reopening-retains-active-operation ()
  "Reopening the manager retains its installer, displayed state, and selection."
  (let ((buffer (get-buffer-create "*Omnivox Engines*"))
        (process (make-pipe-process :name "component install fixture" :noquery t)))
    (unwind-protect
        (cl-letf (((symbol-function 'emacsvox-omnivox-components--request-records)
                   (lambda () (setq emacsvox-omnivox-components--records
                                    '((:id "flite" :name "Flite" :state "available"
                                       :size 1024 :detail "fixture")))))
                  ((symbol-function 'emacsvox-aural-ui-pop-to-buffer) #'identity))
          (with-current-buffer buffer
            (emacsvox-omnivox-components-mode)
            (setq emacsvox-omnivox-components--process process)
            (process-put process 'emacsvox-component-id "flite")
            (process-put process 'emacsvox-operation 'installation)
            (emacsvox-omnivox-components--request-records)
            (emacsvox-omnivox-components-refresh "flite")
            (emacsvox-aural-ui-goto-tabulated-column 1)
            (emacsvox-omnivox-components--manager-buffer)
            (should (eq emacsvox-omnivox-components--process process))
            (should (equal (aref (tabulated-list-get-entry) 1) "installing"))
            (should (= (emacsvox-aural-ui-tabulated-column-index) 1))
            (should-error (emacsvox-omnivox-components--start nil 'test nil)
                          :type 'user-error)))
      (delete-process process)
      (kill-buffer buffer))))

(ert-deftest emacsvox-omnivox-components-test-result-announces-voices ()
  "A successful voice check reports the count and points to its list."
  (should
   (equal
    (emacsvox-omnivox-components--result-message
     "TGSpeechBox" 'test t
     "Found 154 voices:\n\n en (1 voice):\n  TGSpeechBox Adam [en/adam]\n"
     "finished\n")
    "TGSpeechBox release check found 154 voices. Read last result for details")))

(ert-deftest emacsvox-omnivox-components-uninstall-result-is-concise ()
  "A successful removal has an unambiguous spoken result."
  (should
   (equal
    (emacsvox-omnivox-components--result-message
     "Flite" 'uninstallation t "Uninstalled Flite.\n" "finished\n")
    "Flite removed from the installed release")))

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
          (emacsvox-omnivox-components-mode)
          (cl-letf (((symbol-function
                      'emacsvox-omnivox-components--check-installer)
                     (lambda () "/bin/false"))
                    ((symbol-function 'emacsvox-omnivox-components--request-records)
                     (lambda () nil))
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
                    ((symbol-function
                      'emacsvox-omnivox-components--notice)
                     #'identity)
                    ((symbol-function 'tts-restart)
                     (lambda () (setq restarted t))))
            (let ((process
                   (emacsvox-omnivox-components--start
                    '(:id "flite" :name "Flite")
                    'uninstallation '("--uninstall" "flite"))))
              (let ((deadline (+ (float-time) 3)))
                ;; Service stderr as well as stdout before expecting the
                ;; completion sentinel to restore the stopped speech stream.
                (while (and emacsvox-omnivox-components--process
                            (< (float-time) deadline))
                  (accept-process-output nil 0.05)))
              (should-not emacsvox-omnivox-components--process)
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
    (setq-local emacsvox-omnivox-components--release-operation t)
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
    (setq-local emacsvox-omnivox-components--release-operation t)
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
      (should (string-search "from the installed release" prompt))
      (should (eq (cadr started) 'uninstallation))
      (should (equal (caddr started) '("--uninstall" "flite"))))))

(cl-defmacro emacsvox-omnivox-components-tests--with-inventory (&rest body)
  "Run BODY with distinct main/notification workers and normalized evidence."
  (declare (indent 0))
  `(let ((tts-speaker-process (make-pipe-process :name "engine-main-fixture" :noquery t
                                                :sentinel #'ignore))
         (tts-notify-process (make-pipe-process :name "engine-notify-fixture" :noquery t
                                               :sentinel #'ignore)))
     (unwind-protect
         (with-temp-buffer
           (emacsvox-omnivox-components-mode)
           (setq emacsvox-omnivox-components--records
                 '((:id "eloquence" :name "Eloquence" :state "runtime-required"
                    :size 0 :detail "User runtime prerequisite")))
           (dolist (lane '(main notification))
             (setf (alist-get lane emacsvox-omnivox-components--snapshots)
                   (list :process (if (eq lane 'main) tts-speaker-process tts-notify-process)
                         :inventory
                         (list :received-at (current-time)
                               :engines (copy-tree
                                         '((:engine-id "eloquence" :display-name "Eloquence"
                                            :availability "available" :availability-reason nil
                                            :health "healthy"
                                            :disabled-by-policy nil
                                            :voices ((:voice-id "reed") (:voice-id "shelley")))))))))
           (emacsvox-omnivox-components--render "eloquence")
           ,@body)
       (delete-process tts-speaker-process)
       (delete-process tts-notify-process))))

(ert-deftest emacsvox-omnivox-components-mbrola-missing-and-live-status ()
  "Missing MBROLA stays discoverable; its configuration never implies availability."
  (let ((process-environment (copy-sequence process-environment)))
    (setenv "OMNIVOX_MBROLA_HELPER" nil)
    (cl-letf (((symbol-function 'omnivox-engine-settings--supported-p) (lambda () t)))
      (let* ((engines (emacsvox-omnivox-components--browse-engines nil))
             (mbrola (cl-find "mbrola" engines :test #'equal
                              :key (lambda (engine) (plist-get engine :engine-id)))))
        (should (equal (plist-get mbrola :availability) "Prototype; not configured"))
        (should-not (plist-get mbrola :voices)))
      (setenv "OMNIVOX_MBROLA_HELPER" "C:/prototype/omnivox-mbrola-helper.exe")
      (should (equal (plist-get (emacsvox-omnivox-components--mbrola-placeholder) :availability)
                     "Prototype; not reported")))
    (setenv "OMNIVOX_MBROLA_HELPER" nil)
    (cl-letf (((symbol-function 'omnivox-engine-settings--supported-p) (lambda () nil)))
      (should (equal (plist-get (emacsvox-omnivox-components--mbrola-placeholder) :availability)
                     "Prototype; not reported")))
    (let* ((live '(:engine-id "mbrola" :display-name "MBROLA" :availability "available"
                   :voices ((:voice-id "mbrola:v1/mb-en1/en1"))))
           (engines (emacsvox-omnivox-components--browse-engines (list live))))
      (should (eq live (car engines)))
      (should (= 1 (cl-count "mbrola" engines :test #'equal
                            :key (lambda (engine) (plist-get engine :engine-id))))))))

(ert-deftest emacsvox-omnivox-components-mbrola-details-explain-unmanaged-setup ()
  "Opening the prototype explains setup without offering unsupported management."
  (with-temp-buffer
    (emacsvox-omnivox-components-mode)
    (let* ((rows (emacsvox-omnivox-components--detail-rows "mbrola"))
           (visible (emacsvox-omnivox-components--layout-details rows)))
      (should (equal (aref (cadr (assq 'summary rows)) 0) "MBROLA"))
      (should (assq 'prototype visible))
      (should (string-search "OMNIVOX_MBROLA_HELPER"
                             (aref (cadr (assq 'prototype-setup visible)) 1)))
      (should (assq 'download-voices rows))
      (dolist (action '(install uninstall test))
        (should-not (assq action rows))))))

(ert-deftest emacsvox-omnivox-components-live-discovery-overrides-prerequisite ()
  "Usable runtime discovery is not obscured by a managed bridge prerequisite."
  (emacsvox-omnivox-components-tests--with-inventory
    (should (equal (aref (tabulated-list-get-entry) 1) "Available"))
    (should (equal (aref (tabulated-list-get-entry) 2) "2"))
    (let ((rows (emacsvox-omnivox-components--detail-rows "eloquence")))
      (should (string-search "Found and loaded" (aref (cadr (assq 'main-runtime rows)) 1)))
      (should (string-search "ECI library loaded successfully on both streams"
                             (aref (cadr (assq 'runtime rows)) 1)))
      (should-not (assq 'managed rows))
      (should-not (assq 'scope rows))
      (should-not (assq 'test rows)))))

(ert-deftest emacsvox-omnivox-components-old-or-replaced-worker-is-not-current ()
  "Age requests refresh; only disconnect or replacement invalidates the worker."
  (emacsvox-omnivox-components-tests--with-inventory
    (let* ((record (emacsvox-omnivox-components--record))
           (inventory (plist-get (alist-get 'main emacsvox-omnivox-components--snapshots)
                                 :inventory)))
      (setf (plist-get inventory :received-at) (time-subtract nil 600))
      (should (equal (emacsvox-omnivox-components--state record) "Available"))
      (should (emacsvox-omnivox-components--refresh-due-p 'main))
      (setf (plist-get inventory :received-at) (current-time))
      (should-not (emacsvox-omnivox-components--refresh-due-p 'main))
      (let ((tts-speaker-process tts-notify-process))
        (should (equal (emacsvox-omnivox-components--state record) "Previously available"))
        (let ((rows (emacsvox-omnivox-components--detail-rows "eloquence")))
          (should (string-search "engine-notify-fixture" (aref (cadr (assq 'main-target rows)) 1)))
          (should (string-search "engine-main-fixture" (aref (cadr (assq 'main-source rows)) 1)))))
      (delete-process tts-speaker-process)
      (should (equal (emacsvox-omnivox-components--state record) "Previously available")))))

(ert-deftest emacsvox-omnivox-components-compares-voice-identities-between-streams ()
  "Equal voice counts do not prove the two workers agree."
  (emacsvox-omnivox-components-tests--with-inventory
    (let ((engine (emacsvox-omnivox-components--engine "eloquence" 'notification)))
      (setf (plist-get engine :voices) '((:voice-id "reed") (:voice-id "sandy")))
      (should (equal (emacsvox-omnivox-components--state
                      (emacsvox-omnivox-components--record)) "Streams differ"))
      (setf (plist-get engine :disabled-by-policy) t)
      (should (equal (emacsvox-omnivox-components--lane-state "eloquence" 'notification)
                     "Disabled")))))

(defun emacsvox-omnivox-components-tests--check-details-quit ()
  "Check that two quits leave the engine UI in either window layout."
  (dolist (action '(display-buffer-same-window display-buffer-pop-up-window))
    (emacsvox-omnivox-components-tests--with-inventory
      (let ((manager (current-buffer))
            (origin (generate-new-buffer "*engine quit origin*"))
            (display-buffer-overriding-action (list action))
            details)
        (unwind-protect
            (save-window-excursion
              (delete-other-windows)
              (with-current-buffer manager (rename-buffer "*engine quit manager*" t))
              (switch-to-buffer origin)
              (insert "Return here after closing engines.")
              (cl-letf (((symbol-function 'emacsvox-omnivox-components--speak) #'ignore)
                        ((symbol-function 'emacsvox-aural-ui-speak) #'ignore)
                        ((symbol-function 'emacsvox-aural-ui--speak-feedback) #'ignore))
                ;; Revisit retained buffers to catch stale window return history.
                (dotimes (_ 2)
                  (emacsvox-aural-ui-pop-to-buffer manager)
                  (call-interactively (key-binding (kbd "RET")))
                  (setq details (current-buffer))
                  (should (derived-mode-p 'emacsvox-omnivox-engine-details-mode))
                  (call-interactively (key-binding (kbd "q")))
                  (redisplay t)
                  (should (eq (window-buffer (selected-window)) manager))
                  (should (equal (tabulated-list-get-id) "eloquence"))
                  (call-interactively (key-binding (kbd "q")))
                  (redisplay t)
                  (should (eq (window-buffer (selected-window)) origin))
                  (should (= (point) (point-max)))
                  (should-not (get-buffer-window details))
                  (should-not (get-buffer-window manager)))))
          (dolist (buffer (list details origin))
            (when (buffer-live-p buffer) (kill-buffer buffer))))))))

(ert-deftest emacsvox-omnivox-components-details-quit-does-not-cycle ()
  "Quitting details then engines returns to the original buffer."
  (emacsvox-omnivox-components-tests--check-details-quit))

(ert-deftest emacsvox-omnivox-components-details-retain-focus-and-speak-values ()
  "RET opens details; asynchronous redraw keeps its field, and q returns."
  (emacsvox-omnivox-components-tests--with-inventory
    (let ((manager (current-buffer)) (spoken nil) details)
      (unwind-protect
          (save-window-excursion
            (switch-to-buffer manager)
            (cl-letf (((symbol-function 'emacsvox-omnivox-components--speak) #'identity)
                      ((symbol-function 'emacsvox-aural-ui-speak)
                       (lambda (text) (setq spoken text)))
                      ((symbol-function 'emacsvox-omnivox-components--start)
                       (lambda (&rest _) (ert-fail "Opening details started an operation"))))
              (emacsvox-omnivox-components-activate)
              (setq details (current-buffer))
              (should (derived-mode-p 'emacsvox-omnivox-engine-details-mode))
              (should (eq (tabulated-list-get-id) 'voices))
              (should-not (assq 'main tabulated-list-entries))
              (goto-char (point-min))
              (should (eq (tabulated-list-get-id) 'summary))
              (emacsvox-omnivox-components--speak-detail)
              (should (string-search "Available; 2 voices on both streams" spoken))
              (with-current-buffer manager (emacsvox-omnivox-components--refresh-details))
              (should (eq (current-buffer) details))
              (should (eq (tabulated-list-get-id) 'summary))
              (emacsvox-omnivox-components--details-next-action)
              (should (eq (tabulated-list-get-id) 'voices))
              (emacsvox-omnivox-components--details-back)
              (should (eq (current-buffer) manager))
              (should (equal (tabulated-list-get-id) "eloquence"))))
        (when (buffer-live-p details) (kill-buffer details))))))

(ert-deftest emacsvox-omnivox-components-graphical-details-refresh-preserves-window ()
  "Real redisplay keeps details and the selected action in the same window."
  (skip-unless (display-graphic-p))
  (emacsvox-omnivox-components-tests--check-details-quit)
  (emacsvox-omnivox-components-tests--with-inventory
    (let ((manager (current-buffer)) details)
      (unwind-protect
          (save-window-excursion
            (switch-to-buffer manager)
            (cl-letf (((symbol-function 'emacsvox-omnivox-components--speak) #'identity)
                      ((symbol-function 'emacsvox-aural-ui-speak) #'identity))
              (emacsvox-omnivox-components-activate)
              (setq details (current-buffer))
              (emacsvox-omnivox-components--details-next-action)
              (redisplay t)
              (let ((window (selected-window)) (id (tabulated-list-get-id)))
                (with-current-buffer manager (emacsvox-omnivox-components--refresh-details))
                (redisplay t)
                (should (eq window (selected-window)))
                (should (eq details (window-buffer window)))
                (should (eq id (tabulated-list-get-id)))
                (should (pos-visible-in-window-p (point) window)))
              (should-not (string-search "engine-main-fixture" (buffer-string)))
              (should (emacsvox-aural-ui-goto-row 'diagnostics-section))
              (should (eq 'folded (emacsvox-aural-ui--control-visibility)))
              (call-interactively (key-binding (kbd "RET")))
              (redisplay t)
              (should (eq 'expanded (emacsvox-aural-ui--control-visibility)))
              (should (string-search "engine-main-fixture" (buffer-string)))
              (should (emacsvox-aural-ui-goto-row 'main-time))
              (emacsvox-aural-ui-goto-tabulated-column 1)
              (let ((window (selected-window)))
                (with-current-buffer manager (emacsvox-omnivox-components--refresh-details))
                (redisplay t)
                (should (eq window (selected-window)))
                (should (eq 'main-time (tabulated-list-get-id)))
                (should (= 1 (emacsvox-aural-ui-tabulated-column-index)))
                (should (pos-visible-in-window-p (point))))
              (emacsvox-aural-ui-goto-row 'diagnostics-section)
              (call-interactively (key-binding (kbd "RET")))
              (redisplay t)
              (should (eq 'folded (emacsvox-aural-ui--control-visibility)))
              (should-not (string-search "engine-main-fixture" (buffer-string)))
              (call-interactively (key-binding (kbd "TAB")))
              (should (eq 'back (tabulated-list-get-id)))
              (call-interactively (key-binding (kbd "<backtab>")))
              (should (eq 'diagnostics-section (tabulated-list-get-id)))
              (emacsvox-omnivox-components--details-back)
              (redisplay t)
              (should (equal (tabulated-list-get-id) "eloquence"))
              (should (pos-visible-in-window-p (point)))))
        (when (buffer-live-p details) (kill-buffer details))))))

(ert-deftest emacsvox-omnivox-components-graphical-library-navigation-and-return ()
  "The same browser shows disabled downloads, actions and stable navigation."
  (skip-unless (and (not noninteractive) (display-graphic-p)))
  (emacsvox-omnivox-components-tests--with-inventory
    (setq emacsvox-omnivox-components--records
          '((:id "flite" :name "Flite" :state "installed" :size 0)))
    (emacsvox-omnivox-components--render "flite")
    (let ((manager (current-buffer)) details library receive spoken command
          (index '(:voices [(:engine_id "flite" :physical_id "cmu_us_slt"
                                       :display_name "SLT" :enabled t)
                          (:engine_id "flite" :physical_id "fixture"
                                      :display_name "Test voice" :enabled :false)])))
      (unwind-protect
          (save-window-excursion
            (switch-to-buffer manager)
            (cl-letf (((symbol-function 'emacsvox-omnivox-components--speak) #'ignore)
                      ((symbol-function 'tts-speak) (lambda (text) (setq spoken text)))
                      ((symbol-function 'emacsvox-aural-ui-speak) (lambda (text) (setq spoken text)))
                      ((symbol-function 'tts-voice-inventory) (lambda () '(:adapter "omnivox" :engines nil)))
                      ((symbol-function 'omnivox-library--source-key) (lambda () '(fixture)))
                      ((symbol-function 'omnivox-library--inspect-async)
                       (lambda (callback) (setq receive callback) #'ignore))
                      ((symbol-function 'omnivox-library--service)
                       (lambda (&rest _) (make-pipe-process :name "library UI fixture" :noquery t)))
                      ((symbol-function 'omnivox-library--request)
                       (lambda (_service request) (setq command request) '(:type "library"))))
              (emacsvox-omnivox-components-activate)
              (setq details (current-buffer))
              (should (emacsvox-aural-ui-goto-row 'voices))
              (emacsvox-omnivox-components--details-activate)
              (setq library (current-buffer))
              (should (derived-mode-p 'emacsvox-aural-voice-workbench-mode))
              (should (string-search "Loading library" spoken))
              (funcall receive (list :index index :sha256 "fixture") nil)
              (redisplay t)
              (should (equal (tabulated-list-get-id) '("flite" "cmu_us_slt")))
              (emacsvox-aural-ui-next-row)
              (should (string-search "Test voice" spoken))
              (should (equal (aref (tabulated-list-get-entry) 4) "No"))
              (emacsvox-aural-voice-workbench--library-toggle)
              (should (equal (plist-get command :command) "enable"))
              (should (eq (plist-get command :enabled) t))
              (should (equal (plist-get command :expected_sha256) "fixture"))
              (setf (plist-get (aref (plist-get index :voices) 1) :enabled) t)
              (funcall receive (list :index index :sha256 "new") nil)
              (redisplay t)
              (should (equal (tabulated-list-get-id) '("flite" "fixture")))
              (should (equal (aref (tabulated-list-get-entry) 4) "Yes"))
              (should (equal (aref (tabulated-list-get-entry) 5) "Unknown"))
              (should (pos-visible-in-window-p (point)))
              (should-error (emacsvox-aural-voice-workbench-preview) :type 'user-error)
              (emacsvox-aural-ui-previous-row)
              (should (string-search "SLT" spoken))
              (emacsvox-aural-voice-workbench-quit)
              (redisplay t)
              (should (eq (current-buffer) details))
              (should (eq (tabulated-list-get-id) 'voices))
              (should (pos-visible-in-window-p (point)))))
        (dolist (buffer (list library details))
          (when (buffer-live-p buffer) (kill-buffer buffer)))))))

(ert-deftest emacsvox-omnivox-components-listing-failure-retains-live-engines ()
  "A managed-platform error leaves live discovery accessible and unchanged."
  (emacsvox-omnivox-components-tests--with-inventory
    (let ((program (make-temp-file "engine-listing-" nil ".sh"
                                   "#!/bin/sh\necho unsupported-platform >&2\nexit 1\n")))
      (unwind-protect
          (progn
            (set-file-modes program #o700)
            (let ((emacsvox-omnivox-component-installer program))
              (emacsvox-omnivox-components-refresh)
              (emacsvox-omnivox-components--request-records)
              (let ((deadline (+ (float-time) 3)))
                (while (and emacsvox-omnivox-components--listing-process
                            (< (float-time) deadline))
                  (accept-process-output nil 0.05)))
              (should-not emacsvox-omnivox-components--listing-process)
              (should (string-search "unsupported-platform" emacsvox-omnivox-components--listing-error))
              (should (equal (aref (tabulated-list-get-entry) 1) "Available"))))
        (delete-file program)))))

(ert-deftest emacsvox-omnivox-components-completion-keeps-selection-and-results ()
  "A completed check neither moves the row nor opens or speaks long output."
  (emacsvox-omnivox-components-tests--with-inventory
    (let ((output (generate-new-buffer " *retained engine result*")) notice)
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-omnivox-components--check-installer)
                     (lambda () "/bin/sh"))
                    ((symbol-function 'emacsvox-omnivox-components--request-records) #'ignore)
                    ((symbol-function 'emacsvox-omnivox-components--speak) #'identity)
                    ((symbol-function 'emacsvox-omnivox-components--notice)
                     (lambda (text) (setq notice text)))
                    ((symbol-function 'emacsvox-omnivox-components--show-output)
                     (lambda (&rest _) (ert-fail "Completion stole focus"))))
            (let* ((emacsvox-omnivox-components--output-buffer (buffer-name output))
                   (process (emacsvox-omnivox-components--start
                             (emacsvox-omnivox-components--record) 'test
                             '("-c" "read -r ignored; printf 'Found 2 voices:\\nlong diagnostic\\n'"))))
              (push '(:id "flite" :name "Flite" :state "available" :size 12)
                    emacsvox-omnivox-components--records)
              (emacsvox-omnivox-components--render "flite")
              (process-send-string process "finish\n")
              (let ((deadline (+ (float-time) 3)))
                (while (and emacsvox-omnivox-components--process (< (float-time) deadline))
                  ;; The command has a separate stderr pipe.  Service both
                  ;; pipes so Emacs can deliver its completion sentinel.
                  (accept-process-output nil 0.05)))
              (should-not emacsvox-omnivox-components--process)
              (should (stringp notice))
              (should (equal (tabulated-list-get-id) "flite"))
              (should (< (length notice) 100))
              (should-not (string-search "long diagnostic" notice))
              (emacsvox-omnivox-components-refresh)
              (should (string-search "long diagnostic"
                                     (plist-get (alist-get "eloquence" emacsvox-omnivox-components--results
                                                           nil nil #'equal) :output)))))
        (kill-buffer output)))))

(ert-deftest emacsvox-omnivox-components-listing-success-is-asynchronous ()
  "A successful managed listing refreshes the existing row without native checks."
  (with-temp-buffer
    (emacsvox-omnivox-components-mode)
    (let ((tts-speaker-process nil)
          (tts-notify-process nil)
          (program (make-temp-file "engine-listing-" nil ".sh"
                                   "#!/bin/sh\nprintf 'installation-target\\tOmnivox fixture\\tconfigured\\t0\\t/tmp/release/omnivox.exe\\nflite\\tFlite\\tavailable\\t12\\tFixture\\n'\n")))
      (unwind-protect
          (progn
            (set-file-modes program #o700)
            (let ((emacsvox-omnivox-component-installer program))
              (emacsvox-omnivox-components-refresh)
              (emacsvox-omnivox-components--request-records)
              (should (processp emacsvox-omnivox-components--listing-process))
              (let ((deadline (+ (float-time) 3)))
                (while (and emacsvox-omnivox-components--listing-process
                            (< (float-time) deadline))
                  (accept-process-output nil 0.05)))
              (should-not emacsvox-omnivox-components--listing-process)
              (should-not emacsvox-omnivox-components--listing-error)
              ;; The explanatory prototype row survives the background listing.
              (should (equal (tabulated-list-get-id) "mbrola"))
              (should (emacsvox-aural-ui-goto-row "flite"))
              (should (equal (aref (tabulated-list-get-entry) 1) "Not checked"))))
        (delete-file program)))))

(ert-deftest emacsvox-omnivox-components-captures-each-workers-own-inventory ()
  "Both inventory replies are timed and published without mixing worker data."
  (require 'omnivox-voices)
  (emacsvox-omnivox-components-tests--with-inventory
    (let* ((calls 0)
           (omnivox-engine-inventory nil)
           (omnivox-engine-inventory-time nil)
           (omnivox-routing-policy-registration nil)
           (tts-voice-inventory-changed-hook (list (lambda () (cl-incf calls))))
           (raw '(:type "inventory" :engines
                  ((:id "eloquence" :display_name "Eloquence"
                    :availability (:status "available") :health (:status "healthy")))))
           (notify (copy-tree raw)))
      (setf (plist-get (car (plist-get notify :engines)) :availability)
            '(:status "unavailable" :reason "Runtime failed to load"))
      (cl-letf (((symbol-function 'omnivox--process-supports-p) #'ignore))
        (omnivox--handle-inventory-response tts-speaker-process raw)
        (omnivox--handle-inventory-response tts-notify-process notify))
      (should (= calls 2))
      (should (process-get tts-notify-process 'omnivox-inventory-received-at))
      (emacsvox-omnivox-components--capture-inventory)
      (should (equal (emacsvox-omnivox-components--lane-state "eloquence" 'main) "Available"))
      (should (equal (emacsvox-omnivox-components--lane-state "eloquence" 'notification)
                     "Needs attention")))))

(ert-deftest emacsvox-omnivox-components-details-handle-disappearing-record ()
  "An open detail view survives a record disappearing during async discovery."
  (with-temp-buffer
    (emacsvox-omnivox-components-mode)
    (setq emacsvox-omnivox-components--records
          '((:id "flite" :name "Flite" :state "installed" :size 0)))
    (let ((rows (emacsvox-omnivox-components--detail-rows "information")))
      (should (equal (aref (cadr (assq 'summary rows)) 1) "Not checked"))
      (should-not (assq 'install rows))
      (should-not (assq 'test rows)))))

(ert-deftest emacsvox-omnivox-components-details-prioritize-voice-actions ()
  "Common actions stay visible while diagnostics and disruptive actions collapse."
  (with-temp-buffer
    (emacsvox-omnivox-components-mode)
    (setq emacsvox-omnivox-components--records
          '((:id "flite" :name "Flite" :state "installed" :size 0)))
    (let* ((all (emacsvox-omnivox-components--detail-rows "flite"))
           (visible (emacsvox-omnivox-components--layout-details all)))
      (should (equal (seq-take (mapcar #'car visible) 4)
                     '(summary voices download-voices check-live)))
      (should-not (assq 'uninstall visible))
      (should-not (assq 'main-target visible))
      (let ((emacsvox-omnivox-components--expanded-sections '(module-section)))
        (should-not (assq 'uninstall (emacsvox-omnivox-components--layout-details all)))))
    (let ((rows (emacsvox-omnivox-components--layout-details
                 (emacsvox-omnivox-components--detail-rows "eloquence"))))
      (should-not (assq 'voice-library rows))
      (should-not (assq 'download-voices rows)))
    (setf (alist-get "flite" emacsvox-omnivox-components--results nil nil #'equal)
          (list :operation 'test :success nil :time (current-time) :output "fixture failure"))
    (let ((rows (emacsvox-omnivox-components--layout-details
                 (emacsvox-omnivox-components--detail-rows "flite"))))
      (should (equal (seq-take (mapcar #'car rows) 3) '(summary operation-error output))))))

(ert-deftest emacsvox-omnivox-components-details-refresh-old-evidence-after-announcement ()
  "Old evidence for a running worker remains usable and refreshes after speech."
  (emacsvox-omnivox-components-tests--with-inventory
    (let ((manager (current-buffer)) details events)
      (setf (plist-get (plist-get (alist-get 'main emacsvox-omnivox-components--snapshots)
                                 :inventory) :received-at) (time-subtract nil 600))
      (unwind-protect
          (save-window-excursion
            (switch-to-buffer manager)
            (cl-letf (((symbol-function 'omnivox--process-supports-p) (lambda (&rest _) t))
                      ((symbol-function 'emacsvox-omnivox-components--speak)
                       (lambda (text)
                         (should (string-search "Available; 2 voices on both streams" text))
                         (push 'announcement events)))
                      ((symbol-function 'omnivox-refresh-voice-inventory)
                       (lambda () (push 'inventory-request events))))
              (emacsvox-omnivox-components-activate)
              (setq details (current-buffer))
              (should (equal (reverse events) '(announcement inventory-request)))
              (with-current-buffer manager (emacsvox-omnivox-components--refresh-details))
              (should (= 2 (length events)))
              (should (eq 'voices (tabulated-list-get-id)))))
        (when (buffer-live-p details) (kill-buffer details))))))

(ert-deftest emacsvox-omnivox-components-collapsed-details-expose-speech-problems ()
  "Notification problems remain visible even when diagnostics is collapsed."
  (emacsvox-omnivox-components-tests--with-inventory
    (let ((engine (emacsvox-omnivox-components--engine "eloquence" 'notification)))
      (setf (plist-get engine :availability) "unavailable")
      (setf (plist-get engine :availability-reason) "Runtime could not be loaded")
      (let ((rows (emacsvox-omnivox-components--layout-details
                   (emacsvox-omnivox-components--detail-rows "eloquence"))))
        (should (string-search "notification: Needs attention" (aref (cadr (assq 'summary rows)) 1)))
        (should (equal (aref (cadr (assq 'notification-runtime-status rows)) 1)
                       "Load failed: Runtime could not be loaded"))
        (should-not (assq 'notification-problem rows))
        (should-not (assq 'notification-runtime rows)))
      (delete-process tts-notify-process)
      (setf (plist-get engine :availability) "available")
      (let ((rows (emacsvox-omnivox-components--layout-details
                   (emacsvox-omnivox-components--detail-rows "eloquence"))))
        (should (string-search "notification: Previously available" (aref (cadr (assq 'summary rows)) 1)))
        (should-not (assq 'notification-problem rows))))))

(ert-deftest emacsvox-omnivox-components-locked-removal-is-visible-and-spoken ()
  "The actual completion path exposes a locked helper without hiding live voices."
  (emacsvox-omnivox-components-tests--with-inventory
    (let ((output (generate-new-buffer " *locked helper result*")) notice)
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-omnivox-components--check-installer) (lambda () "/bin/sh"))
                    ((symbol-function 'emacsvox-omnivox-components--request-records) #'ignore)
                    ((symbol-function 'emacsvox-omnivox-components--running-omnivox-p) (lambda () nil))
                    ((symbol-function 'emacsvox-omnivox-components--speak) #'ignore)
                    ((symbol-function 'emacsvox-omnivox-components--notice) (lambda (text) (setq notice text))))
            (let ((emacsvox-omnivox-components--output-buffer (buffer-name output)))
              (emacsvox-omnivox-components--start
               (emacsvox-omnivox-components--record) 'uninstallation
               '("-c" "read -r ignored; echo 'could not remove engine; its helper is still in use by an Omnivox session'; exit 1"))
              (process-send-string emacsvox-omnivox-components--process "finish\n")
              (let ((deadline (+ (float-time) 3)))
                (while (and emacsvox-omnivox-components--process (< (float-time) deadline))
                  (accept-process-output nil 0.05)))
              (should (string-search "removal failed" notice))
              (should (string-search "helper is still in use" notice))
              (should-not (string-search "completed" notice))
              (let* ((rows (emacsvox-omnivox-components--layout-details
                            (emacsvox-omnivox-components--detail-rows "eloquence")))
                     (failure (aref (cadr (assq 'operation-error rows)) 1)))
                (should (string-search "Engine was not removed" failure))
                (should (string-search "helper still in use" failure))
                (should (string-search "Available" (aref (cadr (assq 'summary rows)) 1))))))
        (kill-buffer output)))))

(ert-deftest emacsvox-omnivox-component-target-is-reported-and-pinned ()
  "Show the real release location and reject a changed target before mutation."
  (emacsvox-omnivox-components-tests--with-fixture
      (root installer environment windows-root archive)
    (ignore root archive)
    (let* ((program (emacsvox-omnivox-components-tests--install-core windows-root))
           (listing (emacsvox-wsl-install-tests--call installer environment "--machine-target")))
      (should (zerop (car listing)))
      (with-temp-buffer
        (emacsvox-omnivox-components-mode)
        (emacsvox-omnivox-components--accept-listing (cadr listing))
        (should (equal (plist-get emacsvox-omnivox-components--release-target :detail) program))
        (should-not (cl-find "installation-target" emacsvox-omnivox-components--records
                            :key (lambda (r) (plist-get r :id)) :test #'equal)))
      (let* ((changed (emacsvox-wsl-install-tests--setenv
                       environment "EMACSVOX_COMPONENT_EXPECTED_TARGET" "/another/omnivox.exe"))
             (result (emacsvox-wsl-install-tests--call installer changed "--install" "flite")))
        (should-not (zerop (car result)))
        (should (string-search "installation target changed" (cadr result)))
        (should-not (file-exists-p (expand-file-name "flite" (file-name-directory program)))))
      (let* ((arm (emacsvox-wsl-install-tests--setenv environment "EMACSVOX_WSL_WINDOWS_ARCHITECTURE" "Arm64"))
             (listing (emacsvox-wsl-install-tests--call installer arm "--machine-target")))
        (should (zerop (car listing)))
        (should (string-search "Omnivox 1.7.0 (windows-arm64)" (cadr listing)))
        (should (string-search "1.7.0-windows-arm64/omnivox.exe" (cadr listing)))))))

(ert-deftest emacsvox-omnivox-components-runtime-reasons-and-worker-identity ()
  "Required-runtime status distinguishes failures without using stale workers."
  (emacsvox-omnivox-components-tests--with-inventory
    (let ((engine (emacsvox-omnivox-components--engine "eloquence" 'notification)))
      (setf (plist-get engine :availability) "unavailable")
      (dolist (case '(("ECI library was not found" . "Missing:")
                      ("ECI library failed to load: wrong architecture" . "Load failed:")
                      ("No usable voices were reported" . "Unavailable:")))
        (setf (plist-get engine :availability-reason) (car case))
        (let ((rows (emacsvox-omnivox-components--layout-details
                     (emacsvox-omnivox-components--detail-rows "eloquence"))))
          (should-not (assq 'runtime rows))
          (should (string-search "loaded successfully" (aref (cadr (assq 'main-runtime-status rows)) 1)))
          (should (string-prefix-p (cdr case) (aref (cadr (assq 'notification-runtime-status rows)) 1)))
          (should (string-search (car case) (aref (cadr (assq 'notification-runtime-status rows)) 1)))))
      (setf (plist-get engine :disabled-by-policy) t)
      (should (equal (emacsvox-omnivox-components--runtime-state "eloquence" 'notification)
                     "Disabled; runtime status not established"))
      (setf (plist-get engine :disabled-by-policy) nil
            (plist-get engine :availability) "available")
      (let ((tts-notify-process tts-speaker-process))
        (should (equal (emacsvox-omnivox-components--runtime-state "eloquence" 'notification)
                       "Not checked for current worker")))
      (delete-process tts-notify-process)
      (should (equal (emacsvox-omnivox-components--runtime-state "eloquence" 'notification)
                     "Not checked for current worker")))))

(ert-deftest emacsvox-omnivox-components-dectalk-runtime-is-visible ()
  "Current DECtalk discovery shows its DLL and dictionary without expansion."
  (emacsvox-omnivox-components-tests--with-inventory
    (dolist (lane '(main notification))
      (setf (plist-get (emacsvox-omnivox-components--engine "eloquence" lane) :engine-id) "dectalk"))
    (let ((rows (emacsvox-omnivox-components--layout-details
                 (emacsvox-omnivox-components--detail-rows "dectalk"))))
      (should (equal (seq-take (mapcar #'car rows) 3) '(summary runtime voices)))
      (should (equal (aref (cadr (assq 'runtime rows)) 1)
                     "DLL and dictionary loaded successfully on both streams")))))

(ert-deftest emacsvox-omnivox-components-current-view-never-probes-release ()
  "Opening and refreshing live details never starts the unrelated installer."
  (emacsvox-omnivox-components-tests--with-inventory
    (let ((manager (current-buffer)) details)
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-omnivox-components--request-records)
                     (lambda () (ert-fail "Live details invoked release installer")))
                    ((symbol-function 'emacsvox-omnivox-components--speak) #'ignore)
                    ((symbol-function 'omnivox-refresh-voice-inventory) #'ignore))
            (emacsvox-omnivox-components--show-details "eloquence" manager manager)
            (setq details (current-buffer))
            (emacsvox-omnivox-components--details-refresh)
            (should-not (assq 'managed tabulated-list-entries))
            (should-not (assq 'uninstall tabulated-list-entries))
            (should-not (assq 'test tabulated-list-entries)))
        (when (buffer-live-p details) (kill-buffer details))))))

(ert-deftest emacsvox-omnivox-components-release-operation-keeps-speech-running ()
  "Explicit release removal never retires or restarts the current workers."
  (emacsvox-omnivox-components-tests--with-inventory
    (setq emacsvox-omnivox-components--release-target
          '(:name "Omnivox release" :detail "/tmp/selected/omnivox.exe"))
    (let ((output (generate-new-buffer " *separate release operation*")))
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-omnivox-components--check-installer) (lambda () "/bin/sh"))
                    ((symbol-function 'emacsvox-omnivox-components--request-records) #'ignore)
                    ((symbol-function 'emacsvox-omnivox-components--running-omnivox-p) (lambda () t))
                    ((symbol-function 'emacsvox-omnivox-components--suspend-omnivox)
                     (lambda () (ert-fail "Stopped the current speech workers")))
                    ((symbol-function 'tts-restart) (lambda () (ert-fail "Restarted current speech")))
                    ((symbol-function 'emacsvox-omnivox-components--speak) #'ignore)
                    ((symbol-function 'emacsvox-omnivox-components--notice) #'ignore))
            (let* ((emacsvox-omnivox-components--release-operation t)
                   (emacsvox-omnivox-components--output-buffer (buffer-name output))
                   (process (emacsvox-omnivox-components--start
                             (emacsvox-omnivox-components--record) 'uninstallation
                             '("-c" "read -r done; test \"$EMACSVOX_COMPONENT_EXPECTED_TARGET\" = /tmp/selected/omnivox.exe"))))
              (should (equal (emacsvox-omnivox-components--state (emacsvox-omnivox-components--record)) "Available"))
              (should (assq 'release-progress (emacsvox-omnivox-components--release-rows "eloquence")))
              (process-send-string process "finish\n")
              (let ((deadline (+ (float-time) 3)))
                (while (and emacsvox-omnivox-components--process (< (float-time) deadline))
                  (accept-process-output nil 0.05)))
              (should-not emacsvox-omnivox-components--process)
              (let ((result (alist-get "eloquence" emacsvox-omnivox-components--results nil nil #'equal)))
                (should (plist-get result :success))
                (should (plist-get result :release)))
              (should-not (assq 'result (emacsvox-omnivox-components--detail-rows "eloquence")))
              (should (process-live-p tts-speaker-process))
              (should (process-live-p tts-notify-process))))
        (kill-buffer output)))))

(ert-deftest emacsvox-omnivox-components-graphical-explicit-release-round-trip ()
  "Release actions require selecting their target and preserve live detail focus."
  (skip-unless (display-graphic-p))
  (emacsvox-omnivox-components-tests--with-inventory
    (let ((manager (current-buffer)) details requests started)
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-omnivox-components--release-supported-p) (lambda () t))
                    ((symbol-function 'emacsvox-omnivox-components--speak) #'ignore)
                    ((symbol-function 'emacsvox-aural-ui-speak) #'ignore)
                    ((symbol-function 'emacsvox-omnivox-components--request-records)
                     (lambda ()
                       (cl-incf requests)
                       (emacsvox-omnivox-components--accept-listing
                        (concat "installation-target\tOmnivox test release\tconfigured\t0\t/tmp/other/omnivox.exe\n"
                                "eloquence\tEloquence\truntime-required\t0\tBridge installed\n"))))
                    ((symbol-function 'emacsvox-omnivox-components--start)
                     (lambda (_record operation args)
                       (should emacsvox-omnivox-components--release-operation)
                       (setq started (list operation args)))))
            (setq requests 0)
            (switch-to-buffer manager)
            (emacsvox-omnivox-components-activate)
            (setq details (current-buffer))
            (should (= requests 0))
            (should (emacsvox-aural-ui-goto-row 'release-manager))
            (call-interactively (key-binding (kbd "RET")))
            (redisplay t)
            (should emacsvox-omnivox-components--release-view)
            (should (= requests 1))
            (should (string-search "Omnivox test release" (buffer-string)))
            (should-not (assq 'runtime tabulated-list-entries))
            (should (emacsvox-aural-ui-goto-row 'test))
            (call-interactively (key-binding (kbd "RET")))
            (should (equal started '(test ("--test" "eloquence"))))
            (with-current-buffer manager (emacsvox-omnivox-components--refresh-details))
            (redisplay t)
            (should (eq (current-buffer) details))
            (should (eq (tabulated-list-get-id) 'test))
            (call-interactively (key-binding (kbd "q")))
            (redisplay t)
            (should-not emacsvox-omnivox-components--release-view)
            (should (eq (tabulated-list-get-id) 'release-manager))
            (should (assq 'runtime tabulated-list-entries))
            (should-not (assq 'test tabulated-list-entries))
            (should (pos-visible-in-window-p (point))))
        (when (buffer-live-p details) (kill-buffer details))))))

(provide 'emacsvox-omnivox-components-tests)
;;; emacsvox-omnivox-components-tests.el ends here
