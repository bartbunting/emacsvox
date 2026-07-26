;;; emacsvox-gnus.el --- Speech enable Gnus   -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $ 
;; Description:  Emacsvox extension to speech enable Gnus
;; Keywords: Emacsvox, Gnus, Advice, Spoken Output, News
;;;   LCD Archive entry: 

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com 
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ | 
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:
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

;; This module advises gnus to speak. 
;; Updating support in 2014 (Emacsvox is nearly 20 years old)
;; Updating in 2018 as I switch to gnus as my primary mail interface.
;; These customizations to gnus make it convenient to listen to news:
;; You can read news mostly by using the four arrow keys.
;; By default all article headers are hidden, so you hear the real news.

;;; Code:

;;; Forward variable declarations:

(defvar emacsvox-gnus-large-article)
(defvar gnus-article-buffer)
(defvar gnus-article-mode-map)
(defvar gnus-group-mmode-map)
(defvar gnus-summary-mode-map)
(defvar tts-punctuation-mode)
(defvar voice-lock-mode)

;;;  requires

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'emacsvox-aural-transport)
(require 'emacsvox-aural-representative)
(require 'emacsvox-hide)
(require 'gnus)
(require 'gnus-art)
(require 'gnus-sum)
(with-suppressed-warnings ((obsolete nnir)) (require 'gm-nnir)) 

;;;   Customizations:

(defgroup emacsvox-gnus nil
  "Emacsvox customizations for the Gnus News/Mail/RSS reader"
  :group 'emacsvox
  :group 'gnus
  :prefix "emacsvox-gnus-")

(defcustom emacsvox-gnus-punctuation-mode  'all
  "Pronunciation mode to use for gnus buffers."
  :type '(choice
          (const  :tag "Ignore" nil)
          (const  :tag "some" some)
          (const  :tag "all" all))
  :group 'emacsvox-gnus)

(defcustom  emacsvox-gnus-large-article 100
  "Articles having more than
emacsvox-gnus-large-article lines will be considered to be a large article.
A large article is not spoken all at once;
instead you hear only the first screenful."
  :type 'integer
  :group 'emacsvox-gnus 
  )

;; Keybindings 
(defun emacsvox-gnus-setup-keys ()
  "Setup Emacsvox keys."
  (define-key gnus-summary-mode-map "\C-t" 'gnus-summary-toggle-header)
  (define-key gnus-summary-mode-map "t" 'gnus-summary-toggle-header)
  (define-key
   gnus-summary-mode-map
   '[left] 'emacsvox-gnus-summary-catchup-quietly-and-exit)
  (define-key gnus-summary-mode-map '[right] 'gnus-summary-show-article)
  (define-key gnus-group-mode-map "/" 'gm-nnir-group-make-gmail-group)
  (define-key gnus-group-mode-map ";" 'emacsvox-gnus-personal-gmail-recent)
  (define-key gnus-group-mode-map ":" 'emacsvox-gnus-personal-gmail-last-week)
  (define-key gnus-group-mode-map "\C-n" 'gnus-group-next-group)
  (define-key gnus-group-mode-map [down] 'gnus-group-next-group)
  (define-key gnus-group-mode-map [up] 'gnus-group-prev-group)
  (define-key gnus-group-mode-map "\C-p" 'gnus-group-prev-group)
  (define-key gnus-summary-wash-map "D" 'gnus-summary-downcase-article)
  (define-key gnus-group-mode-map '[right]
              'gnus-group-read-group))

(add-hook 'gnus-started-hook 'emacsvox-gnus-setup-keys)

;;;   helper functions

(defun emacsvox-gnus-enable-aural-context ()
  "Identify the current Gnus buffer to aural presentation schemes."
  (setq-local emacsvox-aural-module 'gnus))

(dolist
    (hook
     '(gnus-group-mode-hook gnus-summary-mode-hook gnus-article-mode-hook))
  (add-hook hook #'emacsvox-gnus-enable-aural-context))

(defun emacsvox-gnus-message-facts (&optional event extra-states)
  "Return semantic facts for the current Gnus message.

EVENT names a presentation event and EXTRA-STATES records an operation whose
new Gnus mark is not otherwise portable."
  (let ((mark
         (and
          (fboundp 'gnus-summary-article-mark)
          (ignore-errors (gnus-summary-article-mark))))
        (states (copy-sequence extra-states)))
    (when
        (and
         (boundp 'gnus-unread-mark)
         (equal mark gnus-unread-mark))
      (push 'unread states))
    (when
        (or
         (and (boundp 'gnus-ticked-mark)
              (equal mark gnus-ticked-mark))
         (and (boundp 'gnus-dormant-mark)
              (equal mark gnus-dormant-mark)))
      (push 'flagged states))
    (append
     (list :role 'message)
     (when event (list :events (list event)))
     (when states (list :states (delete-dups (nreverse states)))))))

(defun emacsvox-gnus-present-subject
    (icon occasion event &optional extra-states)
  "Present the current subject with ICON and semantic message context."
  (let* ((facts (emacsvox-gnus-message-facts event extra-states))
         (context (emacsvox-aural-capture-context 'gnus occasion))
         (emacsvox-aural-submission-facts facts)
         (emacsvox-aural-submission-context context)
         (emacsvox-aural-submission-module 'gnus)
         (emacsvox-aural-submission-occasion occasion))
    (when icon (emacsvox-icon icon))
    (emacsvox-gnus-summary-speak-subject)))

(defun emacsvox-gnus-present-group
    (icon occasion event speaker &optional icon-after)
  "Present a mail group using ICON, OCCASION, EVENT, and SPEAKER.

When ICON-AFTER is non-nil, preserve speaker-before-icon ordering."
  (let* ((facts
          (append
           (list :role 'mail-group)
           (when event (list :events (list event)))))
         (context (emacsvox-aural-capture-context 'gnus occasion))
         (emacsvox-aural-submission-facts facts)
         (emacsvox-aural-submission-context context)
         (emacsvox-aural-submission-module 'gnus)
         (emacsvox-aural-submission-occasion occasion))
    (if icon-after
        (progn
          (funcall speaker)
          (when icon (emacsvox-icon icon)))
      (when icon (emacsvox-icon icon))
      (funcall speaker))))

(defun emacsvox-gnus-summary-speak-subject ()
  "Speak the current Gnus subject with semantic message context."
  (let* ((facts
          (or
           emacsvox-aural-submission-facts
           (emacsvox-gnus-message-facts 'focus-entered)))
         (context
          (or
           emacsvox-aural-submission-context
           (emacsvox-aural-capture-context 'gnus 'navigation)))
         (emacsvox-aural-submission-facts facts)
         (emacsvox-aural-submission-context context)
         (emacsvox-aural-submission-module 'gnus)
         (emacsvox-aural-submission-occasion
          (or emacsvox-aural-submission-occasion 'navigation)))
    (tts-speak (gnus-summary-article-subject))))

(defun emacsvox-gnus-speak-article-body ()
  (with-current-buffer gnus-article-buffer
    (goto-char (point-min))
    (search-forward "\n\n")
    (cond
     ((< (count-lines (point) (point-max))
         emacsvox-gnus-large-article)
      (emacsvox-speak-rest-of-buffer))
     (t (emacsvox-icon 'large-movement)
        (let ((start (point))
              (window (get-buffer-window (current-buffer))))
          (with-selected-window window
            (save-excursion
              (move-to-window-line -1)
              (end-of-line)
              (emacsvox-speak-region start (point)))))))))

;;;  Advise top-level gnus command

;; emacs can hang if too many message sfly by as gnus starts

(defun emacsvox--advice-gnus-around (original &rest arguments)
  "Run ORIGINAL with silenced messages and cue Gnus startup."
  (tts-speak "Starting gnus")
  (let ((result
         (ems-with-messages-silenced
           (apply original arguments))))
    (emacsvox-gnus-present-group
     'news 'notification 'refresh-completed
     (lambda () (message "Gnus is ready ")))
    result))

(advice-add
 'gnus :around #'emacsvox--advice-gnus-around
 '((name . emacsvox)))

(cl-loop
 for target in
 '(gnus-group-suspend gnus-group-quit
   gnus-group-exit gnus-server-exit)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactively leaving a Gnus view."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'close-object)
         (tts-stop)
         (emacsvox-speak-mode-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

;;;   starting up:

(defun emacsvox--advice-gnus-group-post-news-after (&rest _)
  "Cue and speak after interactively starting a Gnus post."
  (when (ems-interactive-p 'gnus-group-post-news)
    (emacsvox-icon 'open-object)
    (emacsvox-speak-line)))

(advice-add
 'gnus-group-post-news :after
 #'emacsvox--advice-gnus-group-post-news-after
 '((name . emacsvox)))

(defun emacsvox--advice-gnus-group-get-new-news-around
    (original &rest arguments)
  "Run ORIGINAL with silenced messages and cue the news refresh."
  (tts-speak "Getting new  gnus")
  (let ((result
         (ems-with-messages-silenced
           (apply original arguments))))
    (emacsvox-gnus-present-group
     'news 'notification 'refresh-completed
     (lambda () (message "Gnus is ready ")) t)
    result))

(advice-add
 'gnus-group-get-new-news :around
 #'emacsvox--advice-gnus-group-get-new-news-around
 '((name . emacsvox)))

(defun emacsvox--advice-nnheader-message-maybe-around
    (original &rest arguments)
  "Run ORIGINAL with Emacsvox messages silenced."
  (ems-with-messages-silenced
    (apply original arguments)))

(advice-add
 'nnheader-message-maybe :around
 #'emacsvox--advice-nnheader-message-maybe-around
 '((name . emacsvox)))

;;;   Newsgroup selection

(cl-loop
 for target in
 '(
   gnus-group-select-group gnus-group-first-unread-group
   gnus-group-read-group
   gnus-group-prev-group gnus-group-next-group
   gnus-group-prev-unread-group  gnus-group-next-unread-group
   gnus-group-get-new-news-this-group)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactive Gnus group movement."
       (when (ems-interactive-p ',target)
         (emacsvox-gnus-present-group
          'select-object 'navigation 'focus-entered
          #'emacsvox-speak-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-gnus-group-unsubscribe-current-group-after
    (&rest _)
  "Produce an auditory icon indicating\nthis group is being deselected."
  (when (ems-interactive-p 'gnus-group-unsubscribe-current-group)
    (emacsvox-icon 'deselect-object)
    (emacsvox-speak-line)))

(advice-add
 'gnus-group-unsubscribe-current-group :after
 #'emacsvox--advice-gnus-group-unsubscribe-current-group-after
 '((name . emacsvox)))

(defun emacsvox--advice-gnus-group-catchup-current-after (&rest _)
  "speak.\n Produce an auditory icon if possible."
  (when (ems-interactive-p 'gnus-group-catchup-current)
    (emacsvox-icon 'close-object)
    (emacsvox-speak-line)))

(advice-add
 'gnus-group-catchup-current :after
 #'emacsvox--advice-gnus-group-catchup-current-after
 '((name . emacsvox)))

(defun emacsvox--advice-gnus-group-yank-group-after (&rest _)
  "speak.\n Produce an auditory icon if possible."
  (when (ems-interactive-p 'gnus-group-yank-group)
    (emacsvox-icon 'yank-object)
    (emacsvox-speak-line)))

(advice-add
 'gnus-group-yank-group :after
 #'emacsvox--advice-gnus-group-yank-group-after
 '((name . emacsvox)))

(defun emacsvox--advice-gnus-group-list-groups-after (&rest _)
  "speak.\n Produce an auditory icon if possible."
  (when (ems-interactive-p 'gnus-group-list-groups)
    (emacsvox-icon 'open-object)
    (tts-speak "Listing groups... done")))

(advice-add
 'gnus-group-list-groups :after
 #'emacsvox--advice-gnus-group-list-groups-after
 '((name . emacsvox)))

(defun emacsvox--advice-gnus-topic-mode-after (&rest _)
  "speak.\n Produce an auditory icon if possible."
  (when (ems-interactive-p 'gnus-topic-mode)
    (emacsvox-icon 'open-object)
    (tts-speak "toggled topic mode")))

(advice-add
 'gnus-topic-mode :after
 #'emacsvox--advice-gnus-topic-mode-after
 '((name . emacsvox)))

(defun emacsvox--advice-gnus-group-list-all-groups-after (&rest _)
  "speak.\n Produce an auditory icon if possible."
  (when (ems-interactive-p 'gnus-group-list-all-groups)
    (emacsvox-icon 'open-object)
    (tts-speak "Listing all groups... done")))

(advice-add
 'gnus-group-list-all-groups :after
 #'emacsvox--advice-gnus-group-list-all-groups-after
 '((name . emacsvox)))

(defun emacsvox--advice-gnus-group-list-all-matching-after (&rest _)
  "speak.\n Produce an auditory icon if possible."
  (when (ems-interactive-p 'gnus-group-list-all-matching)
    (emacsvox-icon 'open-object)
    (tts-speak "Listing all matching groups... done")))

(advice-add
 'gnus-group-list-all-matching :after
 #'emacsvox--advice-gnus-group-list-all-matching-after
 '((name . emacsvox)))

(defun emacsvox--advice-gnus-group-list-killed-after (&rest _)
  "speak.\n Produce an auditory icon if possible."
  (when (ems-interactive-p 'gnus-group-list-killed)
    (emacsvox-icon 'open-object)
    (tts-speak "Listing killed groups... done")))

(advice-add
 'gnus-group-list-killed :after
 #'emacsvox--advice-gnus-group-list-killed-after
 '((name . emacsvox)))

(defun emacsvox--advice-gnus-group-list-matching-after (&rest _)
  "speak.\n Produce an auditory icon if possible."
  (when (ems-interactive-p 'gnus-group-list-matching)
    (emacsvox-icon 'open-object)
    (emacsvox-pip
     "listing matching groups with unread articles... done")))

(advice-add
 'gnus-group-list-matching :after
 #'emacsvox--advice-gnus-group-list-matching-after
 '((name . emacsvox)))

(defun emacsvox--advice-gnus-group-list-zombies-after (&rest _)
  "speak.\n Produce an auditory icon if possible."
  (when (ems-interactive-p 'gnus-group-list-zombies)
    (emacsvox-icon 'open-object)
    (tts-speak "Listing zombie groups... done")))

(advice-add
 'gnus-group-list-zombies :after
 #'emacsvox--advice-gnus-group-list-zombies-after
 '((name . emacsvox)))

(defun emacsvox--advice-gnus-group-customize-before (&rest _)
  "speak.\n Produce an auditory icon if possible."
  (when (ems-interactive-p 'gnus-group-customize)
    (emacsvox-icon 'open-object)
    (message "Customizing group %s" (gnus-group-group-name))))

(advice-add
 'gnus-group-customize :before
 #'emacsvox--advice-gnus-group-customize-before
 '((name . emacsvox)))

;;;   summary mode 

(cl-loop
 for target in
 '(
   gnus-summary-clear-mark-backward gnus-summary-clear-mark-forward
   gnus-summary-mark-as-dormant gnus-summary-mark-as-expirable
   gnus-summary-mark-as-processable
   gnus-summary-tick-article-backward gnus-summary-tick-article-forward
   )
 for function = (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(progn
     (defun ,function (original &rest arguments)
       "Mark via ORIGINAL once, then report interactive movement."
       (let ((saved-point (point)))
         (let ((result (apply original arguments)))
           (when (ems-interactive-p ',target)
             (if (= saved-point (point))
                 (emacsvox-pip "No more articles")
               (emacsvox-gnus-present-subject
                'mark-object 'state-change 'message-marked '(marked))))
           result)))
     (advice-add
      ',target :around #',function '((name . emacsvox))))))

(defun emacsvox--advice-gnus-summary-unmark-as-processable-after
    (&rest _)
  "Speak the line.\n Produce an auditory icon if possible."
  (when (ems-interactive-p 'gnus-summary-unmark-as-processable)
    (emacsvox-gnus-present-subject
     'deselect-object 'state-change 'message-marked)))

(advice-add
 'gnus-summary-unmark-as-processable :after
 #'emacsvox--advice-gnus-summary-unmark-as-processable-after
 '((name . emacsvox)))

(defun emacsvox--advice-gnus-summary-delete-article-after (&rest _)
  "Speak the line.\n Produce an auditory icon if possible."
  (when (ems-interactive-p 'gnus-summary-delete-article)
    (emacsvox-gnus-present-subject
     'delete-object 'state-change 'message-deleted)))

(advice-add
 'gnus-summary-delete-article :after
 #'emacsvox--advice-gnus-summary-delete-article-after
 '((name . emacsvox)))

(cl-loop
 for target in
 '(gnus-summary-catchup-to-here gnus-summary-catchup-from-here)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactively catching up articles."
       (when (ems-interactive-p ',target)
         (emacsvox-gnus-present-subject
          'mark-object 'state-change 'message-marked '(marked))))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-gnus-summary-select-article-buffer-after
    (&rest _)
  "Speak the modeline.\nIndicate change of selection with\n  an auditory icon if possible."
  (when (ems-interactive-p 'gnus-summary-select-article-buffer)
    (emacsvox-icon 'select-object)
    (emacsvox-speak-mode-line)))

(advice-add
 'gnus-summary-select-article-buffer :after
 #'emacsvox--advice-gnus-summary-select-article-buffer-after
 '((name . emacsvox)))

(cl-loop
 for target in
 '(gnus-summary-exit-no-update gnus-summary-exit)
 for function = (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(progn
     (defun ,function (original &rest arguments)
       "Exit via ORIGINAL once and describe the selected Gnus group."
       (let ((current-group gnus-newsgroup-name))
         (let ((result (apply original arguments)))
           (when (ems-interactive-p ',target)
             (emacsvox-icon 'close-object)
             (tts-stop)
             (if (eq current-group (gnus-group-group-name))
                 (emacsvox-pip "No more unread newsgroups")
               (emacsvox-speak-line)))
           result)))
     (advice-add
      ',target :around #',function '((name . emacsvox))))))

(cl-loop
 for target in
 '(gnus-summary-prev-subject
   gnus-summary-next-subject
   gnus-summary-prev-unread-subject
   gnus-summary-next-unread-subject
   gnus-summary-goto-subject)
 for no-more-message in
 '("No more articles "
   "No more articles "
   "No more unread articles "
   "No more articles "
   "No more articles ")
 for function = (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(progn
     (defun ,function (original &rest arguments)
       "Move via ORIGINAL once and speak the resulting Gnus subject."
       (let ((saved-point (point)))
         (let ((result (apply original arguments)))
           (when (ems-interactive-p ',target)
             (if (= saved-point (point))
                 (emacsvox-pip ,no-more-message)
               (emacsvox-gnus-present-subject
                'select-object 'navigation 'focus-entered)))
           result)))
     (advice-add
      ',target :around #',function '((name . emacsvox))))))

(defun emacsvox--advice-gnus-summary-catchup-and-exit-after
    (&rest _)
  "Speak the newsgroup line.\n Produce an auditory icon indicating \nthe previous group was closed."
  (when (ems-interactive-p 'gnus-summary-catchup-and-exit)
    (emacsvox-icon 'close-object)
    (emacsvox-speak-line)))

(advice-add
 'gnus-summary-catchup-and-exit :after
 #'emacsvox--advice-gnus-summary-catchup-and-exit-after
 '((name . emacsvox)))

(cl-loop
 for target in
 '(gnus-summary-mark-as-read-forward
   gnus-summary-mark-as-read-backward)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactively marking articles as read."
       (when (ems-interactive-p ',target)
         (emacsvox-gnus-present-subject
          'mark-object 'state-change 'message-marked '(marked))))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-gnus-summary-kill-same-subject-and-select-after
    (&rest _)
  "Speak the subject and speak the first screenful.\nProduce an auditory icon\nindicating the article is being opened."
  
  (when
      (ems-interactive-p
       'gnus-summary-kill-same-subject-and-select)
    (emacsvox-gnus-summary-speak-subject)
    (sit-for 2)
    (emacsvox-icon 'open-object)
    (with-current-buffer gnus-article-buffer
      (let
          ((start (point))
           (window (get-buffer-window (current-buffer))))
        (with-selected-window window
          (save-excursion
            (move-to-window-line -1) (end-of-line)
            (emacsvox-speak-region start (point))))))))

(advice-add
 'gnus-summary-kill-same-subject-and-select :after
 #'emacsvox--advice-gnus-summary-kill-same-subject-and-select-after
 '((name . emacsvox)))

(cl-loop
 for target in
 '(gnus-summary-kill-same-subject
   gnus-summary-next-thread gnus-summary-prev-thread
   gnus-summary-up-thread gnus-summary-down-thread
   gnus-summary-kill-thread)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactive Gnus thread movement."
       (when (ems-interactive-p ',target)
         (emacsvox-gnus-present-subject
          'select-object 'navigation 'focus-entered)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-gnus-summary-hide-all-threads-after (&rest _)
  "speak."
  (when (ems-interactive-p 'gnus-summary-hide-all-threads)
    (emacsvox-icon 'close-object)
    (emacsvox-speak-line)))

(advice-add
 'gnus-summary-hide-all-threads :after
 #'emacsvox--advice-gnus-summary-hide-all-threads-after
 '((name . emacsvox)))

;;;   Article reading

(defun emacsvox-gnus-summary-catchup-quietly-and-exit ()
  "Catch up on all articles in current group."
  (interactive)
  (gnus-summary-catchup-and-exit t t)
  (emacsvox-icon 'close-object)
  (emacsvox-speak-line))

(cl-loop
 for target in
 '(gnus-summary-read-group gnus-summary-show-article)
 for function = (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(progn
     (defun ,function (original &rest arguments)
       "Call ORIGINAL without Emacsvox's external SHR renderers."
       (let ((shr-external-rendering-functions nil))
         (apply original arguments)))
     (advice-add
      ',target :around #',function
      '((name . emacsvox-disable-shr))))))

(defun emacsvox--advice-gnus-summary-show-article-after (&rest _)
  "Start speaking the article. "
  (when (ems-interactive-p 'gnus-summary-show-article)
    (with-current-buffer gnus-article-buffer
      (let* ((facts (emacsvox-gnus-message-facts 'message-opened))
             (context
              (emacsvox-aural-capture-context 'gnus 'state-change))
             (emacsvox-aural-submission-facts facts)
             (emacsvox-aural-submission-context context)
             (emacsvox-aural-submission-module 'gnus)
             (emacsvox-aural-submission-occasion 'state-change))
        (visual-line-mode)
        (emacsvox-icon 'open-object)
        (condition-case nil
            (emacsvox-hide-all-blocks-in-buffer)
          (error nil))
        (emacsvox-gnus-speak-article-body)))))

(advice-add
 'gnus-summary-show-article :after
 #'emacsvox--advice-gnus-summary-show-article-after
 '((name . emacsvox)))

(cl-loop
 for target in
 '(gnus-summary-next-page gnus-summary-prev-page)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak the visible article page."
       (tts-stop 'all)
       (emacsvox-icon 'scroll)
       (with-current-buffer gnus-article-buffer
         (let ((start (point))
               (window (get-buffer-window (current-buffer))))
           (with-selected-window window
             (save-excursion
               (move-to-window-line -1)
               (end-of-line)
               (emacsvox-speak-region start (point)))))))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in
 '(gnus-summary-beginning-of-article
   gnus-summary-end-of-article)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak the current line in the Gnus article buffer."
       (with-current-buffer gnus-article-buffer
         (emacsvox-speak-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in
 '(gnus-summary-prev-article gnus-summary-next-article
   gnus-summary-next-unread-article
   gnus-summary-prev-unread-article
   gnus-summary-prev-same-subject
   gnus-summary-next-same-subject
   gnus-summary-first-unread-article
   gnus-summary-goto-last-article)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak after interactive movement to a Gnus article."
       (when (ems-interactive-p ',target)
         (emacsvox-gnus-speak-article-body)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-gnus-article-show-summary-after (&rest _)
  "Speak the modeline.\nIndicate change of selection with\n  an auditory icon if possible."
  (when (ems-interactive-p 'gnus-article-show-summary)
    (emacsvox-icon 'select-object)
    (emacsvox-speak-mode-line)))

(advice-add
 'gnus-article-show-summary :after
 #'emacsvox--advice-gnus-article-show-summary-after
 '((name . emacsvox)))

(cl-loop
 for target in
 '(gnus-article-next-page gnus-article-prev-page)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak the current window after interactive article scrolling."
       (when (ems-interactive-p ',target)
         (emacsvox-speak-current-window)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-gnus-summary-button-forward-after (&rest _)
  "Cue and identify the current Gnus article button."
  (when (ems-interactive-p 'gnus-summary-button-forward)
    (let ((button (button-at (point))))
      (emacsvox-icon 'large-movement)
      (when button
        (message "%s" (button-label button))))))

(advice-add
 'gnus-summary-button-forward :after
 #'emacsvox--advice-gnus-summary-button-forward-after
 '((name . emacsvox)))

(defun emacsvox--advice-gnus-article-press-button-before (&rest _)
  "Cue before interactively pressing a Gnus article button."
  (when (ems-interactive-p 'gnus-article-press-button)
    (emacsvox-icon 'button)))

(advice-add
 'gnus-article-press-button :before
 #'emacsvox--advice-gnus-article-press-button-before
 '((name . emacsvox)))

(cl-loop
 for target in
 '(gnus-article-goto-prev-page gnus-article-goto-next-page)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactive Gnus article page movement."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'scroll)
         (sit-for 1)
         (emacsvox-speak-current-window)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun gnus-summary-downcase-article ()
  "Downcases the article body
Helps to prevent words from being spelled instead of spoken."
  (interactive)
  (gnus-summary-select-article-buffer)
  (article-goto-body)
  (let ((beg (point))
        (end (point-max))
        (inhibit-read-only t))
    (downcase-region beg end))
  (gnus-article-show-summary)
  (emacsvox-icon 'modified-object)
  (tts-speak "Downcased article body"))

;;;  refreshing the pronunciation  and punctuation mode

(cl-loop
 for hook  in 
 '(
   gnus-article-mode-hook gnus-group-mode-hook gnus-summary-mode-hook
   gnus-agent-mode-hook  gnus-article-edit-mode-hook
   gnus-server-mode-hook gnus-category-mode-hook
   )
 do
 (add-hook
  hook 
  #'(lambda ()
      (tts-set-punctuations emacsvox-gnus-punctuation-mode)
      (emacsvox-pronounce-refresh-pronunciations))))

;;;  rdc: mapping font faces to personalities 

;; article buffer personalities

;; Since citation does not normally go beyond 4 levels deep, in my 
;; experience, there are separate voices for the first four levels
;; and then they are repeated
(voice-setup-add-map
 '(
   (gnus-button voice-bolden)
   (gnus-cite-attribution voice-smoothen)
   (gnus-emphasis-bold-italic voice-animate)
   (gnus-emphasis-underline-bold voice-lighten) 
   (gnus-emphasis-underline-bold-italic  voice-lighten-extra)
   (gnus-emphasis-underline-italic voice-lighten)
   (gnus-group-mail-1  voice-brighten)
   (gnus-group-mail-2  voice-animate)
   (gnus-group-mail-3  voice-lighten)
   (gnus-group-mail-low voice-smoothen)
   (gnus-group-news-1  voice-animate) 
   (gnus-group-news-2  voice-lighten)
   (gnus-group-news-3  voice-brighten)
   (gnus-group-news-4  voice-lighten)
   (gnus-group-news-5 voice-smoothen) 
   (gnus-group-news-6 voice-annotate)
   (gnus-group-news-low  voice-smoothen-extra)
   (gnus-server-cloud  voice-animate)
   (gnus-server-cloud-host  voice-lighten)
   (gnus-splash  voice-brighten) 
   (gnus-summary-high-undownloaded voice-animate)
   (gnus-summary-normal-unread  voice-bolden)
   (gnus-x-face voice-monotone-extra)
   (gnus-cite-1 voice-bolden-medium)
   (gnus-cite-2 voice-lighten) 
   (gnus-cite-3 voice-lighten-extra)
   (gnus-cite-4 voice-smoothen)
   (gnus-cite-5 voice-smoothen-extra)
   (gnus-cite-6 voice-lighten)
   (gnus-cite-7 voice-lighten-extra)
   (gnus-cite-8 voice-bolden)
   (gnus-cite-9 voice-bolden-medium)
   (gnus-cite-10 voice-lighten)
   (gnus-cite-11 voice-lighten-extra)
   (gnus-emphasis-highlight-words voice-lighten-extra)
   (gnus-emphasis-bold voice-bolden-and-animate)
   (gnus-emphasis-strikethru voice-bolden-extra)
   (gnus-emphasis-italic voice-lighten)
   (gnus-emphasis-underline voice-brighten-extra)
   (gnus-signature voice-animate)
   (gnus-header-content voice-bolden)
   (gnus-header-name voice-animate)
   (gnus-header-from voice-bolden)
   (gnus-header-newsgroups voice-bolden)
   (gnus-header-subject voice-bolden)
   ;; ;; summary buffer personalities
   ;; since there are so many distinctions, most variations
   ;; on the same thing are given the same voice.  Any user that
   ;; uses low and high interest is sufficiently advanced to change
   ;; the voice to his own preferences
   (gnus-summary-normal-read voice-smoothen)
   (gnus-summary-high-read voice-bolden)
   (gnus-summary-low-read voice-bolden)
   (gnus-summary-normal-ticked voice-brighten-extra)
   (gnus-summary-high-ticked voice-brighten-extra)
   (gnus-summary-low-ticked voice-brighten-extra)
   (gnus-summary-normal-ancient voice-smoothen-extra)
   (gnus-summary-high-ancient voice-smoothen-extra)
   (gnus-summary-low-ancient voice-smoothen-extra)
   (gnus-summary-normal-undownloaded voice-bolden-and-animate)
   (gnus-summary-low-undownloaded voice-bolden-and-animate)
   (gnus-summary-low-unread voice-bolden-medium)
   (gnus-summary-high-unread voice-brighten-extra)
   (gnus-summary-selected voice-animate-extra)
   (gnus-summary-cancelled voice-bolden-extra)
   ;; group buffer personalities
   ;; I think the voice used for the groups in the buffer should be the 
   ;; default voice.  I might ask if there is a call for different voices 
   ;; as they are only necessary if users have persistently visible groups
   ;; in the case of empty groups, and voices for the various levels.
   (gnus-group-mail-1-empty voice-monotone-extra)
   (gnus-group-mail-2-empty voice-monotone-extra)
   (gnus-group-mail-3-empty  voice-monotone-extra)
   (gnus-group-mail-low-empty voice-monotone-extra)
   (gnus-group-news-1-empty voice-monotone-extra)
   (gnus-group-news-2-empty voice-monotone-extra)
   (gnus-group-news-3-empty voice-monotone-extra)
   (gnus-group-news-4-empty voice-monotone-extra)
   (gnus-group-news-5-empty voice-monotone-extra)
   (gnus-group-news-6-empty voice-monotone-extra)
   (gnus-group-news-low-empty voice-monotone-extra)
   ;; server buffer personalities
   (gnus-server-agent voice-bolden)
   (gnus-server-closed voice-bolden-medium)
   (gnus-server-denied voice-bolden-extra)
   (gnus-server-offline voice-animate)
   (gnus-server-opened voice-lighten)))

;;;  server mode:

(cl-loop
 for target in
 '(gnus-server-edit-server gnus-group-enter-server-mode gnus-browse-exit)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak the mode line after interactive Gnus server navigation."
       (when (ems-interactive-p ',target)
         (emacsvox-speak-mode-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

;;;  Async Gnus:

;;;  GMail Search Accelerators:

(defun emacsvox-gnus-personal-gmail-recent ()
  "Look for mail addressed personally in the last day."
  (interactive)
  (gm-nnir-group-make-gmail-group
   (format "newer_than:1d to:me -cc:%s" user-mail-address)))

(defun emacsvox-gnus-personal-gmail-last-week()
  "Look for mail addressed personally in the last week."
  (interactive)
  (gm-nnir-group-make-gmail-group
   (format
    "after:%s before:%s to:me -cc:%s"
    (format-time-string "%Y/%m/%d" (time-subtract (current-time) (* 7 86400)))
    (format-time-string "%Y/%m/%d")
    user-mail-address)))

;;; xoauth2

(defun emacsvox--advice-auth-source-do-debug-around
    (original &rest arguments)
  "Run ORIGINAL with Emacsvox messages silenced."
  (ems-with-messages-silenced
    (apply original arguments)))

(advice-add
 'auth-source-do-debug :around
 #'emacsvox--advice-auth-source-do-debug-around
 '((name . emacsvox)))

;;; xoauth:

(defun emacsvox--advice-auth-source-xoauth2--file-creds-around
    (original &rest arguments)
  "Run ORIGINAL once with Emacsvox messages silenced."
  (let ((emacsvox-speak-messages nil))
    (apply original arguments)))

(defun emacsvox-gnus--setup-xoauth2-advice ()
  "Install Emacsvox advice for the optional XOAuth2 package."
  (advice-add
   'auth-source-xoauth2--file-creds :around
   #'emacsvox--advice-auth-source-xoauth2--file-creds-around
   '((name . emacsvox))))

(with-eval-after-load 'auth-source-xoauth2
  (emacsvox-gnus--setup-xoauth2-advice))

(provide 'emacsvox-gnus)
;;;   end of file 

;; byte-compile-warnings: (deprecated )
