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
