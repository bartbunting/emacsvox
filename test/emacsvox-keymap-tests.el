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

(ert-deftest emacsvox-keymap-removes-legacy-tts-prefix-name ()
  "The legacy public prefix name is intentionally unavailable."
  (should-not (boundp 'emacsvox-dtk-submap))
  (should-not (fboundp 'emacsvox-dtk-submap)))

(ert-deftest emacsvox-keymap-uses-live-clipboard-commands ()
  "The Emacsvox clipboard bindings name the implemented commands."
  (should
   (eq
    (lookup-key emacsvox-keymap (kbd "C-M-c"))
    'emacsvox-clipfile-copy))
  (should
   (eq
    (lookup-key emacsvox-keymap (kbd "C-M-y"))
    'emacsvox-clipfile-paste)))

(ert-deftest emacsvox-keymap-exposes-aural-home-and-explanation ()
  "Aural discovery and point diagnosis have stable prefix bindings."
  (should
   (eq
    (lookup-key emacsvox-keymap (kbd "H"))
    'emacsvox-aural))
  (should
   (eq
    (lookup-key emacsvox-keymap (kbd "E"))
    'emacsvox-aural-explain-presentation))
  (should
   (eq
    (key-binding (kbd "C-e H"))
    'emacsvox-aural))
  (should
   (eq
    (key-binding (kbd "C-e E"))
    'emacsvox-aural-explain-presentation)))

(ert-deftest emacsvox-keymap-uses-canonical-tts-commands ()
  "Generic speech bindings use canonical commands; DECtalk remains explicit."
  (dolist
      (binding
       '(("=" . tts-rate-adjust)
         ("," . tts-toggle-punctuation-mode)
         ("." . tts-notify-stop)
         ("C-c" . tts-cloud)
         ("C-j" . tts-set-chunk-separator-syntax)
         ("C" . emacsvox-set-capitalization-presentation)
         ("I" . emacsvox-set-indentation-presentation)
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
         ("i" . emacsvox-toggle-audio-indentation)
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
