;;; emacsvox-eat-input.el --- EAT interactive input feedback  -*- lexical-binding: t; -*-
;;; $Author: tv.raman.tv $
;;; Keywords: Emacsvox, Audio Desktop, eat

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; All Rights Reserved.
;;
;; This file is not part of GNU Emacs, but the same permissions apply.
;;
;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:
;; Input, navigation, deletion, paste, mode, and completion feedback for EAT.
;; Load `emacsvox-eat' rather than requiring this module directly.

;;; Code:

(require 'emacsvox-eat-core)
(defvar eat-terminal)
(declare-function eat-term-display-cursor "eat" (terminal))
(declare-function eat-term-end "eat" (terminal))
(declare-function eat-term-in-alternative-display-p "eat" (terminal))
(declare-function eat-term-live-p "eat" (object))

;;;  Interactive Commands:

(defconst emacsvox-eat--history-navigation-targets
  '(eat-line-find-input
    eat-line-next-input
    eat-line-next-matching-input
    eat-line-next-matching-input-from-input
    eat-line-previous-input
    eat-line-previous-matching-input
    eat-line-previous-matching-input-from-input)
  "Public EAT line-history commands that replace the editable input.")

(defconst emacsvox-eat--history-isearch-targets
  '(eat-line-history-isearch-backward
    eat-line-history-isearch-backward-regexp)
  "Public EAT commands that start an input-history Isearch.")

(defconst emacsvox-eat--prompt-navigation-targets
  '(eat-next-shell-prompt eat-previous-shell-prompt)
  "Public EAT commands that move point between shell prompts.")

(defun emacsvox-eat--line-input-content ()
  "Return bounded editable EAT line input, or nil when none is available."
  (when-let* ((eat-terminal)
              (terminal-end (ignore-errors (eat-term-end eat-terminal)))
              (start
               (if (markerp terminal-end)
                   (marker-position terminal-end)
                 terminal-end))
              ((integerp start))
              ((<= (point-min) start (point-max))))
    (let ((text
           (string-trim-right
            (buffer-substring-no-properties start (point-max)))))
      (unless (string-empty-p text)
        (emacsvox-eat--bounded-output
         (emacsvox-eat--split-screen-rows text))))))

(defun emacsvox-eat--present-history-input ()
  "Present the editable input selected by explicit EAT history navigation."
  (emacsvox-eat--submit
   (or (emacsvox-eat--line-input-content)
       "Empty terminal history input")
   (emacsvox-eat--facts
    'command-input 'focus-entered 'history-navigation
    '(:command-input-origin history))
   'navigation 'select-object 'replaceable
   (emacsvox-eat--terminal-delivery-key 'history-navigation)))

(defun emacsvox-eat--present-prompt-navigation ()
  "Present the line reached by explicit EAT shell-prompt navigation."
  (let* ((line
          (buffer-substring-no-properties
           (line-beginning-position) (line-end-position)))
         (content (emacsvox-eat--bounded-output (list line))))
    (emacsvox-eat--submit
     (if (and content (not (string-empty-p (string-trim content))))
         content
       "Blank terminal prompt line")
     (emacsvox-eat--facts
      'command-prompt 'focus-entered 'prompt-navigation)
     'navigation 'item 'replaceable
     (emacsvox-eat--terminal-delivery-key 'prompt-navigation))))

(cl-loop
 for target in emacsvox-eat--history-navigation-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Present input after interactive `%s'." target)
     (when (and (ems-interactive-p ',target)
                (emacsvox-eat--selected-buffer-p))
       (emacsvox-eat--present-history-input)))))

(defun emacsvox-eat--history-isearch-ended ()
  "Present EAT history input when an explicitly started Isearch ends."
  (remove-hook 'isearch-mode-end-hook
               #'emacsvox-eat--history-isearch-ended t)
  (when (and eat-terminal (emacsvox-eat--selected-buffer-p))
    (emacsvox-eat--present-history-input)))

(cl-loop
 for target in emacsvox-eat--history-isearch-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Arrange feedback after interactive `%s'." target)
     (when (and (ems-interactive-p ',target)
                (emacsvox-eat--selected-buffer-p))
       (add-hook 'isearch-mode-end-hook
                 #'emacsvox-eat--history-isearch-ended nil t)))))

(cl-loop
 for target in emacsvox-eat--prompt-navigation-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Present the prompt reached by interactive `%s'." target)
     (when (and (ems-interactive-p ',target)
                (emacsvox-eat--selected-buffer-p))
       (emacsvox-eat--present-prompt-navigation)))))

(defconst emacsvox-eat--yank-targets
  '(eat-yank eat-yank-from-kill-ring eat-xterm-paste
    eat-mouse-yank-primary eat-mouse-yank-secondary)
  "EAT commands that paste saved or selected terminal input.")

(defconst emacsvox-eat--yank-labels
  '((eat-yank . "Pasted terminal input")
    (eat-yank-from-kill-ring . "Pasted selected kill-ring input")
    (eat-xterm-paste . "Pasted clipboard input")
    (eat-mouse-yank-primary . "Pasted primary selection")
    (eat-mouse-yank-secondary . "Pasted secondary selection"))
  "Human fallback feedback for EAT terminal paste commands.")

(defun emacsvox-eat--before-terminal-paste (&rest _)
  "Invalidate input-correlated state before sending terminal paste content."
  (emacsvox-eat--resolve-deletion-as-cue)
  (emacsvox-eat--cancel-completion)
  (emacsvox-eat--remember-input-row-offset)
  (setq emacsvox-eat--recent-input nil))

(defun emacsvox-eat--keyboard-yank-content ()
  "Return bounded content most recently yanked by `eat-yank'."
  (when-let* ((text (car-safe kill-ring-yank-pointer))
              ((stringp text)))
    (emacsvox-eat--bounded-output
     (split-string (substring-no-properties text) "\n" nil))))

