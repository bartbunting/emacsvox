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

(ert-deftest emacsvox-keymap-prefix-survives-fresh-startup-and-mode-changes ()
  "Supported prefix shapes load in fresh Emacs and retain speech commands."
  (let ((emacs (expand-file-name invocation-name invocation-directory))
        (lisp (expand-file-name "lisp/" emacsvox-keymap-test--repository-directory)))
    (dolist (prefix '("C-e" "C-t" "C-c e" "<f12>" "<f12> <f11>"))
      (with-temp-buffer
        (let ((status
               (call-process
                emacs nil t nil "-Q" "--batch" "-L" lisp
                "--eval"
                (prin1-to-string
                 `(progn
                    (setq load-prefer-newer t emacsvox-prefix (kbd ,prefix))
                    (require 'ert)
                    (require 'emacsvox)
                    (with-temp-buffer
                      (dolist (mode '(text-mode special-mode fundamental-mode))
                        (funcall mode)
                        (should
                         (eq (key-binding (vconcat emacsvox-prefix "e"))
                             'move-end-of-line))
                        (should
                         (eq (key-binding (vconcat emacsvox-prefix "l"))
                             'emacsvox-speak-line)))))))))
          (unless (eq status 0)
            (ert-fail (list prefix (buffer-string)))))))))

(ert-deftest emacsvox-keymap-recovery-preserves-multi-event-conflicts ()
  "Recovery never consumes a command or submap along a repeated prefix."
  (dolist (case '(("C-c e" "C-c" emacsvox-selective-display)
                  ("M-e x" "M-e" emacsvox-epub)
                  ("<f12> <f11>" "<f12> <f11>" ignore)
                  ("<f12> <f11>" "<f12> <f11>" keymap)))
    (pcase-let* ((`(,prefix ,occupied ,binding) case)
                 (emacsvox-prefix (kbd prefix))
                 (global-map (make-sparse-keymap))
                 (saved-global-map (current-global-map))
                 (emacsvox-keymap (copy-keymap emacsvox-keymap))
                 (command (if (eq binding 'keymap) (make-sparse-keymap) binding)))
      (cl-letf (((symbol-function 'emacsvox-keymap) emacsvox-keymap))
        (define-key emacsvox-keymap (kbd occupied) command)
        (unwind-protect
            (progn
              (define-key global-map emacsvox-prefix 'emacsvox-keymap)
              (use-global-map global-map)
              (dotimes (_ 2) (emacsvox-keymap-recover-eol))
              (should (eq (lookup-key emacsvox-keymap (kbd occupied)) command))
              (should (eq (lookup-key emacsvox-keymap "e") 'move-end-of-line)))
          (use-global-map saved-global-map))))))

(ert-deftest emacsvox-keymap-recovery-keeps-uncontested-repeat-shortcuts ()
  "Default, customized single-event and unused repeated prefixes still work."
  (dolist (prefix '("C-e" "C-t" "<f12>" "<f12> <f11>"))
    (let ((emacsvox-prefix (kbd prefix))
          (global-map (make-sparse-keymap))
          (saved-global-map (current-global-map))
          (emacsvox-keymap (copy-keymap emacsvox-keymap)))
      (cl-letf (((symbol-function 'emacsvox-keymap) emacsvox-keymap))
        (unwind-protect
            (progn
              (define-key global-map emacsvox-prefix 'emacsvox-keymap)
              (use-global-map global-map)
              (dotimes (_ 2) (emacsvox-keymap-recover-eol))
              (should
               (eq (lookup-key global-map (vconcat emacsvox-prefix emacsvox-prefix))
                   'move-end-of-line)))
          (use-global-map saved-global-map))))))

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
