;;; emacsvox-startup-tests.el --- Core startup tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Contract coverage for core Emacsvox startup and mode preparation.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox)

(ert-deftest emacsvox-programming-mode-uses-canonical-tts-state ()
  "Programming-mode setup configures speech through the canonical TTS API."
  (let ((tts-split-caps nil)
        (tts-caps nil)
        (emacsvox-audio-indentation t)
        events)
    (cl-letf
        (((symbol-function 'tts-set-punctuations)
          (lambda (mode) (push (list 'punctuations mode) events)))
         ((symbol-function 'tts-toggle-split-caps)
          (lambda () (push 'split-caps events)))
         ((symbol-function 'tts-toggle-caps)
          (lambda () (push 'caps events)))
         ((symbol-function 'emacsvox-pronounce-refresh-pronunciations)
          (lambda () (push 'pronunciations events)))
         ((symbol-function 'emacsvox-toggle-audio-indentation)
          (lambda () (push 'audio-indentation events))))
      (emacsvox-setup-programming-mode))
    (should
     (equal
      (nreverse events)
      '((punctuations all) split-caps caps pronunciations)))))

(provide 'emacsvox-startup-tests)
;;; emacsvox-startup-tests.el ends here
