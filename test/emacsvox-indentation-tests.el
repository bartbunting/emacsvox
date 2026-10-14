;;; emacsvox-indentation-tests.el --- Indentation menu tests -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Exercise scope, previews, persistence, and real Transient interaction.

;;; Code:
(require 'ert)
(require 'emacsvox-indentation)

(defmacro emacsvox-test--with-indentation-menu (&rest body)
  "Run BODY with isolated defaults and an indentation source buffer."
  (declare (indent 0) (debug t))
  `(let* ((symbols '(emacsvox-audio-indentation emacsvox-indentation-presentation
                    emacsvox-indentation-tone-timing tts-main-tone-volume))
          (defaults (mapcar (lambda (symbol) (cons symbol (default-value symbol))) symbols))
          (properties (mapcar (lambda (symbol) (cons symbol (copy-tree (symbol-plist symbol)))) symbols))
          (native-comp-enable-subr-trampolines nil))
     (unwind-protect
         (progn
           (set-default 'emacsvox-audio-indentation nil)
           (set-default 'emacsvox-indentation-presentation 'spoken)
           (set-default 'emacsvox-indentation-tone-timing 'overlay)
           (set-default 'tts-main-tone-volume 50)
           (with-temp-buffer
             (setq-local emacsvox-indentation-presentation 'spoken)
             (setq-local emacsvox-indentation-tone-timing 'overlay)
             (let* ((source (current-buffer))
                    (transient--prefix
                     (transient-prefix :command 'emacsvox-indentation
                                       :scope (cons source nil))))
               (cl-letf (((symbol-function 'emacsvox-aural-submit) #'ignore)
                         ((symbol-function 'emacsvox-aural-submit-actions) #'ignore)
                         ((symbol-function 'tts-stop) #'ignore)
                         ((symbol-function 'tts--omnivox-program-p) (lambda () nil)))
                 ,@body))))
       (dolist (entry defaults) (set-default (car entry) (cdr entry)))
       (dolist (entry properties) (setplist (car entry) (cdr entry))))))

(ert-deftest emacsvox-indentation-menu-targets-source-buffer ()
  "Actions in another buffer still change only the captured source."
  (emacsvox-test--with-indentation-menu
    (with-temp-buffer
      (emacsvox-indentation--set 'emacsvox-indentation-presentation 'pitch-tone "Pitch tone")
      (should (eq emacsvox-indentation-presentation 'spoken))
      (should (eq (emacsvox-indentation--value 'emacsvox-indentation-presentation) 'pitch-tone)))
    (should (eq emacsvox-indentation-presentation 'pitch-tone))
    (should (eq (default-value 'emacsvox-indentation-presentation) 'spoken))
    (emacsvox-indentation--toggle)
    (should emacsvox-audio-indentation)
    (should-not (default-value 'emacsvox-audio-indentation))))

(ert-deftest emacsvox-indentation-menu-global-preserves-local-choices ()
  "Global edits affect inheriting buffers and preserve explicit local choices."
  (emacsvox-test--with-indentation-menu
    (emacsvox-indentation--scope)
    (emacsvox-indentation--set 'emacsvox-indentation-presentation 'duration-tone "Duration tone")
    (emacsvox-indentation--set 'emacsvox-indentation-tone-timing 'insert "Before speech")
    (should (eq emacsvox-indentation-presentation 'spoken))
    (should (eq emacsvox-indentation-tone-timing 'overlay))
    (with-temp-buffer
      (should (eq emacsvox-indentation-presentation 'duration-tone))
      (should (eq emacsvox-indentation-tone-timing 'insert)))
    (should (emacsvox-indentation--tonal-p))
    (emacsvox-indentation--scope)
    (should-not (emacsvox-indentation--tonal-p))))

(ert-deftest emacsvox-indentation-menu-preview-uses-displayed-scope ()
  "Global previews use defaults without altering the local presentation."
  (emacsvox-test--with-indentation-menu
    (emacsvox-indentation--scope)
    (emacsvox-indentation--set 'emacsvox-indentation-presentation 'pitch-tone "Pitch tone")
    (emacsvox-indentation--set 'emacsvox-indentation-tone-timing 'insert "Before speech")
    (let (text)
      (cl-letf (((symbol-function 'tts-speak) (lambda (value) (setq text value))))
        (with-temp-buffer (emacsvox-indentation--preview)))
      (let ((facts (get-text-property 4 emacsvox-aural-facts-property text)))
        (should (eq (plist-get facts :indentation-presentation) 'pitch-tone))
        (should (eq (plist-get facts :indentation-tone-timing) 'insert))))
    (should-not emacsvox-audio-indentation)
    (should (eq emacsvox-indentation-presentation 'spoken))
    (should (eq emacsvox-indentation-tone-timing 'overlay))))

(ert-deftest emacsvox-indentation-menu-volume-is-global-and-bounded ()
  "Volume changes use Customize in either scope and stay in the valid range."
  (emacsvox-test--with-indentation-menu
    (emacsvox-indentation--volume -5)
    (should (= (default-value 'tts-main-tone-volume) 45))
    (emacsvox-indentation--scope)
    (emacsvox-indentation--volume 5)
    (should (= (default-value 'tts-main-tone-volume) 50))
    (emacsvox-indentation--volume -100)
    (should (= (default-value 'tts-main-tone-volume) 0))
    (emacsvox-indentation--volume 200)
    (should (= (default-value 'tts-main-tone-volume) 100))
    (cl-letf (((symbol-function 'read-number) (lambda (&rest _) 101)))
      (should-error (emacsvox-indentation--volume) :type 'user-error))
    (should (= (default-value 'tts-main-tone-volume) 100))))

(ert-deftest emacsvox-indentation-menu-feedback-replaces-main-speech ()
  "Volume, scope, and enable changes interrupt previous main feedback."
  (let ((submit (symbol-function 'emacsvox-aural-submit)))
    (emacsvox-test--with-indentation-menu
      (let (submissions)
        (cl-letf (((symbol-function 'tts-speak) #'ignore)
                  ((symbol-function 'emacsvox-aural-submit)
                   (lambda (&rest args)
                     (push (apply submit args) submissions))))
          (emacsvox-indentation--volume -5)
          (emacsvox-indentation--volume -5)
          (emacsvox-indentation--volume 5)
          (emacsvox-indentation--scope)
          (emacsvox-indentation--toggle))
        (should (equal (mapcar #'emacsvox-aural-submission-content
                              (reverse submissions))
                       '("45 percent" "40 percent" "45 percent"
                         "Editing global defaults" "Indentation on")))
        (dolist (submission submissions)
          (should (eq (emacsvox-aural-submission-lane submission) 'main))
          (should (eq (emacsvox-aural-submission-delivery-policy submission)
                      'replaceable))
          (should (eq (emacsvox-aural-submission-replacement-key submission)
                      'speaker))
          (should (eq (emacsvox-aural-submission-interruption-policy submission)
                      'lane)))))))

(ert-deftest emacsvox-indentation-menu-save-does-not-promote-local-settings ()
  "Saving persists global values, never the source buffer's local overrides."
  (emacsvox-test--with-indentation-menu
    (setq-local emacsvox-indentation-presentation 'pitch-tone)
    (let (saved)
      (cl-letf (((symbol-function 'customize-save-variable)
                 (lambda (symbol value &rest _) (push (cons symbol value) saved))))
        (should-error (emacsvox-indentation--save) :type 'user-error)
        (should-not saved)
        (emacsvox-indentation--scope)
        (emacsvox-indentation--save))
      (should (equal (nreverse saved)
                     '((emacsvox-audio-indentation)
                       (emacsvox-indentation-presentation . spoken)
                       (emacsvox-indentation-tone-timing . overlay)
                       (tts-main-tone-volume . 50)))))
    (should (eq emacsvox-indentation-presentation 'pitch-tone))))

(ert-deftest emacsvox-indentation-menu-saved-defaults-reload ()
  "Saved settings restore through Customize without persisting local choices."
  (emacsvox-test--with-indentation-menu
    (let* ((custom-file (make-temp-file "emacsvox-indentation-custom-" nil ".el"))
           (user-init-file custom-file))
      (unwind-protect
          (progn
            (emacsvox-indentation--scope)
            (emacsvox-indentation--set 'emacsvox-indentation-presentation 'duration-tone "Duration tone")
            (emacsvox-indentation--set 'emacsvox-indentation-tone-timing 'insert "Before speech")
            (emacsvox-indentation--toggle)
            (emacsvox-indentation--volume -5)
            (emacsvox-indentation--save)
            (set-default 'emacsvox-audio-indentation nil)
            (set-default 'emacsvox-indentation-presentation 'spoken)
            (set-default 'emacsvox-indentation-tone-timing 'overlay)
            (set-default 'tts-main-tone-volume 100)
            (load custom-file nil t)
            (should (default-value 'emacsvox-audio-indentation))
            (should (eq (default-value 'emacsvox-indentation-presentation) 'duration-tone))
            (should (eq (default-value 'emacsvox-indentation-tone-timing) 'insert))
            (should (= (default-value 'tts-main-tone-volume) 45))
            (should (eq emacsvox-indentation-presentation 'spoken)))
        (delete-file custom-file)))))

(ert-deftest emacsvox-indentation-menu-closed-source-refuses-mutations ()
  "A menu whose source has died cannot change global settings."
  (emacsvox-test--with-indentation-menu
    (emacsvox-indentation--scope)
    (let ((dead (generate-new-buffer " *closed indentation source*")))
      (kill-buffer dead)
      (setcar (oref transient--prefix scope) dead))
    (should-error (emacsvox-indentation--set 'emacsvox-indentation-presentation 'pitch-tone "Pitch tone") :type 'user-error)
    (should-error (emacsvox-indentation--volume 5) :type 'user-error)
    (should-error (emacsvox-indentation--save) :type 'user-error)
    (should (eq (default-value 'emacsvox-indentation-presentation) 'spoken))
    (should (= (default-value 'tts-main-tone-volume) 50))))

(ert-deftest emacsvox-indentation-menu-graphical-shortcuts-and-scope ()
  "Real menu keys retain the source, refresh choices, and honour C-u."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (emacsvox-test--with-indentation-menu
      (switch-to-buffer source)
      (insert "source text")
      (goto-char 4)
      (local-set-key (kbd "<f8>") #'emacsvox-indentation)
      (let ((transient--prefix nil)
            (transient-show-menu 0)
            (transient-values nil)
            (transient-history nil)
            (transient-history-file nil)
            (transient-save-history nil)
            preview)
        (cl-letf (((symbol-function 'tts-speak) (lambda (text) (setq preview text))))
          (unwind-protect
              (progn
                (execute-kbd-macro (kbd "<f8>"))
                (transient--show)
                (should-not (cdr (emacsvox-indentation--state)))
                (execute-kbd-macro (kbd "p b - SPC"))
                (should transient--prefix)
                (should (eq (buffer-local-value 'emacsvox-indentation-presentation source) 'pitch-tone))
                (should (eq (buffer-local-value 'emacsvox-indentation-tone-timing source) 'insert))
                (should (= (default-value 'tts-main-tone-volume) 45))
                (should preview)
                (with-current-buffer (window-buffer transient--window)
                  (should (string-match-p "Pitch tone (selected)" (buffer-string)))
                  (should (string-match-p "Before speech (selected)" (buffer-string))))
                (execute-kbd-macro (kbd "s"))
                (should (oref (seq-find (lambda (suffix) (equal (oref suffix key) "b")) transient--suffixes) inapt))
                (execute-kbd-macro (kbd "<down> <down> <up> q"))
                (should-not transient--prefix)
                (should (eq (current-buffer) source))
                (should (= (point) 4))
                (execute-kbd-macro (kbd "C-u <f8>"))
                (should (cdr (emacsvox-indentation--state)))
                (execute-kbd-macro (kbd "d a q"))
                (should (eq (default-value 'emacsvox-indentation-presentation) 'duration-tone))
                (should (eq (buffer-local-value 'emacsvox-indentation-presentation source) 'spoken))
                (should (= (point) 4)))
            (when transient--prefix (execute-kbd-macro (kbd "C-g")))))))))

(ert-deftest emacsvox-indentation-menu-navigation-cues-follow-active-choice ()
  "Movement cues distinguish section changes and the current scoped choice."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (emacsvox-test--with-indentation-menu
      (switch-to-buffer source)
      (use-local-map (make-sparse-keymap))
      (local-set-key (kbd "<f8>") #'emacsvox-indentation)
      (let ((emacsvox-transient-verbose-descriptions nil)
            (emacsvox-transient-navigation-style 'continuous)
            (transient--prefix nil)
            (transient-show-menu 0)
            selections cues toggles)
        (cl-letf (((symbol-function 'emacsvox-aural-submit)
                   (lambda (content &rest arguments)
                     (when (eq (plist-get (plist-get arguments :facts)
                                         :command-menu-action)
                               'focus-button)
                       (push (substring-no-properties content) selections)
                       (push (mapcar #'emacsvox-aural-compatibility-action-value
                                     (plist-get arguments :compatibility-actions))
                             cues))
                     (when (member (substring-no-properties content)
                                   '("Indentation on" "Indentation off"))
                       (push (mapcar #'emacsvox-aural-compatibility-action-value
                                     (plist-get arguments :compatibility-actions))
                             toggles)))))
          (unwind-protect
              (progn
                (execute-kbd-macro (kbd "<f8>"))
                (transient--show)
                (execute-kbd-macro (kbd "<down> <down>"))
                (should (equal (car selections) "Indentation: off. e."))
                (should (equal (car cues) '(off)))
                (execute-kbd-macro (kbd "e <up> <down>"))
                (should (equal (car selections) "Indentation: on. e."))
                (should (equal (car cues) '(on)))
                (should (equal (car toggles) '(on)))
                (execute-kbd-macro (kbd "e <up> <down>"))
                (should (equal (car selections) "Indentation: off. e."))
                (should (equal (car cues) '(off)))
                (should (equal (car toggles) '(off)))
                (execute-kbd-macro (kbd "<down>"))
                (should (equal (car selections)
                               "Spoken column (selected). s. Presentation. 2 of 5 sections."))
                (should (equal (car cues) '(section)))
                (execute-kbd-macro (kbd "<down>"))
                (should (equal (car selections) "Pitch tone. p."))
                (should-not (car cues))
                (execute-kbd-macro (kbd "<up>"))
                (should (equal (car cues) '(select-object)))
                (execute-kbd-macro (kbd "p <down>"))
                (should (equal (car selections) "Pitch tone (selected). p."))
                (should (equal (car cues) '(select-object)))
                (execute-kbd-macro (kbd "g <up> <down>"))
                (should (equal (car selections) "Pitch tone. p."))
                (should-not (car cues)))
            (when transient--prefix (execute-kbd-macro (kbd "C-g")))))))))

(ert-deftest emacsvox-indentation-menu-graphical-shift-arrows-adjust-volume ()
  "Shift arrows adjust only Volume; plain arrows navigate and prompts keep their keys."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (emacsvox-test--with-indentation-menu
      (switch-to-buffer source)
      (insert "source text")
      (goto-char 4)
      (use-local-map (make-sparse-keymap))
      (local-set-key (kbd "<f8>") #'emacsvox-indentation)
      (local-set-key (kbd "S-<left>") #'backward-char)
      (local-set-key (kbd "S-<right>") #'forward-char)
      (let ((transient--prefix nil)
            (transient--stack nil)
            (transient-show-menu t)
            (shift-select-mode t)
            submissions minibuffer-keys preview)
        (cl-letf (((symbol-function 'emacsvox-aural-submit)
                   (lambda (text &rest arguments)
                     (push (cons text arguments) submissions)))
                  ((symbol-function 'tts-speak)
                   (lambda (text) (setq preview text))))
          (unwind-protect
              (progn
                (execute-kbd-macro (kbd "<f8>"))
                (should (cl-some (lambda (entry)
                                   (string-match-p "Shift left and right: adjust volume"
                                                   (car entry))) submissions))
                (execute-kbd-macro (kbd "<down>"))
                (setq submissions nil)
                (execute-kbd-macro (kbd "S-<right>"))
                (should (= (length submissions) 1))
                (should (string-prefix-p "Not adjustable" (caar submissions)))
                (should (= (default-value 'tts-main-tone-volume) 50))
                (execute-kbd-macro (kbd "<right> <right> <right>"))
                (with-selected-window transient--window
                  (should (eq (oref (button-get (button-at (point)) 'button-data) command)
                              'emacsvox-indentation--volume)))
                (setq submissions nil)
                (execute-kbd-macro (kbd "S-<left> S-<left> S-<right>"))
                (should (= (default-value 'tts-main-tone-volume) 45))
                (should (equal (mapcar #'car (reverse submissions))
                               '("45 percent" "40 percent" "45 percent")))
                (dolist (entry submissions)
                  (should (eq (plist-get (cdr entry) :lane) 'main))
                  (should (eq (plist-get (cdr entry) :delivery-policy) 'replaceable))
                  (should (eq (plist-get (cdr entry) :interruption-policy) 'lane)))
                (with-selected-window transient--window
                  (should (string-match-p "Volume: 45 percent" (button-label (button-at (point))))))
                (set-default 'tts-main-tone-volume 0)
                (execute-kbd-macro (kbd "S-<left>"))
                (should (= (default-value 'tts-main-tone-volume) 0))
                (should (equal (caar submissions) "0 percent"))
                (set-default 'tts-main-tone-volume 100)
                (execute-kbd-macro (kbd "S-<right>"))
                (should (= (default-value 'tts-main-tone-volume) 100))
                (should (equal (caar submissions) "100 percent"))
                (minibuffer-with-setup-hook
                    (lambda ()
                      (add-hook 'pre-command-hook
                                (lambda ()
                                  (setq minibuffer-keys
                                        (list (key-binding (kbd "S-<left>"))
                                              (key-binding (kbd "S-<right>")))))
                                nil t))
                  (execute-kbd-macro (kbd "RET RET")))
                (should minibuffer-keys)
                (should-not (memq 'emacsvox-indentation--decrease minibuffer-keys))
                (should-not (memq 'emacsvox-indentation--increase minibuffer-keys))
                (execute-kbd-macro (kbd "SPC"))
                (should preview)
                (should (eq (oref transient--prefix command) 'emacsvox-indentation))
                (should (= (point) 4))
                (should-not mark-active)
                (execute-kbd-macro (kbd "q"))
                (should-not transient--prefix)
                (should (eq (key-binding (kbd "S-<left>")) 'backward-char))
                (should (eq (key-binding (kbd "S-<right>")) 'forward-char))
                (should (= (point) 4)))
            (when transient--prefix (execute-kbd-macro (kbd "C-q")))))))))

(ert-deftest emacsvox-indentation-menu-graphical-adjustment-bindings-stay-local ()
  "Linked parents retain section arrows and never inherit adjustment bindings."
  (skip-unless (display-graphic-p))
  (require 'emacsvox-aural-menu)
  (save-window-excursion
    (emacsvox-test--with-indentation-menu
      (switch-to-buffer source)
      (use-local-map (make-sparse-keymap))
      (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
      (let ((transient--prefix nil)
            (transient--stack nil))
        (unwind-protect
            (progn
              (execute-kbd-macro (kbd "<f8> s i"))
              (should (eq (key-binding (kbd "S-<left>")) 'emacsvox-indentation--decrease))
              (should (eq (key-binding (kbd "S-<right>")) 'emacsvox-indentation--increase))
              (should (eq (key-binding (kbd "<left>")) 'emacsvox-transient-previous-section))
              (should (eq (key-binding (kbd "<right>")) 'emacsvox-transient-next-section))
              (execute-kbd-macro (kbd "q"))
              (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-speech))
              (should (eq (key-binding (kbd "S-<left>")) 'emacsvox-aural-menu--rate-decrease))
              (should (eq (key-binding (kbd "S-<right>")) 'emacsvox-aural-menu--rate-increase))
              (should (eq (key-binding (kbd "<right>")) 'emacsvox-transient-next-section))
              (should-not (string-match-p "adjust volume" (emacsvox-transient--opening-text)))
              (execute-kbd-macro (kbd "q"))
              (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))
              (should-not (lookup-key transient--transient-map (kbd "S-<left>")))
              (should-not (lookup-key transient--transient-map (kbd "S-<right>"))))
          (when transient--prefix (execute-kbd-macro (kbd "C-q"))))))))

(provide 'emacsvox-indentation-tests)
;;; emacsvox-indentation-tests.el ends here