(defun emacsvox-eat--present-terminal-paste (target)
  "Present a terminal paste performed by EAT command TARGET."
  (emacsvox-eat--submit
   (or (and (eq target 'eat-yank)
            (emacsvox-eat--keyboard-yank-content))
       (alist-get target emacsvox-eat--yank-labels)
       "Pasted terminal input")
   (emacsvox-eat--facts
    'command-input 'object-changed nil '(:command-input-origin copied))
   'edit 'yank-object))

(cl-loop
 for target in emacsvox-eat--yank-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Present paste feedback after `%s'." target)
     (when (ems-interactive-p ',target)
       (emacsvox-eat--present-terminal-paste ',target)))))

(defun emacsvox-eat--present-secure-input-result (completed-p)
  "Present a content-free EAT secure-input result for COMPLETED-P."
  (emacsvox-eat--submit
   (if completed-p
       "Secure terminal input sent"
     "Secure terminal input cancelled")
   (emacsvox-eat--facts
    'command-interaction
    (if completed-p 'operation-completed 'state-changed))
   'state-change
   (if completed-p 'task-done 'close-object)))

(defun emacsvox--advice-eat-send-password-around (original &rest arguments)
  "Protect EAT observation state while calling password command ORIGINAL.
ARGUMENTS are passed through without inspection so password content never
reaches this advice."
  (let ((terminal-buffer (current-buffer))
        (interactive-p (ems-interactive-p 'eat-send-password))
        completed-p)
    (with-current-buffer terminal-buffer
      (emacsvox-eat--clear-sensitive-screen-state)
      (setq emacsvox-eat--secure-input-active-p t))
    (unwind-protect
        (prog1 (apply original arguments)
          (setq completed-p t))
      (when (buffer-live-p terminal-buffer)
        (with-current-buffer terminal-buffer
          (emacsvox-eat--clear-sensitive-screen-state)
          (setq emacsvox-eat--secure-input-active-p nil)
          (when (and interactive-p (emacsvox-eat--selected-buffer-p))
            ;; Feedback must not prevent a password send or mask its error.
            (condition-case nil
                (emacsvox-eat--present-secure-input-result completed-p)
              (error nil))))))))

(defun emacsvox--advice-eat-reload-after (&rest _)
  "Speak after reloading Eat."
  (emacsvox-eat--install-advice)
  (when (ems-interactive-p 'eat-reload)
    (emacsvox-eat--submit
     "Reloaded EAT"
     (emacsvox-eat--facts 'command-interaction 'operation-completed)
     'state-change 'task-done)))

(defun emacsvox--advice-eat-reset-after (&rest _)
  "Speak after resetting Eat."
  (when (ems-interactive-p 'eat-reset)
    (emacsvox-eat--submit
     "Reset EAT"
     (emacsvox-eat--facts 'command-interaction 'operation-completed)
     'state-change 'task-done)))

(defconst emacsvox-eat--mode-targets
  '(eat-blink-mode eat-char-mode eat-emacs-mode
    eat-eshell-char-mode eat-eshell-emacs-mode eat-eshell-mode
    eat-eshell-semi-char-mode eat-eshell-visual-command-mode
    eat-line-mode eat-mode eat-semi-char-mode
    eat-trace-mode eat-trace-replay-mode)
  "Eat mode-switching commands that receive speech feedback.")

(defconst emacsvox-eat--mode-labels
  '((eat-blink-mode . "Terminal blinking")
    (eat-char-mode . "Character input mode")
    (eat-emacs-mode . "Emacs input mode")
    (eat-eshell-char-mode . "Eshell character input mode")
    (eat-eshell-emacs-mode . "Eshell Emacs input mode")
    (eat-eshell-mode . "EAT Eshell integration")
    (eat-eshell-semi-char-mode . "Eshell semi-character input mode")
    (eat-eshell-visual-command-mode . "EAT Eshell visual commands")
    (eat-line-mode . "Line input mode")
    (eat-mode . "EAT terminal mode")
    (eat-semi-char-mode . "Semi-character input mode")
    (eat-trace-mode . "EAT tracing")
    (eat-trace-replay-mode . "EAT trace replay mode"))
  "Human descriptions of interactive EAT mode commands.")

(defun emacsvox-eat--mode-feedback (target)
  "Return concise human feedback for EAT mode command TARGET."
  (let ((label (or (alist-get target emacsvox-eat--mode-labels)
                   (symbol-name target))))
    (pcase target
      ('eat-blink-mode
       (format "%s %s" label
               (if (bound-and-true-p eat-blink-mode)
                   "enabled" "disabled")))
      ('eat-eshell-mode
       (format "%s %s" label
               (if (bound-and-true-p eat-eshell-mode)
                   "enabled" "disabled")))
      ('eat-eshell-visual-command-mode
       (format "%s %s" label
               (if (bound-and-true-p eat-eshell-visual-command-mode)
                   "enabled" "disabled")))
      ('eat-trace-mode
       (format "%s %s" label
               (if (bound-and-true-p eat-trace-mode)
                   "enabled" "disabled")))
      (_ label))))

(defun emacsvox-eat--present-mode-feedback (target)
  "Present the human mode state produced by EAT command TARGET."
  (emacsvox-eat--submit
   (emacsvox-eat--mode-feedback target)
   (emacsvox-eat--facts 'command-interaction 'state-changed)
   'state-change 'button))

(cl-loop
 for target in emacsvox-eat--mode-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Speak after `%s'." target)
     (when (ems-interactive-p ',target)
       (emacsvox-eat--present-mode-feedback ',target)))))

(defun emacsvox--advice-eat-after (&rest _)
  "Speak after opening Eat."
  (when (ems-interactive-p 'eat)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(defconst emacsvox-eat--advice-targets
  (append emacsvox-eat--history-navigation-targets
          emacsvox-eat--history-isearch-targets
          emacsvox-eat--prompt-navigation-targets
          emacsvox-eat--yank-targets
          '(eat-reload eat-reset)
          emacsvox-eat--mode-targets
          '(eat))
  "Current Eat targets that receive native after advice.")

(defconst emacsvox-eat--before-advice
  (append
   '((eat-reset . emacsvox--advice-eat-reset-before)
     (eat-reload . emacsvox--advice-eat-reload-before))
   (mapcar
    (lambda (target)
      (cons target #'emacsvox-eat--before-terminal-paste))
    emacsvox-eat--yank-targets))
  "EAT targets and native before-advice used for state invalidation.")

(defconst emacsvox-eat--around-advice
  '((eat-send-password . emacsvox--advice-eat-send-password-around)
    (eat-self-input . emacsvox--advice-eat-self-input-around))
  "EAT targets and native around-advice used for bounded input state.")

(defun emacsvox-eat--install-advice ()
  "Install native advice after the optional Eat package loads."
  ;; Reloads must remove the superseded fixed-label raw-input adapter before
  ;; installing observed deletion feedback.
  (when (fboundp 'eat-self-input)
    (advice-remove
     'eat-self-input 'emacsvox--advice-eat-self-input-after))
  (dolist (target emacsvox-eat--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox))))))
  (dolist (entry emacsvox-eat--before-advice)
    (let ((target (car entry))
          (function (cdr entry)))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :before function '((name . emacsvox-state))))))
  (dolist (entry emacsvox-eat--around-advice)
    (let ((target (car entry))
          (function (cdr entry)))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :around function '((name . emacsvox-state))))))
  (when
      (and
       (fboundp 'eat-self-input)
       (not
        (advice-member-p
         #'emacsvox--advice-eat-self-input-before 'eat-self-input)))
    (advice-add
     'eat-self-input :before #'emacsvox--advice-eat-self-input-before
     '((name . emacsvox)))))

(defun emacsvox-eat--tab-event-p (event)
  "Return non-nil when EVENT is a Tab key event."
  (and event
       (or (eq event 9)
           (memq (event-basic-type event) '(9 tab)))))

(defun emacsvox-eat--navigation-direction (event)
  "Return a normalized terminal navigation direction for EVENT."
  (when event
    (let ((basic (event-basic-type event))
          (modifiers (event-modifiers event)))
      (or
       (and (or (memq 'meta modifiers)
                (and (memq 'control modifiers)
                     (memq basic '(left right))))
            (pcase basic
              ((or ?b 'left) 'backward)
              ((or ?f 'right) 'forward)))
       (pcase event
         (16 'up)
         (14 'down)
         (2 'left)
         (6 'right)
         (9 'forward))
       (pcase basic
         ((or 'up 'prior) 'up)
         ((or 'down 'next) 'down)
         ((or 'left 'home) 'left)
         ((or 'right 'end) 'right)
         ('tab 'forward)
         ((or 'backtab 'iso-lefttab) 'backward))))))

(defun emacsvox-eat--navigation-unit (event)
  "Return `word' when EVENT conventionally moves by a terminal word."
  (when event
    (let ((basic (event-basic-type event))
          (modifiers (event-modifiers event)))
      (when (or (and (memq 'meta modifiers)
                     (memq basic '(?b ?f left right)))
                (and (memq 'control modifiers)
                     (memq basic '(left right))))
        'word))))

(defun emacsvox-eat--raw-input-action (event)
  "Return the content-free main-screen action represented by EVENT.
The return value is one of `submit', `backspace', `delete', `kill', or nil."
  (when event
    (let ((basic (event-basic-type event))
          (modifiers (event-modifiers event)))
      (cond
       ((or (memq event '(10 13))
            (memq basic '(linefeed return)))
        'submit)
       ((or (eq event 127) (eq basic 'backspace)) 'backspace)
       ((memq basic '(delete deletechar)) 'delete)
       ((or (eq event 11)
            (and (memq 'control modifiers) (eq basic ?k))
            (and (memq 'meta modifiers) (eq basic ?d)))
        'kill)))))

(defun emacsvox-eat--raw-input-feedback-eligible-p ()
  "Return non-nil when raw main-screen input feedback is safe and useful."
  (and eat-terminal
       (not emacsvox-eat--secure-input-active-p)
       (emacsvox-eat--selected-buffer-p)
       (ignore-errors
         (and (eat-term-live-p eat-terminal)
              (not (eat-term-in-alternative-display-p eat-terminal))
              (emacsvox-eat--following-live-p)))))

(defun emacsvox-eat--cancel-deletion ()
  "Cancel and forget the current observed terminal deletion."
  (when (timerp emacsvox-eat--deletion-timer)
    (cancel-timer emacsvox-eat--deletion-timer))
  (setq emacsvox-eat--deletion-intent nil
        emacsvox-eat--deletion-timer nil))

(defun emacsvox-eat--deletion-intent-current-p (intent)
  "Return non-nil when observed terminal deletion INTENT is current."
  (when intent
    (let ((generation (plist-get intent :generation))
          (deadline (plist-get intent :deadline)))
      (and (integerp generation)
           (= generation emacsvox-eat--generation)
           (numberp deadline)
           (<= (float-time) deadline)))))

(defun emacsvox-eat--current-deletion-intent ()
  "Return the current terminal deletion intent, cueing stale ambiguity."
  (if (emacsvox-eat--deletion-intent-current-p
       emacsvox-eat--deletion-intent)
      emacsvox-eat--deletion-intent
    (emacsvox-eat--resolve-deletion-as-cue)
    nil))

(defun emacsvox-eat--present-deletion-cue ()
  "Present an action-only cue for an ambiguous terminal deletion."
  (emacsvox-aural-submit-actions
   :facts
   (append
    (emacsvox-eat--facts
     'command-input 'object-changed nil
     '(:command-input-origin current))
    '(:edit-operation deletion))
   :module 'eat
   :occasion 'edit
   :delivery-policy 'replaceable
   :replacement-key
   (emacsvox-eat--terminal-delivery-key 'deletion)))

(defun emacsvox-eat--resolve-deletion-as-cue ()
  "Resolve a transported deletion as a cue, or clear it when ineligible."
  (when-let* ((intent emacsvox-eat--deletion-intent))
    (let ((present-p
           (and (plist-get intent :transported)
                (emacsvox-eat--raw-input-feedback-eligible-p))))
      (emacsvox-eat--cancel-deletion)
      (when present-p (emacsvox-eat--present-deletion-cue)))))

(defun emacsvox-eat--begin-deletion (action count)
  "Begin an observed terminal deletion for ACTION repeated COUNT times.
Return its serial, or nil when rendered feedback would be unsafe."
  (when (and (memq action '(backspace delete kill))
             (emacsvox-eat--raw-input-feedback-eligible-p))
    (when-let* ((screen (ignore-errors (emacsvox-eat--capture-screen))))
      (let* ((now (float-time))
             (old (emacsvox-eat--current-deletion-intent))
             (merge-p (and old (eq action (plist-get old :action))))
             (normalized-count
              (if (integerp count) (max 1 (abs count)) 1)))
        (unless merge-p (emacsvox-eat--resolve-deletion-as-cue))
        (when (timerp emacsvox-eat--deletion-timer)
          (cancel-timer emacsvox-eat--deletion-timer))
        (setq emacsvox-eat--deletion-timer nil
              emacsvox-eat--deletion-serial
              (1+ emacsvox-eat--deletion-serial)
              emacsvox-eat--deletion-intent
              (list
               :generation emacsvox-eat--generation
               :serial emacsvox-eat--deletion-serial
               :action action
               :count
               (+ normalized-count
                  (if merge-p (or (plist-get old :count) 1) 0))
               :started-at (if merge-p (plist-get old :started-at) now)
               :deadline (+ now emacsvox-eat--deletion-timeout)
               :screen (if merge-p (plist-get old :screen) screen)
               :transported nil))
        emacsvox-eat--deletion-serial))))

(defun emacsvox-eat--expire-deletion (buffer generation serial)
  "Expire BUFFER's observed deletion identified by GENERATION and SERIAL."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (and emacsvox-eat--deletion-intent
                 (= generation emacsvox-eat--generation)
                 (= serial (plist-get emacsvox-eat--deletion-intent :serial)))
        (emacsvox-eat--resolve-deletion-as-cue)))))

(defun emacsvox-eat--commit-deletion (serial)
  "Mark observed terminal deletion SERIAL as transported and arm its timer."
  (when (and serial emacsvox-eat--deletion-intent
             (= serial (plist-get emacsvox-eat--deletion-intent :serial)))
    (setq emacsvox-eat--deletion-intent
          (plist-put emacsvox-eat--deletion-intent :transported t))
    (when (timerp emacsvox-eat--deletion-timer)
      (cancel-timer emacsvox-eat--deletion-timer))
    (setq emacsvox-eat--deletion-timer
          (run-at-time
           (max
            0.0
            (- (plist-get emacsvox-eat--deletion-intent :deadline)
               (float-time)))
           nil #'emacsvox-eat--expire-deletion
           (current-buffer) emacsvox-eat--generation serial))))

(defun emacsvox-eat--snapshot-row-start (snapshot row)
  "Return the text offset at which ROW begins in SNAPSHOT, or nil."
  (when-let* ((text (plist-get snapshot :text))
              ((integerp row)))
    (let ((starts (emacsvox-eat--row-start-offsets text)))
      (when (< -1 row (length starts)) (aref starts row)))))

(defun emacsvox-eat--snapshot-row-local-cursor (snapshot row)
  "Return SNAPSHOT's cursor offset relative to ROW, or nil."
  (when-let* ((offset (plist-get snapshot :cursor-offset))
              ((integerp offset))
              (cursor-row (plist-get snapshot :cursor-row))
              ((integerp cursor-row))
              ((= row cursor-row))
              (start (emacsvox-eat--snapshot-row-start snapshot row)))
    (- offset start)))

(defun emacsvox-eat--rows-equal-except-p (old-rows new-rows row)
  "Return non-nil when OLD-ROWS and NEW-ROWS differ, if at all, only at ROW."
  (and (= (length old-rows) (length new-rows))
       (cl-loop
        for old in old-rows
        for new in new-rows
        for index from 0
        always (or (= index row) (equal old new)))))

(defun emacsvox-eat--snapshot-range-concealed-p (snapshot start end)
  "Return non-nil when SNAPSHOT range START through END is concealed."
  (cl-some
   (lambda (run)
     (and (< start (cadr run))
          (< (car run) end)
          (memq 'concealed (plist-get (caddr run) :traits))))
   (plist-get snapshot :styles)))

(defun emacsvox-eat--observed-deleted-text (intent snapshot)
  "Return text unambiguously deleted between INTENT and rendered SNAPSHOT.
Only a same-generation, same-row main-screen edit is inferred.  Terminal
right-side blank padding is ignored, but unrelated rows must remain equal."
  (when-let* ((old (plist-get intent :screen))
              ((equal (plist-get old :generation)
                      (plist-get snapshot :generation)))
              ((not (plist-get old :alternate-screen)))
              ((not (plist-get snapshot :alternate-screen)))
              (row (plist-get old :cursor-row))
              ((integerp row))
              (new-row-index (plist-get snapshot :cursor-row))
              ((integerp new-row-index))
              ((= row new-row-index))
              (old-rows (plist-get old :rows))
              (new-rows (plist-get snapshot :rows))
              ((< -1 row (length old-rows)))
              ((emacsvox-eat--rows-equal-except-p old-rows new-rows row))
              (old-row (nth row old-rows))
              (new-row (nth row new-rows))
              ((not (equal old-row new-row)))
              (old-cursor
               (emacsvox-eat--snapshot-row-local-cursor old row))
              (new-cursor
               (emacsvox-eat--snapshot-row-local-cursor snapshot row))
              (row-start (emacsvox-eat--snapshot-row-start old row)))
    (pcase (plist-get intent :action)
      ('backspace
       (when (and (< new-cursor old-cursor)
                  (<= 0 new-cursor old-cursor (length old-row)))
         (let* ((candidate (substring old-row new-cursor old-cursor))
                (expected
                 (concat
                  (substring old-row 0 new-cursor)
                  (substring old-row old-cursor))))
           (when (and
                  (not (string-empty-p candidate))
                  (equal (string-trim-right expected)
                         (string-trim-right new-row))
                  (not
                   (emacsvox-eat--snapshot-range-concealed-p
                    old (+ row-start new-cursor) (+ row-start old-cursor))))
             candidate))))
      ((or 'delete 'kill)
       (when (and (= new-cursor old-cursor)
                  (<= 0 old-cursor (length old-row)))
         (let ((effective-old-row (string-trim-right old-row))
               (effective-new-row
                (concat
                 (substring new-row 0 (min new-cursor (length new-row)))
                 (string-trim-right
                  (substring new-row (min new-cursor (length new-row)))))))
           (when-let* ((change
                       (emacsvox-eat--sequence-change
                        effective-old-row effective-new-row))
                     (start (plist-get change :start))
                     (old-end (plist-get change :old-end))
                     (new-end (plist-get change :new-end))
                     ((<= 0 old-cursor (length effective-old-row)))
                     ((= start old-cursor))
                     ((= new-end start))
                     ((< start old-end))
                     (candidate
                      (substring effective-old-row start old-end))
                     (expected
                      (concat
                       (substring effective-old-row 0 start)
                       (substring effective-old-row old-end)))
                     ((equal expected effective-new-row))
                     ((not
                       (emacsvox-eat--snapshot-range-concealed-p
                        old (+ row-start start) (+ row-start old-end)))))
             candidate)))))))

(defun emacsvox-eat--deleted-character-name (character)
  "Return a nonempty spoken name for deleted CHARACTER."
  (let ((name (and character (tts-char-to-speech character))))
    (if (and name (not (string-empty-p (string-trim name))))
        (string-trim name)
      (char-to-string character))))

(defun emacsvox-eat--deleted-text-content (text intent)
  "Return bounded spoken deletion TEXT described by INTENT."
  (let* ((length (length text))
         (limit (min length emacsvox-eat--maximum-deletion-characters))
         (additional (- length limit))
         (count (or (plist-get intent :count) 1))
         (action (plist-get intent :action))
         (bounded
          (if (eq action 'backspace)
              (substring text (- length limit))
            (substring text 0 limit)))
         (content
          (cond
           ((= length 1)
            (emacsvox-eat--deleted-character-name (aref text 0)))
           ((and (> count 1) (memq action '(backspace delete)))
            (let ((characters (string-to-list bounded)))
              (when (eq action 'backspace)
                (setq characters (nreverse characters)))
              (mapconcat
               #'emacsvox-eat--deleted-character-name characters " ")))
           (t
            (let ((sanitized
                   (emacsvox-eat--sanitize-output-row bounded)))
              (if (string-empty-p (string-trim sanitized))
                  (mapconcat
                   #'emacsvox-eat--deleted-character-name
                   (string-to-list sanitized) " ")
                sanitized))))))
    (when (> additional 0)
      (setq content
            (format "%s, %d additional characters deleted"
                    content additional)))
    content))

(defun emacsvox-eat--present-observed-deletion (intent snapshot)
  "Present deletion INTENT from its rendered result in SNAPSHOT."
  (let* ((text (emacsvox-eat--observed-deleted-text intent snapshot))
         (content (and text (emacsvox-eat--deleted-text-content text intent))))
    (emacsvox-eat--cancel-deletion)
    (if content
        (emacsvox-eat--submit
         content
         (emacsvox-eat--facts
          'command-input 'object-changed nil
          '(:command-input-origin current))
         'edit nil 'replaceable
         (emacsvox-eat--terminal-delivery-key 'deletion))
      (emacsvox-eat--present-deletion-cue))
    t))

(defun emacsvox-eat--navigation-intent-current-p (intent)
  "Return non-nil when content-free navigation INTENT is still current."
  (and intent
       (= (plist-get intent :generation) emacsvox-eat--generation)
       (<= (float-time) (plist-get intent :deadline))))

(defun emacsvox-eat--current-navigation-intent ()
  "Return current terminal navigation intent, clearing it when stale."
  (if (emacsvox-eat--navigation-intent-current-p
       emacsvox-eat--recent-navigation-intent)
      emacsvox-eat--recent-navigation-intent
    (setq emacsvox-eat--recent-navigation-intent nil)))

(defun emacsvox-eat--merge-pending-navigation-intent (intent)
  "Merge content-free navigation INTENT into the current update burst."
  (if (null emacsvox-eat--pending-navigation-intent)
      (setq emacsvox-eat--pending-navigation-intent (copy-sequence intent))
    (if (and
         (eq (plist-get emacsvox-eat--pending-navigation-intent :direction)
             (plist-get intent :direction))
         (eq (plist-get emacsvox-eat--pending-navigation-intent :unit)
             (plist-get intent :unit)))
        (progn
          (setq emacsvox-eat--pending-navigation-intent
                (plist-put
                 emacsvox-eat--pending-navigation-intent :count
                 (1+
                  (or
                   (plist-get
                    emacsvox-eat--pending-navigation-intent :count)
                   1))))
          (setq emacsvox-eat--pending-navigation-intent
                (plist-put
                 emacsvox-eat--pending-navigation-intent :deadline
                 (max
                  (plist-get
                   emacsvox-eat--pending-navigation-intent :deadline)
                  (plist-get intent :deadline)))))
      (setq emacsvox-eat--pending-navigation-intent
            (plist-put
             emacsvox-eat--pending-navigation-intent :ambiguous t)))))

(defun emacsvox-eat--record-navigation-intent (direction &optional unit)
  "Record content-free terminal navigation in DIRECTION and optional UNIT."
  (let* ((now (float-time))
         (screen
          (or emacsvox-eat--screen-snapshot
              (ignore-errors (emacsvox-eat--capture-screen)))))
    (setq emacsvox-eat--recent-input nil
          emacsvox-eat--recent-navigation-intent
          (list
           :generation emacsvox-eat--generation
           :direction direction
           :unit unit
           :started-at now
           :deadline (+ now emacsvox-eat--navigation-timeout)
           :count 1
           :cursor-offset (plist-get screen :cursor-offset)
           :cursor-row (plist-get screen :cursor-row)
           :cursor-column (plist-get screen :cursor-column)
           :input-row-offset emacsvox-eat--input-row-offset
           :input-start-row emacsvox-eat--input-start-row))))

(defun emacsvox-eat--capture-completion (cursor)
  "Start a terminal completion transaction at EAT terminal CURSOR."
  (emacsvox-eat--cancel-completion)
  (setq emacsvox-eat--recent-navigation-intent nil
        emacsvox-eat--pending-navigation-intent nil)
  (setq emacsvox-eat--completion-serial
        (1+ emacsvox-eat--completion-serial))
  (when-let* ((cursor)
              (screen (emacsvox-eat--capture-screen)))
    (let* ((started-at (float-time))
           (deadline (+ started-at emacsvox-eat--completion-timeout)))
      (setq emacsvox-eat--completion-snapshot
            (list
             :generation emacsvox-eat--generation
             :serial emacsvox-eat--completion-serial
             :started-at started-at
             :deadline deadline
             :screen screen)
            emacsvox-eat--completion-timer
            (run-at-time
             emacsvox-eat--completion-timeout nil
             #'emacsvox-eat--expire-completion
             (current-buffer) emacsvox-eat--generation
             emacsvox-eat--completion-serial)))))

(defun emacsvox-eat--cancel-completion ()
  "Cancel and forget the current terminal completion transaction."
  (when (timerp emacsvox-eat--completion-timer)
    (cancel-timer emacsvox-eat--completion-timer))
  (setq emacsvox-eat--completion-snapshot nil
        emacsvox-eat--completion-timer nil))

(defun emacsvox-eat--expire-completion (buffer generation serial)
  "Expire BUFFER's terminal completion identified by GENERATION and SERIAL."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (and emacsvox-eat--completion-snapshot
                 (= generation emacsvox-eat--generation)
                 (= serial emacsvox-eat--completion-serial)
                 (= serial
                    (plist-get emacsvox-eat--completion-snapshot :serial)))
        (setq emacsvox-eat--completion-snapshot nil
              emacsvox-eat--completion-timer nil)))))

(defun emacsvox-eat--completion-current-p ()
  "Return non-nil when the terminal completion transaction is current."
  (let ((snapshot emacsvox-eat--completion-snapshot))
    (if (and snapshot
             (= (plist-get snapshot :generation)
                emacsvox-eat--generation)
             (<= (float-time) (plist-get snapshot :deadline)))
        t
      (emacsvox-eat--cancel-completion)
      nil)))

(defun emacsvox-eat--record-input (event)
  "Record one non-completion terminal input EVENT for correlated feedback."
  (let* ((basic (and event (event-basic-type event)))
         (recordable-p
          (and
           (not (emacsvox-eat--raw-input-action event))
           ;; C-h is terminal erase on some peers and cursor movement on
           ;; others.  Either way, adjacent screen text is not typed echo.
           (not (eq event 8))
           (or
            (and (integerp event) (>= event 32))
            (and (symbolp basic)
                 (not (memq basic '(tab return linefeed escape))))))))
    (when recordable-p (emacsvox-eat--remember-input-row-offset))
    (setq emacsvox-eat--recent-navigation-intent nil
          emacsvox-eat--pending-navigation-intent nil
          emacsvox-eat--recent-input
          (when recordable-p
            (list emacsvox-eat--generation basic
                  (+ (float-time) 0.5))))))

(defun emacsvox--advice-eat-self-input-before (_count &optional event)
  "Capture terminal completion context before EAT sends Tab EVENT."
  (let* ((event (or event last-command-event))
         (tab-p (emacsvox-eat--tab-event-p event))
         (direction (emacsvox-eat--navigation-direction event))
         (unit (emacsvox-eat--navigation-unit event))
         (action (emacsvox-eat--raw-input-action event))
         (alternate-screen-p
          (plist-get emacsvox-eat--screen-snapshot :alternate-screen)))
    (unless (memq action '(backspace delete kill))
      (emacsvox-eat--resolve-deletion-as-cue))
    (cond
     ((and eat-terminal tab-p (not alternate-screen-p))
      (setq emacsvox-eat--recent-input nil)
      (emacsvox-eat--remember-input-row-offset)
      (emacsvox-eat--capture-completion
       (eat-term-display-cursor eat-terminal)))
     (direction
      (emacsvox-eat--cancel-completion)
      (when (and (memq direction '(up down))
                 (not alternate-screen-p))
        (emacsvox-eat--remember-input-row-offset))
      (emacsvox-eat--record-navigation-intent direction unit))
     (action
      (emacsvox-eat--cancel-completion)
      (when (eq action 'submit)
        (setq emacsvox-eat--input-row-offset nil
              emacsvox-eat--input-start-row nil))
      (setq emacsvox-eat--recent-input nil
            emacsvox-eat--recent-navigation-intent nil
            emacsvox-eat--pending-navigation-intent nil))
     (t
      (emacsvox-eat--cancel-completion)
      (emacsvox-eat--record-input event)))))

(defun emacsvox--advice-eat-self-input-around
    (original count &optional event)
  "Call ORIGINAL, observing rendered deletion for COUNT copies of EVENT.
Return is deliberately silent.  Backspace, Delete, and forward kills are
announced only from their later public-screen result, with an action cue when
that is ambiguous."
  (let* ((event (or event last-command-event))
         (action (emacsvox-eat--raw-input-action event))
         (serial (emacsvox-eat--begin-deletion action count))
         completed
         result)
    (unwind-protect
        (progn
          (setq result (funcall original count event)
                completed t))
      (if completed
          (emacsvox-eat--commit-deletion serial)
        (when (and serial emacsvox-eat--deletion-intent
                   (= serial
                      (plist-get emacsvox-eat--deletion-intent :serial)))
          (emacsvox-eat--cancel-deletion))))
    result))

(defun emacsvox-eat--screen-cursor-input (snapshot)
  "Return SNAPSHOT's wrapped visual input facts through the terminal cursor.
Full-width rows immediately before the cursor row are treated as visual wraps.
This is a conservative public-screen inference; no EAT wrap property is read."
  (when-let* ((text (plist-get snapshot :text))
              (offset (plist-get snapshot :cursor-offset))
              (cursor-row (plist-get snapshot :cursor-row))
              (size (plist-get snapshot :size))
              (width (car size))
              ((integerp offset))
              ((<= 0 offset (length text)))
              ((integerp cursor-row))
              ((> width 0)))
    (let* ((rows (plist-get snapshot :rows))
           (prefix-rows
            (emacsvox-eat--split-screen-rows (substring text 0 offset)))
           (start cursor-row))
      (when (and (< cursor-row (length rows))
                 (= (length prefix-rows) (1+ cursor-row)))
        (while (and (> start 0)
                    (>= (string-width (nth (1- start) rows)) width))
          (setq start (1- start)))
        (list :text (mapconcat #'identity (nthcdr start prefix-rows) "")
              :start-row start)))))

(defun emacsvox-eat--screen-cursor-prefix (snapshot)
  "Return SNAPSHOT's wrapped visual input through the terminal cursor."
  (plist-get (emacsvox-eat--screen-cursor-input snapshot) :text))

(defun emacsvox-eat--completion-leading-rows-compatible-p
    (old old-input new new-input)
  "Return non-nil when OLD and NEW added no rows before their cursor inputs."
  (let* ((old-leading
          (emacsvox-eat--list-slice
           (plist-get old :rows) 0 (plist-get old-input :start-row)))
         (new-leading
          (emacsvox-eat--list-slice
           (plist-get new :rows) 0 (plist-get new-input :start-row)))
         (overlap
          (emacsvox-eat--suffix-prefix-row-overlap old-leading new-leading)))
    (or (equal old-leading new-leading)
        (and (> overlap 0) (<= (length new-leading) overlap)))))

(defun emacsvox-eat--escaped-character-p (text index)
  "Return non-nil when the character at TEXT INDEX is backslash-escaped."
  (let ((backslashes 0)
        (position (1- index)))
    (while (and (>= position 0) (= (aref text position) ?\\))
      (setq backslashes (1+ backslashes)
            position (1- position)))
    (= (% backslashes 2) 1)))

(defun emacsvox-eat--completion-display-field (prefix)
  "Return a conservative final displayed field from cursor PREFIX.
Backslash-escaped whitespace remains part of the field.  Quote-bearing input
returns nil because recognizing its logical word would require shell grammar."
  (unless (string-match-p "['\"]" prefix)
    (let* ((end (string-match-p "[[:space:]]*\\'" prefix))
           (start end))
      (while
          (and (> start 0)
               (let* ((index (1- start))
                      (character (aref prefix index)))
                 (or (not (memq character '(?\s ?\t ?\n ?\r)))
                     (emacsvox-eat--escaped-character-p prefix index))))
        (setq start (1- start)))
      (and (< start end) (substring prefix start end)))))

(defun emacsvox-eat--completion-label (displayed-field)
  "Return a concise path-aware label for DISPLAYED-FIELD."
  (let* ((length (length displayed-field))
         (directory-p
          (and (> length 0) (= (aref displayed-field (1- length)) ?/)))
         (trimmed
          (if directory-p (substring displayed-field 0 -1) displayed-field))
         (component (file-name-nondirectory trimmed)))
    (concat (if (zerop (length component)) trimmed component)
            (if directory-p "/" ""))))

(defun emacsvox-eat--inline-completion-change (old new)
  "Return conservative inline completion facts between OLD and NEW screens."
  (when (and old new
             (equal (plist-get old :generation)
                    (plist-get new :generation))
             (not (plist-get old :alternate-screen))
             (not (plist-get new :alternate-screen)))
    (let* ((diff (emacsvox-eat--screen-diff old new))
           (old-input (emacsvox-eat--screen-cursor-input old))
           (new-input (emacsvox-eat--screen-cursor-input new))
           (old-prefix (plist-get old-input :text))
           (new-prefix (plist-get new-input :text))
           (change
            (and old-prefix new-prefix
                 (emacsvox-eat--sequence-change old-prefix new-prefix))))
      (when (and change
                 (> (plist-get change :start) 0)
                 (>= (length new-prefix) (length old-prefix))
                 (emacsvox-eat--completion-leading-rows-compatible-p
                  old old-input new new-input)
                 (not (emacsvox-eat--complete-output-rows diff new)))
        (let* ((trimmed (string-trim-right new-prefix))
               (field (emacsvox-eat--completion-display-field new-prefix))
               (text
                (if field
                    (emacsvox-eat--completion-label field)
                  trimmed)))
          (when (and (stringp text) (not (string-empty-p text)))
            (list :text text :old old-prefix :new new-prefix
                  :change change :diff (plist-put diff :user-input t))))))))

(defun emacsvox-eat--pending-inline-completion (snapshot)
  "Return inline completion facts for pending transaction at SNAPSHOT."
  (when (emacsvox-eat--completion-current-p)
    (emacsvox-eat--inline-completion-change
     (plist-get emacsvox-eat--completion-snapshot :screen) snapshot)))

(defun emacsvox-eat--completion-input-compatible-p (old-input new-input)
  "Return non-nil when NEW-INPUT can be a redraw of OLD-INPUT."
  (or (equal old-input new-input)
      (when-let* ((change
                   (and old-input new-input
                        (emacsvox-eat--sequence-change old-input new-input))))
        (and (> (plist-get change :start) 0)
             (>= (length new-input) (length old-input))))))

(defun emacsvox-eat--completion-row-items (row)
  "Return conservatively inferred candidate items from terminal ROW.
Two or more spaces may separate columns.  A resulting cell containing any
whitespace is treated as descriptive or ambiguous, so the row is not split."
  (let* ((trimmed (string-trim row))
         (items (and (not (string-empty-p trimmed))
                     (split-string trimmed "[ \t]\\{2,\\}" t))))
    (when (and items
               (cl-every
                (lambda (item) (not (string-match-p "[[:space:]]" item)))
                items))
      items)))

(defun emacsvox-eat--completion-items (rows)
  "Return inferred candidate items from ROWS, or nil for row-oriented output."
  (let ((nonempty
         (cl-remove-if
          (lambda (row) (string-empty-p (string-trim row))) rows))
        items
        valid-p)
    (setq valid-p (not (null nonempty)))
    (dolist (row nonempty)
      (if-let* ((row-items (emacsvox-eat--completion-row-items row)))
          (setq items (append items row-items))
        (setq valid-p nil)))
    (and valid-p items)))

(defun emacsvox-eat--completion-signature (layout rows &optional items)
  "Return a stable normalized signature for completion LAYOUT, ROWS, and ITEMS."
  (list
   layout
   (mapcar
    (lambda (text)
      (string-trim-right (emacsvox-eat--sanitize-output-row text)))
    (if (eq layout 'items) items rows))))

(defun emacsvox-eat--completion-repeated-p (completion)
  "Return non-nil when COMPLETION repeats the retained completion output."
  (and emacsvox-eat--last-completion-output
       (equal (plist-get completion :signature)
              (plist-get emacsvox-eat--last-completion-output :signature))))

(defun emacsvox-eat--completion-output-change (old new)
  "Return candidate/help-row facts between OLD and NEW terminal screens.
Rows are preserved exactly.  `:confidence' is `anchored' when the old screen
through its input row remains as a prefix after scroll alignment, and
`unanchored' when only the redrawn cursor input provides an association."
  (when (and old new
             (equal (plist-get old :generation)
                    (plist-get new :generation))
             (not (plist-get old :alternate-screen))
             (not (plist-get new :alternate-screen)))
    (when-let* ((old-input (emacsvox-eat--screen-cursor-input old))
                (new-input (emacsvox-eat--screen-cursor-input new))
                ((emacsvox-eat--completion-input-compatible-p
                  (plist-get old-input :text) (plist-get new-input :text)))
                (old-cursor-row (plist-get old :cursor-row))
                (new-start-row (plist-get new-input :start-row))
                ((integerp old-cursor-row))
                ((integerp new-start-row)))
      (let* ((old-through-input
              (emacsvox-eat--list-slice
               (plist-get old :rows) 0
               (min (length (plist-get old :rows))
                    (1+ old-cursor-row))))
             (new-leading
              (emacsvox-eat--list-slice
               (plist-get new :rows) 0
               (min (length (plist-get new :rows)) new-start-row)))
             (overlap
              (emacsvox-eat--suffix-prefix-row-overlap
               old-through-input new-leading))
             (rows
              (if (> overlap 0)
                  (nthcdr overlap new-leading)
                new-leading)))
        (when (cl-some
               (lambda (row) (not (string-empty-p (string-trim row))))
               rows)
          (let* ((diff (emacsvox-eat--screen-diff old new))
                 (retained-rows (copy-sequence rows))
                 (content-rows
                  (cl-remove-if
                   (lambda (row) (string-empty-p (string-trim row)))
                   retained-rows))
                 (items (emacsvox-eat--completion-items retained-rows))
                 (layout (if items 'items 'rows)))
            (list
             :rows retained-rows
             :row-count (length content-rows)
             :items items
             :item-count (and items (length items))
             :layout layout
             :signature
             (emacsvox-eat--completion-signature
              layout retained-rows items)
             :confidence (if (> overlap 0) 'anchored 'unanchored)
             :old-input (plist-get old-input :text)
             :new-input (plist-get new-input :text)
             :diff (plist-put diff :user-input t))))))))

(defun emacsvox-eat--pending-completion-output (snapshot)
  "Return candidate/help rows for the pending transaction at SNAPSHOT."
  (when (emacsvox-eat--completion-current-p)
    (emacsvox-eat--completion-output-change
     (plist-get emacsvox-eat--completion-snapshot :screen) snapshot)))

(defun emacsvox-eat--present-inline-completion (text)
  "Present inline terminal completion TEXT as one semantic transaction."
  (when-let* ((content (emacsvox-eat--bounded-output (list text))))
    (emacsvox-eat--submit
     content '(:role candidate :events (completion-input-updated))
     'state-change)))

(defun emacsvox-eat--completion-count-text (completion)
  "Return an accurate count announcement for terminal COMPLETION."
  (let* ((item-count (plist-get completion :item-count))
         (row-count (plist-get completion :row-count))
         (items-p (integerp item-count))
         (count (if items-p item-count row-count))
         (noun (if items-p "candidate" "completion row"))
         (unanchored-p
          (eq (plist-get completion :confidence) 'unanchored)))
    (concat
     (cond
      ((plist-get completion :repeated) "Same ")
      (unanchored-p "At least ")
      (t ""))
     (number-to-string count)
     (if unanchored-p " visible " " ")
     noun
     (if (= count 1) "" "s"))))

(defun emacsvox-eat--bounded-completion-items (items)
  "Return bounded automatic speech for inferred candidate ITEMS."
  (let* ((total (length items))
         (shown-count (min total emacsvox-eat--maximum-spoken-candidates))
         (text
          (emacsvox-eat--bounded-output
           (emacsvox-eat--list-slice items 0 shown-count))))
    (when (> total shown-count)
      (setq text
            (concat
             text "\n"
             (format "%d additional candidates not spoken"
                     (- total shown-count)))))
    text))

(defun emacsvox-eat--present-completion-output (completion)
  "Present terminal candidate/help-row COMPLETION as one transaction."
  (let* ((count (emacsvox-eat--completion-count-text completion))
         (body
          (unless (plist-get completion :repeated)
            (if (eq (plist-get completion :layout) 'items)
                (emacsvox-eat--bounded-completion-items
                 (plist-get completion :items))
              (emacsvox-eat--bounded-output
               (plist-get completion :rows)))))
         (content (if body (concat count "\n" body) count)))
    (when (not (string-empty-p content))
    (emacsvox-eat--submit
     content '(:role candidate :events (operation-completed))
     'state-change))))

(defun emacsvox-eat--speak-input-correlated-update (cursor)
  "Provide the legacy cursor feedback for one recent terminal input at CURSOR."
  (let ((input emacsvox-eat--recent-input))
    (setq emacsvox-eat--recent-input nil)
    (when (and input cursor
               (= (car input) emacsvox-eat--generation)
               (<= (float-time) (caddr input))
               emacsvox-eat--pending-screen-diff)
      (let ((char (char-before cursor)))
        (when char
          (emacsvox-speak-this-char char)
          t)))))
(provide 'emacsvox-eat-input)
;;; emacsvox-eat-input.el ends here
