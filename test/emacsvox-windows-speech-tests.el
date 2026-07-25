;;; emacsvox-windows-speech-tests.el --- Windows speech tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for native Windows speech server discovery and selection.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-windows-speech)

(ert-deftest emacsvox-windows-speech-resolves-friendly-server-name ()
  "Friendly server names resolve to launchers outside Emacsvox."
  (let ((emacsvox-windows-speech-servers-directory "/support/servers/"))
    (cl-letf (((symbol-function 'file-executable-p) (lambda (_file) t)))
      (should
       (equal
        (emacsvox-windows-speech--resolve-server-arguments
         '("windows-outloud"))
        '("/support/servers/windows-outloud"))))))

(ert-deftest emacsvox-windows-speech-leaves-other-server-names-alone ()
  "Bundled server names pass through without translation."
  (let ((emacsvox-windows-speech-servers-directory "/support/servers/"))
    (should
     (equal
      (emacsvox-windows-speech--resolve-server-arguments '("dtk-soft"))
      '("dtk-soft")))))

(ert-deftest emacsvox-windows-speech-rejects-unavailable-server ()
  "Selecting a configured but unavailable Windows server is explicit."
  (let ((emacsvox-windows-speech-servers-directory "/support/servers/"))
    (cl-letf (((symbol-function 'file-executable-p) (lambda (_file) nil)))
      (should-error
       (emacsvox-windows-speech--resolve-server-arguments
        '("windows-dtk"))
       :type 'user-error))))

(ert-deftest emacsvox-windows-speech-registers-only-available-servers ()
  "Completion includes only executable native Windows launchers."
  (let ((tts-servers-alist '("dtk-soft"))
        (emacsvox-windows-speech-servers-directory "/support/servers/")
        (emacsvox-windows-speech--added-server-names nil))
    (cl-letf (((symbol-function 'file-executable-p)
               (lambda (file)
                 (string-suffix-p "windows-outloud" file))))
      (emacsvox-windows-speech--register-server-names)
      (should
       (equal tts-servers-alist '("dtk-soft" "windows-outloud")))
      (should
       (equal emacsvox-windows-speech--added-server-names
              '("windows-outloud"))))))

(provide 'emacsvox-windows-speech-tests)

;;; emacsvox-windows-speech-tests.el ends here
