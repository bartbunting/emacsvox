;;; emacsvox-keymap-tests.el --- Core keymap tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Contract coverage for the canonical TTS prefix map.

;;; Code:

(require 'ert)
(require 'emacsvox-keymap)

(ert-deftest emacsvox-keymap-uses-canonical-tts-prefix ()
  "The Emacsvox speech prefix selects the canonical TTS submap."
  (should (keymapp emacsvox-tts-submap))
  (should
   (eq (lookup-key emacsvox-keymap "d") 'emacsvox-tts-submap)))

(ert-deftest emacsvox-keymap-retains-legacy-tts-prefix-alias ()
  "The legacy public prefix name resolves to the canonical TTS map."
  (should (eq emacsvox-dtk-submap emacsvox-tts-submap))
  (should
   (eq
    (indirect-function 'emacsvox-dtk-submap)
    (indirect-function 'emacsvox-tts-submap))))

(ert-deftest emacsvox-keymap-uses-canonical-tts-commands ()
  "Generic speech bindings use canonical commands; DECtalk remains explicit."
  (dolist
      (binding
       '(("=" . tts-rate-adjust)
         ("," . tts-toggle-punctuation-mode)
         ("." . tts-notify-stop)
         ("C-c" . tts-cloud)
         ("C-j" . tts-set-chunk-separator-syntax)
         ("d" . tts-select-server)
         ("L" . tts-local-server)
         ("N" . tts-set-next-language)
         ("P" . tts-set-previous-language)
         ("R" . tts-reset-state)
         ("S" . tts-set-language)
         ("SPC" . tts-toggle-splitting-on-white-space)
         ("a" . tts-add-cleanup-pattern)
         ("c" . tts-toggle-caps)
         ("f" . tts-set-character-scale)
         ("n" . tts-toggle-speak-nonprinting-chars)
         ("o" . tts-toggle-strip-octals)
         ("p" . tts-set-punctuations)
         ("q" . tts-toggle-quiet)
         ("r" . tts-set-rate)
         ("s" . tts-toggle-split-caps)))
    (should
     (eq
      (lookup-key emacsvox-tts-submap (kbd (car binding)))
      (cdr binding))))
  (dotimes (level 10)
    (should
     (eq
      (lookup-key emacsvox-tts-submap (number-to-string level))
      'tts-set-predefined-rate)))
  (should
   (eq (lookup-key emacsvox-tts-submap (kbd "C-d")) 'dectalk))
  (should
   (eq (lookup-key emacsvox-tts-submap (kbd "C-s")) 'dectalk-soft)))

(provide 'emacsvox-keymap-tests)
;;; emacsvox-keymap-tests.el ends here
