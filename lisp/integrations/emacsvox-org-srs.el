;;; emacsvox-org-srs.el --- Speech-enable Org-srs reviews -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: Emacsvox contributors
;; Maintainer: Emacsvox contributors
;; Keywords: accessibility, multimedia
;; URL: https://github.com/bartbunting/emacsvox

;; This file is part of Emacsvox.
;;
;; Emacsvox is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; Emacsvox is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Emacsvox.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Speak the question, revealed answer, rating result, and session lifecycle
;; of Org-srs.  Confirmation is command based by default so screen-reader
;; navigation does not accidentally reveal an answer.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)
(require 'emacsvox-aural-source)
(require 'emacsvox-aural-provider-org-srs)

(declare-function org-srs-item-card-regions "org-srs-item-card" ())
(declare-function org-srs-item-cloze-collect "org-srs-item-cloze"
                  (&optional start end))
(declare-function org-srs-item-cloze-visibility
                  "org-srs-item-cloze" () t)
(declare-function org-srs-item-confirm-command "org-srs-item" (&rest args))
(declare-function org-srs-item-confirm-pending-p "org-srs-item" (&optional command))
(declare-function org-srs-item-due-time "org-srs-item" (&rest args))
(declare-function org-srs-review-add-hook-once "org-srs-review"
                  (hook function &optional depth local))
(declare-function org-srs-review-upcoming-items "org-srs-review"
                  (&optional source))
(declare-function org-srs-review-message-review-done "org-srs-review" ())
(declare-function org-srs-review-postpone "org-srs-review"
                  (&optional time &rest args))
(declare-function org-srs-review-quit "org-srs-review" ())
(declare-function org-srs-review-rate-again "org-srs-review-rate" () t)
(declare-function org-srs-review-rate-easy "org-srs-review-rate" () t)
(declare-function org-srs-review-rate-good "org-srs-review-rate" () t)
(declare-function org-srs-review-rate-hard "org-srs-review-rate" () t)
(declare-function org-srs-review-suspend "org-srs-review" ())
(declare-function org-srs-review-undo "org-srs-review-undo" (&optional history))
(declare-function org-srs-review-undo-redo "org-srs-review-undo"
                  (&optional history))
(declare-function org-srs-time-difference "org-srs-time" (time-a time-b))
(declare-function org-srs-time-now "org-srs-time" () t)

(defvar org-srs-item-before-confirm-hook)
(defvar org-srs-item-after-review-hook)
(defvar org-srs-item-confirm)
(defvar org-srs-review-after-rate-hook)
(defvar org-srs-review-continue-hook)
(defvar org-srs-review-finish-hook)
(defvar org-srs-review-item)
(defvar org-srs-review-rating)
(defvar org-srs-review-start-hook)

(defgroup emacsvox-org-srs nil
  "Speech feedback for Org-srs spaced-repetition reviews."
  :group 'emacsvox)

(defcustom emacsvox-org-srs-use-command-confirmation t
  "Use an explicit command to reveal each Org-srs answer.

This prevents ordinary screen-reader navigation keys from being consumed by
`read-key' and revealing the answer.  During a review, use `C-c C-c' to reveal
the answer."
  :type 'boolean
  :group 'emacsvox-org-srs)

(defcustom emacsvox-org-srs-announce-pending-count t
  "Whether the first question announces the number of pending items."
  :type 'boolean
  :group 'emacsvox-org-srs)

(defvar emacsvox-org-srs--session-active-p nil
  "Non-nil while Emacsvox is presenting an Org-srs review session.")

(defvar emacsvox-org-srs--pending-result nil
  "Rating or operation result to combine with the next review announcement.")

(defvar emacsvox-org-srs--suppress-answer nil
  "Dynamically non-nil while abandoning rather than revealing an item.")

(defvar-local emacsvox-org-srs--current-type nil)
(defvar-local emacsvox-org-srs--current-args nil)
(defvar-local emacsvox-org-srs--phase nil)

(defun emacsvox-org-srs--rating-ready-p ()
  "Return non-nil when the current answer has been revealed."
  (not (and (fboundp 'org-srs-item-confirm-pending-p)
            (org-srs-item-confirm-pending-p))))

(defun emacsvox-org-srs--call-rating (command)
  "Call Org-srs rating COMMAND after checking that the answer is visible."
  (unless (emacsvox-org-srs--rating-ready-p)
    (user-error "Reveal the answer with C-c C-c before rating it"))
  (call-interactively command))

(defun emacsvox-org-srs-rate-again ()
  "Rate the current Org-srs item as again."
  (interactive)
  (emacsvox-org-srs--call-rating #'org-srs-review-rate-again))

(defun emacsvox-org-srs-rate-hard ()
  "Rate the current Org-srs item as hard."
  (interactive)
  (emacsvox-org-srs--call-rating #'org-srs-review-rate-hard))

(defun emacsvox-org-srs-rate-good ()
  "Rate the current Org-srs item as good."
  (interactive)
  (emacsvox-org-srs--call-rating #'org-srs-review-rate-good))

(defun emacsvox-org-srs-rate-easy ()
  "Rate the current Org-srs item as easy."
  (interactive)
  (emacsvox-org-srs--call-rating #'org-srs-review-rate-easy))

(defvar-keymap emacsvox-org-srs-review-mode-map
  :doc "Accessible keys active only while reviewing an Org-srs item."
  "C-c C-c" #'org-srs-item-confirm-command
  "1" #'emacsvox-org-srs-rate-again
  "2" #'emacsvox-org-srs-rate-hard
  "3" #'emacsvox-org-srs-rate-good
  "4" #'emacsvox-org-srs-rate-easy
  "C-c C-l" #'emacsvox-org-srs-speak-current
  "C-c C-p" #'org-srs-review-postpone
  "C-c C-s" #'org-srs-review-suspend
  "C-c C-q" #'org-srs-review-quit
  "C-c C-u" #'org-srs-review-undo
  "C-c C-r" #'org-srs-review-undo-redo)

(define-minor-mode emacsvox-org-srs-review-mode
  "Provide accessible keys while an Org-srs item is being reviewed."
  :init-value nil
  :lighter " Vox-SRS"
  :keymap emacsvox-org-srs-review-mode-map
  (when emacsvox-org-srs-review-mode
    (setq-local emacsvox-aural-module 'org-srs)))

(defun emacsvox-org-srs--clean-content (content)
  "Remove Org-srs metadata and visual markup from CONTENT."
  (let ((case-fold-search t))
    (setq content
          (replace-regexp-in-string
           "^[ \t]*:\\(?:PROPERTIES\\|SRSITEMS\\):[ \t]*\n\\(?:.*\n\\)*?:END:[ \t]*\n?"
           "" content))
    (setq content
          (replace-regexp-in-string
           "^[ \t]*#\\+NAME:[ \t]+srsitem:.*\n?" "" content))
    (setq content
          (replace-regexp-in-string "^\\*+[ \t]+" "" content))
    (string-trim content)))

(defun emacsvox-org-srs--region-content (bounds)
  "Return cleaned, voice-preserving text from BOUNDS."
  (when (and (consp bounds) (car bounds) (cdr bounds))
    (emacsvox-org-srs--clean-content
     (emacsvox-aural-source-substring (car bounds) (cdr bounds)))))

(defun emacsvox-org-srs--card-content (side answer-p)
  "Return the card content for SIDE, selecting the answer when ANSWER-P."
  (cl-multiple-value-bind (front back) (org-srs-item-card-regions)
    (let ((content
           (emacsvox-org-srs--region-content
            (if (eq side 'front)
                (if answer-p front back)
              (if answer-p back front)))))
      (replace-regexp-in-string
       "\\`\\(?:Front\\|Back\\)[ \t]*\n" "" content t t))))

(defun emacsvox-org-srs--cloze-target-p (id ids)
  "Return non-nil when cloze ID is one of IDS.

An empty IDS list means every cloze in the entry is a target."
  (or (null ids) (member id ids)))

(defun emacsvox-org-srs--cloze-question (ids)
  "Return the current entry with clozes in IDS rendered as blanks."
  (let ((cursor (point-min))
        (visibility (org-srs-item-cloze-visibility))
        pieces)
    (dolist (cloze (org-srs-item-cloze-collect (point-min) (point-max)))
      (cl-destructuring-bind (id start end text &optional hint) cloze
        (push (emacsvox-aural-source-substring cursor start) pieces)
        (push
         (cond
          ((emacsvox-org-srs--cloze-target-p id ids)
           (if (and hint (not (string-empty-p hint)))
               (format "[blank, hint: %s]" hint)
             "[blank]"))
          (visibility text)
          (t "[hidden]"))
         pieces)
        (setq cursor end)))
    (push (emacsvox-aural-source-substring cursor (point-max)) pieces)
    (emacsvox-org-srs--clean-content (apply #'concat (nreverse pieces)))))

(defun emacsvox-org-srs--cloze-answer (ids)
  "Return the answer text for clozes in IDS."
  (let (answers)
    (dolist (cloze (org-srs-item-cloze-collect (point-min) (point-max)))
      (cl-destructuring-bind (id _start _end text &optional _hint) cloze
        (when (emacsvox-org-srs--cloze-target-p id ids)
          (push text answers))))
    (string-join (nreverse answers) "; ")))

(defun emacsvox-org-srs--item-content (type args answer-p)
  "Return question or answer content for Org-srs TYPE and ARGS.

When ANSWER-P is non-nil, return the revealed answer."
  (pcase type
    ('card
     (emacsvox-org-srs--card-content (or (car args) 'back) answer-p))
    ('cloze
     (if answer-p
         (emacsvox-org-srs--cloze-answer args)
       (emacsvox-org-srs--cloze-question args)))
    (_
     (emacsvox-org-srs--clean-content
      (emacsvox-aural-source-substring (point-min) (point-max))))))

(defun emacsvox-org-srs--item-kind (type)
  "Return the semantic Org-srs item kind for TYPE."
  (if (eq type 'cloze) 'cloze 'card))

(defun emacsvox-org-srs--submit (content facts occasion)
  "Present CONTENT with semantic FACTS for OCCASION."
  (when (and (stringp content) (not (string-empty-p content)))
    (emacsvox-aural-submit
     content
     :facts facts
     :module 'org-srs
     :occasion occasion
     :delivery-policy 'ordered)))

(defun emacsvox-org-srs--pending-count ()
  "Return the current number of upcoming review items, or nil."
  (when emacsvox-org-srs-announce-pending-count
    (ignore-errors (length (org-srs-review-upcoming-items)))))

(defun emacsvox-org-srs--consume-pending-result ()
  "Return and clear the pending rating or operation result."
  (prog1 emacsvox-org-srs--pending-result
    (setq emacsvox-org-srs--pending-result nil)))

(defun emacsvox-org-srs--question-facts (type count started-p pending)
  "Build question facts for TYPE, COUNT, STARTED-P, and PENDING result."
  (let ((events '(learning-question-presented)))
    (when started-p
      (setq events (append events '(learning-session-started))))
    (let ((event (plist-get pending :event)))
      (when event
        (setq events (append events (list event)))))
    (append
     (list :role 'learning-item
           :events events
           :learning-phase 'question
           :learning-item-kind (emacsvox-org-srs--item-kind type))
     (when (integerp count) (list :learning-pending-count count))
     (let ((rating (plist-get pending :rating)))
       (when rating (list :learning-rating rating)))
     (let ((interval (plist-get pending :interval)))
       (when interval (list :learning-next-interval interval))))))

(defun emacsvox-org-srs--before-confirm (type &rest args)
  "Speak the question before Org-srs confirms TYPE with ARGS."
  (setq-local emacsvox-org-srs--current-type type
              emacsvox-org-srs--current-args args
              emacsvox-org-srs--phase 'question
              emacsvox-aural-module 'org-srs)
  (emacsvox-org-srs-review-mode 1)
  (org-srs-review-add-hook-once
   'org-srs-review-continue-hook
   (lambda () (emacsvox-org-srs-review-mode -1))
   40)
  (let* ((started-p (not emacsvox-org-srs--session-active-p))
         (pending (emacsvox-org-srs--consume-pending-result))
         (count (and started-p (emacsvox-org-srs--pending-count)))
         (question (emacsvox-org-srs--item-content type args nil))
         (parts
          (delq
           nil
           (list
            (plist-get pending :text)
            (when started-p
              (if (integerp count)
                  (format "Review started. %d item%s pending."
                          count (if (= count 1) "" "s"))
                "Review started."))
            (concat "Question: " question)))))
    (setq emacsvox-org-srs--session-active-p t)
    (emacsvox-org-srs--submit
     (string-join parts " ")
     (emacsvox-org-srs--question-facts type count started-p pending)
     'state-change)))

(defun emacsvox-org-srs--after-review (type &rest args)
  "Speak the answer after Org-srs reveals TYPE with ARGS."
  (unless emacsvox-org-srs--suppress-answer
    (setq-local emacsvox-org-srs--phase 'answer)
    (let ((answer (emacsvox-org-srs--item-content type args t)))
      (emacsvox-org-srs--submit
       (concat "Answer: " answer)
       (list :role 'learning-item
             :events '(learning-answer-revealed)
             :learning-phase 'answer
             :learning-item-kind (emacsvox-org-srs--item-kind type))
       'state-change))))

(defun emacsvox-org-srs--rating-symbol (rating)
  "Return plain semantic symbol for Org-srs RATING keyword."
  (when rating
    (intern (string-remove-prefix ":" (symbol-name rating)))))

(defun emacsvox-org-srs--format-interval (seconds)
  "Return a concise spoken description of SECONDS."
  (let* ((seconds (max 0 (round seconds)))
         (units '((86400 . "day") (3600 . "hour")
                  (60 . "minute") (1 . "second")))
         (remaining seconds)
         parts)
    (dolist (unit units)
      (when (and (> remaining 0) (< (length parts) 2))
        (let* ((size (car unit))
               (amount (/ remaining size)))
          (when (> amount 0)
            (push (format "%d %s%s" amount (cdr unit)
                          (if (= amount 1) "" "s"))
                  parts)
            (setq remaining (% remaining size))))))
    (if parts (string-join (nreverse parts) " and ") "now")))

(defun emacsvox-org-srs--after-rate ()
  "Capture the rating and next due interval for the next announcement."
  (let* ((rating (emacsvox-org-srs--rating-symbol org-srs-review-rating))
         (due (ignore-errors (apply #'org-srs-item-due-time org-srs-review-item)))
         (interval
          (and due
               (max 0 (round (org-srs-time-difference
                              due (org-srs-time-now))))))
         (label (if rating (capitalize (symbol-name rating)) "Rated")))
    (setq emacsvox-org-srs--pending-result
          (list
           :event 'learning-item-rated
           :rating rating
           :interval interval
           :text
           (if interval
               (format "%s. Next review in %s."
                       label (emacsvox-org-srs--format-interval interval))
             (concat label "."))))))

(defun emacsvox-org-srs--finish ()
  "Speak completion of the current Org-srs review session."
  (let* ((pending (emacsvox-org-srs--consume-pending-result))
         (content
          (string-join
           (delq nil (list (plist-get pending :text) "Review complete."))
           " "))
         (facts
          (append
           (list :role 'learning-session
                 :events '(learning-session-finished)
                 :learning-phase 'result)
           (let ((rating (plist-get pending :rating)))
             (when rating (list :learning-rating rating)))
           (let ((interval (plist-get pending :interval)))
             (when interval (list :learning-next-interval interval))))))
    (setq emacsvox-org-srs--session-active-p nil)
    (let ((emacsvox-speak-messages nil))
      (message "Review complete"))
    (emacsvox-org-srs--submit content facts 'notification)))

(defun emacsvox-org-srs-speak-current ()
  "Repeat the current Org-srs question or revealed answer."
  (interactive)
  (unless emacsvox-org-srs--current-type
    (user-error "There is no current Org-srs review item"))
  (let* ((answer-p (eq emacsvox-org-srs--phase 'answer))
         (label (if answer-p "Answer: " "Question: "))
         (event (if answer-p
                    'learning-answer-revealed
                  'learning-question-presented)))
    (emacsvox-org-srs--submit
     (concat label
             (emacsvox-org-srs--item-content
              emacsvox-org-srs--current-type
              emacsvox-org-srs--current-args
              answer-p))
     (list :role 'learning-item
           :events (list event)
           :learning-phase (if answer-p 'answer 'question)
           :learning-item-kind
           (emacsvox-org-srs--item-kind emacsvox-org-srs--current-type))
     'notification)))

(defun emacsvox-org-srs--queue-operation (event text)
  "Queue an Org-srs operation EVENT and TEXT for the next question."
  (setq emacsvox-org-srs--pending-result
        (list :event event :text text)))

(defun emacsvox-org-srs--around-postpone (original &rest args)
  "Announce an interactive postpone around ORIGINAL with ARGS."
  (when (ems-interactive-p 'org-srs-review-postpone)
    (emacsvox-org-srs--queue-operation
     'learning-item-postponed "Item postponed."))
  (apply original args))

(defun emacsvox-org-srs--around-quit (original &rest args)
  "Suppress answer reveal while quitting via ORIGINAL with ARGS."
  (let ((interactive-p (ems-interactive-p 'org-srs-review-quit))
        (emacsvox-org-srs--suppress-answer t))
    (prog1 (apply original args)
      (when interactive-p
        (setq emacsvox-org-srs--session-active-p nil
              emacsvox-org-srs--pending-result nil)
        (emacsvox-org-srs--submit
         "Review stopped."
         '(:role learning-session :events (learning-session-stopped)
           :learning-phase result)
         'notification)))))

(defun emacsvox-org-srs--around-suspend (original &rest args)
  "Announce an interactive suspension around ORIGINAL with ARGS."
  (when (ems-interactive-p 'org-srs-review-suspend)
    (emacsvox-org-srs--queue-operation
     'learning-item-suspended "Item suspended."))
  (apply original args))

(defun emacsvox-org-srs--around-undo (original &rest args)
  "Announce an interactive rating undo around ORIGINAL with ARGS."
  (when (ems-interactive-p 'org-srs-review-undo)
    (emacsvox-org-srs--queue-operation
     'learning-rating-undone "Rating undone."))
  (apply original args))

(defun emacsvox-org-srs--around-redo (original &rest args)
  "Announce an interactive rating redo around ORIGINAL with ARGS."
  (when (ems-interactive-p 'org-srs-review-undo-redo)
    (emacsvox-org-srs--queue-operation
     'learning-rating-redone "Rating restored."))
  (apply original args))

(defun emacsvox-org-srs--after-create (&rest _)
  "Announce interactive creation of an Org-srs item."
  (when (ems-interactive-p 'org-srs-item-create)
    (emacsvox-org-srs--submit
     "Spaced-repetition item created."
     '(:role learning-item :events (learning-item-created)
       :learning-phase result)
     'edit)))

(defun emacsvox-org-srs--after-cloze-update (&rest _)
  "Announce an interactive update of Org-srs cloze items."
  (when (ems-interactive-p 'org-srs-item-cloze-update)
    (emacsvox-org-srs--submit
     "Cloze items updated."
     '(:role learning-item :events (learning-cloze-updated)
       :learning-phase result :learning-item-kind cloze)
     'edit)))

(defun emacsvox-org-srs--install ()
  "Install Emacsvox support for the loaded Org-srs package."
  (when emacsvox-org-srs-use-command-confirmation
    (setq org-srs-item-confirm #'org-srs-item-confirm-command))
  (remove-hook 'org-srs-review-finish-hook
               #'org-srs-review-message-review-done)
  (add-hook 'org-srs-item-before-confirm-hook
            #'emacsvox-org-srs--before-confirm)
  (add-hook 'org-srs-item-after-review-hook
            #'emacsvox-org-srs--after-review)
  (add-hook 'org-srs-review-after-rate-hook
            #'emacsvox-org-srs--after-rate)
  (add-hook 'org-srs-review-finish-hook #'emacsvox-org-srs--finish)
  (dolist (advice
           '((org-srs-review-postpone . emacsvox-org-srs--around-postpone)
             (org-srs-review-quit . emacsvox-org-srs--around-quit)
             (org-srs-review-suspend . emacsvox-org-srs--around-suspend)
             (org-srs-review-undo . emacsvox-org-srs--around-undo)
             (org-srs-review-undo-redo . emacsvox-org-srs--around-redo)))
    (unless (advice-member-p (cdr advice) (car advice))
      (advice-add (car advice) :around (cdr advice))))
  (dolist (advice
           '((org-srs-item-create . emacsvox-org-srs--after-create)
             (org-srs-item-cloze-update . emacsvox-org-srs--after-cloze-update)))
    (unless (advice-member-p (cdr advice) (car advice))
      (advice-add (car advice) :after (cdr advice)))))

(emacsvox-org-srs--install)

(provide 'emacsvox-org-srs)

;;; emacsvox-org-srs.el ends here
