;;; emacsvox-keymap-tests.el --- Core keymap tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Contract coverage for the canonical TTS prefix map.

;;; Code:

(require 'ert)
(require 'emacsvox-keymap)

(defconst emacsvox-keymap-test--repository-directory
  (file-name-as-directory
   (expand-file-name
    "../" (file-name-directory (or load-file-name buffer-file-name))))
  "Repository root used by keymap documentation checks.")

(defun emacsvox-keymap-test--basic-usage-bindings ()
  "Return key/command pairs published by the Basic Usage starter tables."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name
      "docs/manual/chapters/basic-usage.org"
      emacsvox-keymap-test--repository-directory))
    (goto-char (point-min))
    (let (bindings)
      (while (re-search-forward "^# basic-usage-live-keys-begin$" nil t)
        (let ((start (line-beginning-position 2)))
          (unless
              (re-search-forward "^# basic-usage-live-keys-end$" nil t)
            (ert-fail "Unterminated Basic Usage live-key table"))
          (let ((end (match-beginning 0)))
            (save-excursion
              (goto-char start)
              (while (re-search-forward "^- \\([^\n]+\\) ::$" end t)
                (let ((key (match-string-no-properties 1))
                      (item-end
                       (save-excursion
                         (if (re-search-forward "^- [^\n]+ ::$" end t)
                             (match-beginning 0)
                           end))))
                  (unless (re-search-forward "^  ~\\([^~\n]+\\)~$" item-end t)
                    (ert-fail "Missing command for documented key %s" key))
                  (push
                   (cons key (intern (match-string-no-properties 1)))
                   bindings)))))))
      (nreverse bindings))))

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

(ert-deftest emacsvox-basic-usage-key-bindings-match-the-live-keymap ()
  "Every key/command pair in the starter guide should match the live map."
  (let ((bindings (emacsvox-keymap-test--basic-usage-bindings))
        documented-commands)
    (should bindings)
    (dolist (binding bindings)
      (pcase-let ((`(,key . ,command) binding))
        (should (commandp command))
        (should (eq (key-binding (kbd key)) command))
        (push command documented-commands)))
    (dolist
        (essential
         '(emacsvox-speak-char
           emacsvox-speak-word
           emacsvox-speak-line
           emacsvox-speak-paragraph
           emacsvox-speak-page
           emacsvox-speak-region
           emacsvox-speak-rest-of-buffer
           emacsvox-speak-buffer
           tts-stop
           emacsvox-toggle-show-point
           what-line))
      (should (memq essential documented-commands)))))

(ert-deftest emacsvox-basic-usage-points-to-live-and-generated-help ()
  "Conceptual key guidance should lead to current, authoritative bindings."
  (dolist
      (relative-name
       '("docs/manual/chapters/basic-usage.org"
         "docs/manual/chapters/keyboard.org"))
    (let ((guide
           (with-temp-buffer
             (insert-file-contents
              (expand-file-name
               relative-name emacsvox-keymap-test--repository-directory))
             (buffer-string))))
      (should
       (string-match-p
        "@ref{Emacsvox Keymaps,,,emacsvox-reference" guide))
      (should (string-match-p (regexp-quote "@kbd{C-h m}") guide))
      (should (string-match-p (regexp-quote "@kbd{C-h k}") guide)))))

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
         ("D" . emacsvox-aural-toggle-diagnostic-logging)
         ("I" . emacsvox-set-indentation-presentation)
         ("d" . tts-select-server)
         ("e" . emacsvox-aural-prefer-engine)
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
   (eq (lookup-key emacsvox-tts-submap (kbd "C-s")) 'dectalk-soft))
  (should
   (eq
    (key-binding (kbd "C-e d D"))
    'emacsvox-aural-toggle-diagnostic-logging)))

(provide 'emacsvox-keymap-tests)
;;; emacsvox-keymap-tests.el ends here
