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
;; Location https://github.com/tvraman/emacsvox
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

;;;  requires

(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)
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
  (cl-declare (special gnus-summary-mode-map
                       gnus-group-mmode-map
                       gnus-article-mode-map))
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

(defun emacsvox-gnus-summary-speak-subject ()
  (dtk-speak (gnus-summary-article-subject)))

(defun emacsvox-gnus-speak-article-body ()
  (cl-declare (special emacsvox-gnus-large-article
                       voice-lock-mode dtk-punctuation-mode
                       gnus-article-buffer))
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

(defun ems--gnus-around (orig-fun &rest args)
  "Silence messages, produce auditory icon."
  (dtk-speak "Starting gnus")
  (ems-with-messages-silenced (apply orig-fun args))
  (emacsvox-icon 'news) (message "Gnus is ready "))

(advice-add 'gnus :around #'ems--gnus-around)

(cl-loop
 for f in
 '(gnus-group-suspend gnus-group-quit
                      gnus-group-exit gnus-server-exit)
 do
 (eval
  `(defadvice ,f(after emacsvox pre act com)
     "Provide auditory contextual feedback."
     (when (ems-interactive-p)
       (emacsvox-icon 'close-object)
       (dtk-stop)
       (emacsvox-speak-mode-line)))))

;;;   starting up:

(defun ems--gnus-group-post-news-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'gnus-group-post-news :after
            #'ems--gnus-group-post-news-after)

(defun ems--gnus-group-get-new-news-around (orig-fun &rest args)
  "Temporarily silence on message" (dtk-speak "Getting new  gnus")
  (ems-with-messages-silenced (apply orig-fun args))
  (message "Gnus is ready ") (emacsvox-icon 'news))

(advice-add 'gnus-group-get-new-news :around
            #'ems--gnus-group-get-new-news-around)

(defun ems--nnheader-message-maybe-around (orig-fun &rest args)
  "Silence emacsvox"
  (ems-with-messages-silenced (apply orig-fun args)))

(advice-add 'nnheader-message-maybe :around
            #'ems--nnheader-message-maybe-around)

;;;   Newsgroup selection

(cl-loop
 for f in
 '(
   gnus-group-select-group gnus-group-first-unread-group
   gnus-group-read-group
   gnus-group-prev-group gnus-group-next-group
   gnus-group-prev-unread-group  gnus-group-next-unread-group
   gnus-group-get-new-news-this-group)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'select-object)
       (emacsvox-speak-line)))))

(defun ems--gnus-group-unsubscribe-current-group-after (&rest _)
  "Produce an auditory icon indicating\nthis group is being deselected."
  (when (ems-interactive-p)
    (emacsvox-icon 'deselect-object) (emacsvox-speak-line)))

(advice-add 'gnus-group-unsubscribe-current-group :after
            #'ems--gnus-group-unsubscribe-current-group-after)

(defun ems--gnus-group-catchup-current-after (&rest _)
  "speak.\n Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-line)))

(advice-add 'gnus-group-catchup-current :after
            #'ems--gnus-group-catchup-current-after)

(defun ems--gnus-group-yank-group-after (&rest _)
  "speak.\n Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'yank-object) (emacsvox-speak-line)))

(advice-add 'gnus-group-yank-group :after
            #'ems--gnus-group-yank-group-after)

(defun ems--gnus-group-list-groups-after (&rest _)
  "speak.\n Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (dtk-speak "Listing groups... done")))

(advice-add 'gnus-group-list-groups :after
            #'ems--gnus-group-list-groups-after)

(defun ems--gnus-topic-mode-after (&rest _)
  "speak.\n Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (dtk-speak "toggled topic mode")))

(advice-add 'gnus-topic-mode :after #'ems--gnus-topic-mode-after)

(defun ems--gnus-group-list-all-groups-after (&rest _)
  "speak.\n Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (dtk-speak "Listing all groups... done")))

(advice-add 'gnus-group-list-all-groups :after
            #'ems--gnus-group-list-all-groups-after)

(defun ems--gnus-group-list-all-matching-after (&rest _)
  "speak.\n Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (dtk-speak "Listing all matching groups... done")))

(advice-add 'gnus-group-list-all-matching :after
            #'ems--gnus-group-list-all-matching-after)

(defun ems--gnus-group-list-killed-after (&rest _)
  "speak.\n Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (dtk-speak "Listing killed groups... done")))

(advice-add 'gnus-group-list-killed :after
            #'ems--gnus-group-list-killed-after)

(defun ems--gnus-group-list-matching-after (&rest _)
  "speak.\n Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (emacsvox-pip
     "listing matching groups with unread articles... done")))

(advice-add 'gnus-group-list-matching :after
            #'ems--gnus-group-list-matching-after)

(defun ems--gnus-group-list-zombies-after (&rest _)
  "speak.\n Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (dtk-speak "Listing zombie groups... done")))

(advice-add 'gnus-group-list-zombies :after
            #'ems--gnus-group-list-zombies-after)

(defun ems--gnus-group-customize-before (&rest _)
  "speak.\n Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object)
    (message "Customizing group %s" (gnus-group-group-name))))

(advice-add 'gnus-group-customize :before
            #'ems--gnus-group-customize-before)

;;;   summary mode 
(cl-loop
 for f in
 '(
   gnus-summary-clear-mark-backward gnus-summary-clear-mark-forward
   gnus-summary-mark-as-dormant gnus-summary-mark-as-expirable
   gnus-summary-mark-as-processable
   gnus-summary-tick-article-backward gnus-summary-tick-article-forward
   ) do
 (eval
  `(defadvice   ,f (around  emacsvox pre act comp)
     "Speak the article  line.
 Produce an auditory icon if possible."
     (let ((saved-point (point)))
       ad-do-it
       (when (ems-interactive-p)
         (if (= saved-point (point))
             (emacsvox-pip "No more articles")
           (progn 
             (emacsvox-icon 'mark-object)
             (emacsvox-gnus-summary-speak-subject))))
       ad-return-value))))

(defun ems--gnus-summary-unmark-as-processable-after (&rest _)
  "Speak the line.\n Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'deselect-object)
    (emacsvox-gnus-summary-speak-subject)))

(advice-add 'gnus-summary-unmark-as-processable :after
            #'ems--gnus-summary-unmark-as-processable-after)

(defun ems--gnus-summary-delete-article-after (&rest _)
  "Speak the line.\n Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object)
    (emacsvox-gnus-summary-speak-subject)))

(advice-add 'gnus-summary-delete-article :after
            #'ems--gnus-summary-delete-article-after)

(cl-loop
 for f in
 '(
   gnus-summary-catchup-to-here gnus-summary-catchup-from-here
   ) do
 (eval
  `(defadvice  ,f (after emacsvox pre act comp)
     "Speak the line.
 Produce an auditory icon if possible."
     (when (ems-interactive-p)
       (emacsvox-icon  'mark-object)
       (emacsvox-gnus-summary-speak-subject)))))

(defun ems--gnus-summary-select-article-buffer-after (&rest _)
  "Speak the modeline.\nIndicate change of selection with\n  an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-mode-line)))

(advice-add 'gnus-summary-select-article-buffer :after
            #'ems--gnus-summary-select-article-buffer-after)

(defun ems--gnus-summary-prev-article-after (&rest _)
  "Speak the article. "
  (when (ems-interactive-p) (emacsvox-gnus-speak-article-body)))

(advice-add 'gnus-summary-prev-article :after
            #'ems--gnus-summary-prev-article-after)

(defun ems--gnus-summary-next-article-after (&rest _)
  "Speak the article. "
  (when (ems-interactive-p) (emacsvox-gnus-speak-article-body)))

(advice-add 'gnus-summary-next-article :after
            #'ems--gnus-summary-next-article-after)

(defun ems--gnus-summary-exit-no-update-around (orig-fun &rest args)
  "Speak the modeline.\nIndicate change of selection with\n  an auditory icon if possible."
  (let ((result (apply orig-fun args)))
    (let ((cur-group gnus-newsgroup-name))
      (apply orig-fun args)
      (when (ems-interactive-p)
        (emacsvox-icon 'close-object) (dtk-stop)
        (if (eq cur-group (gnus-group-group-name))
            (emacsvox-pip "No more unread newsgroups")
          (progn (emacsvox-speak-line))))
      result)
    result))

(advice-add 'gnus-summary-exit-no-update :around
            #'ems--gnus-summary-exit-no-update-around)

(defun ems--gnus-summary-exit-around (orig-fun &rest args)
  "Speak the modeline.\nIndicate change of selection with\n  an auditory icon if possible."
  (let ((result (apply orig-fun args)))
    (let ((cur-group gnus-newsgroup-name))
      (apply orig-fun args)
      (when (ems-interactive-p)
        (emacsvox-icon 'close-object) (dtk-stop)
        (if (eq cur-group (gnus-group-group-name))
            (emacsvox-pip "No more unread newsgroups")
          (progn (emacsvox-speak-line))))
      result)
    result))

(advice-add 'gnus-summary-exit :around #'ems--gnus-summary-exit-around)

(defun ems--gnus-summary-prev-subject-around (orig-fun &rest args)
  "Speak the article  line.\n Produce an auditory icon if possible."
  (let ((result (apply orig-fun args)))
    (let ((saved-point (point)))
      (apply orig-fun args)
      (when (ems-interactive-p)
        (if (= saved-point (point))
            (emacsvox-pip "No more articles ")
          (progn
            (emacsvox-icon 'select-object)
            (dtk-speak (gnus-summary-article-subject)))))
      result)
    result))

(advice-add 'gnus-summary-prev-subject :around
            #'ems--gnus-summary-prev-subject-around)

(defun ems--gnus-summary-next-subject-around (orig-fun &rest args)
  "Speak the article  line. \nProduce an auditory icon if possible."
  (let ((result (apply orig-fun args)))
    (let ((saved-point (point)))
      (apply orig-fun args)
      (when (ems-interactive-p)
        (if (= saved-point (point))
            (emacsvox-pip "No more articles ")
          (progn
            (emacsvox-icon 'select-object)
            (dtk-speak (gnus-summary-article-subject)))))
      result)
    result))

(advice-add 'gnus-summary-next-subject :around
            #'ems--gnus-summary-next-subject-around)

(defun ems--gnus-summary-prev-unread-subject-around
    (orig-fun &rest args)
  "Speak the article  line.\n Produce an auditory icon if possible."
  (let ((result (apply orig-fun args)))
    (let ((saved-point (point)))
      (apply orig-fun args)
      (when (ems-interactive-p)
        (if (= saved-point (point))
            (emacsvox-pip "No more unread articles ")
          (progn
            (emacsvox-icon 'select-object)
            (dtk-speak (gnus-summary-article-subject)))))
      result)
    result))

(advice-add 'gnus-summary-prev-unread-subject :around
            #'ems--gnus-summary-prev-unread-subject-around)

(defun ems--gnus-summary-next-unread-subject-around
    (orig-fun &rest args)
  "Speak the article line.\nProduce an auditory icon if possible."
  (let ((result (apply orig-fun args)))
    (let ((saved-point (point)))
      (apply orig-fun args)
      (when (ems-interactive-p)
        (if (= saved-point (point))
            (emacsvox-pip "No more articles ")
          (progn
            (emacsvox-icon 'select-object)
            (dtk-speak (gnus-summary-article-subject)))))
      result)
    result))

(advice-add 'gnus-summary-next-unread-subject :around
            #'ems--gnus-summary-next-unread-subject-around)

(defun ems--gnus-summary-goto-subject-around (orig-fun &rest args)
  "Speak the article  line.\n Produce an auditory icon if possible."
  (let ((result (apply orig-fun args)))
    (let ((saved-point (point)))
      (apply orig-fun args)
      (when (ems-interactive-p)
        (if (= saved-point (point))
            (emacsvox-pip "No more articles ")
          (progn
            (emacsvox-icon 'select-object)
            (dtk-speak (gnus-summary-article-subject)))))
      result)
    result))

(advice-add 'gnus-summary-goto-subject :around
            #'ems--gnus-summary-goto-subject-around)

(defun ems--gnus-summary-catchup-and-exit-after (&rest _)
  "Speak the newsgroup line.\n Produce an auditory icon indicating \nthe previous group was closed."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-line)))

(advice-add 'gnus-summary-catchup-and-exit :after
            #'ems--gnus-summary-catchup-and-exit-after)

(defun ems--gnus-summary-mark-as-unread-forward-after (&rest _)
  "Speak the line.\n Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object)
    (emacsvox-gnus-summary-speak-subject)))

(advice-add 'gnus-summary-mark-as-unread-forward :after
            #'ems--gnus-summary-mark-as-unread-forward-after)

(defun ems--gnus-summary-mark-as-read-forward-after (&rest _)
  "Speak the line.\n Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object)
    (emacsvox-gnus-summary-speak-subject)))

(advice-add 'gnus-summary-mark-as-read-forward :after
            #'ems--gnus-summary-mark-as-read-forward-after)

(defun ems--gnus-summary-mark-as-unread-backward-after (&rest _)
  "Speak the line.\n Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object)
    (emacsvox-gnus-summary-speak-subject)))

(advice-add 'gnus-summary-mark-as-unread-backward :after
            #'ems--gnus-summary-mark-as-unread-backward-after)

(defun ems--gnus-summary-mark-as-read-backward-after (&rest _)
  "Speak the line.\n Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object)
    (emacsvox-gnus-summary-speak-subject)))

(advice-add 'gnus-summary-mark-as-read-backward :after
            #'ems--gnus-summary-mark-as-read-backward-after)

(defun ems--gnus-summary-kill-same-subject-and-select-after (&rest _)
  "Speak the subject and speak the first screenful.\nProduce an auditory icon\nindicating the article is being opened."
  
  (when (ems-interactive-p)
    (emacsvox-gnus-summary-speak-subject) (sit-for 2)
    (emacsvox-icon 'open-object)
    (with-current-buffer gnus-article-buffer
      (let
          ((start (point))
           (window (get-buffer-window (current-buffer))))
        (with-selected-window window
          (save-excursion
            (move-to-window-line -1) (end-of-line)
            (emacsvox-speak-region start (point))))))))

(advice-add 'gnus-summary-kill-same-subject-and-select :after
            #'ems--gnus-summary-kill-same-subject-and-select-after)

(defun ems--gnus-summary-kill-same-subject-after (&rest _)
  "Speak the line.\n Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (emacsvox-gnus-summary-speak-subject)))

(advice-add 'gnus-summary-kill-same-subject :after
            #'ems--gnus-summary-kill-same-subject-after)

(defun ems--gnus-summary-next-thread-after (&rest _)
  "Speak the line.\n Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (emacsvox-gnus-summary-speak-subject)))

(advice-add 'gnus-summary-next-thread :after
            #'ems--gnus-summary-next-thread-after)

(defun ems--gnus-summary-prev-thread-after (&rest _)
  "Speak the line.\n Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (emacsvox-gnus-summary-speak-subject)))

(advice-add 'gnus-summary-prev-thread :after
            #'ems--gnus-summary-prev-thread-after)

(defun ems--gnus-summary-up-thread-after (&rest _)
  "Speak the line.\n Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (emacsvox-gnus-summary-speak-subject)))

(advice-add 'gnus-summary-up-thread :after
            #'ems--gnus-summary-up-thread-after)

(defun ems--gnus-summary-down-thread-after (&rest _)
  "Speak the line. \nProduce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (emacsvox-gnus-summary-speak-subject)))

(advice-add 'gnus-summary-down-thread :after
            #'ems--gnus-summary-down-thread-after)

(defun ems--gnus-summary-kill-thread-after (&rest _)
  "Speak the line.\n Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (emacsvox-gnus-summary-speak-subject)))

(advice-add 'gnus-summary-kill-thread :after
            #'ems--gnus-summary-kill-thread-after)

(defun ems--gnus-summary-hide-all-threads-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-line)))

(advice-add 'gnus-summary-hide-all-threads :after
            #'ems--gnus-summary-hide-all-threads-after)

;;;   Article reading

(defun emacsvox-gnus-summary-catchup-quietly-and-exit ()
  "Catch up on all articles in current group."
  (interactive)
  (gnus-summary-catchup-and-exit t t)
  (emacsvox-icon 'close-object)
  (emacsvox-speak-line))

(defun ems--gnus-summary-read-group-around (orig-fun &rest args)
  "Deactivate our shr-external-rendering-functions"
  (let ((shr-external-rendering-functions nil)) (apply orig-fun args)))

(advice-add 'gnus-summary-read-group :around
            #'ems--gnus-summary-read-group-around)

(defun ems--gnus-summary-show-article-around (orig-fun &rest args)
  "Deactivate our shr-external-rendering-functions"
  (let ((shr-external-rendering-functions nil)) (apply orig-fun args)))

(advice-add 'gnus-summary-show-article :around
            #'ems--gnus-summary-show-article-around)

(defun ems--gnus-summary-show-article-after (&rest _)
  "Start speaking the article. "
  (when (ems-interactive-p)
    (with-current-buffer gnus-article-buffer
      (visual-line-mode) (emacsvox-icon 'open-object)
      (condition-case nil (emacsvox-hide-all-blocks-in-buffer)
        (error nil))
      (emacsvox-gnus-speak-article-body))))

(advice-add 'gnus-summary-show-article :after
            #'ems--gnus-summary-show-article-after)

(defun ems--gnus-summary-next-page-after (&rest _)
  "Speak the next pageful " 
  (dtk-stop 'all) (emacsvox-icon 'scroll)
  (with-current-buffer gnus-article-buffer
    (let
        ((start (point)) (window (get-buffer-window (current-buffer))))
      (with-selected-window window
        (save-excursion
          (move-to-window-line -1) (end-of-line)
          (emacsvox-speak-region start (point)))))))

(advice-add 'gnus-summary-next-page :after
            #'ems--gnus-summary-next-page-after)

(defun ems--gnus-summary-prev-page-after (&rest _)
  "Speak the previous  pageful "
  (dtk-stop 'all)
  (emacsvox-icon 'scroll)
  (save-current-buffer
    (set-buffer gnus-article-buffer)
    (let
        ((start (point)) (window (get-buffer-window (current-buffer))))
      (with-selected-window window
        (save-excursion
          (move-to-window-line -1) (end-of-line)
          (emacsvox-speak-region start (point)))))))

(advice-add 'gnus-summary-prev-page :after
            #'ems--gnus-summary-prev-page-after)

(defun ems--gnus-summary-beginning-of-article-after (&rest _)
  "Speak the first line. " 
  (save-current-buffer
    (set-buffer gnus-article-buffer) (emacsvox-speak-line)))

(advice-add 'gnus-summary-beginning-of-article :after
            #'ems--gnus-summary-beginning-of-article-after)

(defun ems--gnus-summary-end-of-article-after (&rest _)
  "Speak the first line. " 
  (save-current-buffer
    (set-buffer gnus-article-buffer) (emacsvox-speak-line)))

(advice-add 'gnus-summary-end-of-article :after
            #'ems--gnus-summary-end-of-article-after)

(defun ems--gnus-summary-next-unread-article-after (&rest _)
  "Speak the article. "
  (when (ems-interactive-p) (emacsvox-gnus-speak-article-body)))

(advice-add 'gnus-summary-next-unread-article :after
            #'ems--gnus-summary-next-unread-article-after)

(defun ems--gnus-summary-prev-unread-article-after (&rest _)
  "Speak the article. "
  (when (ems-interactive-p) (emacsvox-gnus-speak-article-body)))

(advice-add 'gnus-summary-prev-unread-article :after
            #'ems--gnus-summary-prev-unread-article-after)

(defun ems--gnus-summary-next-article-after (&rest _)
  "Speak the article. "
  (when (ems-interactive-p) (emacsvox-gnus-speak-article-body)))

(advice-add 'gnus-summary-next-article :after
            #'ems--gnus-summary-next-article-after)

(defun ems--gnus-summary-prev-same-subject-after (&rest _)
  "Speak the article. "
  (when (ems-interactive-p) (emacsvox-gnus-speak-article-body)))

(advice-add 'gnus-summary-prev-same-subject :after
            #'ems--gnus-summary-prev-same-subject-after)

(defun ems--gnus-summary-next-same-subject-after (&rest _)
  "Speak the article. "
  (when (ems-interactive-p) (emacsvox-gnus-speak-article-body)))

(advice-add 'gnus-summary-next-same-subject :after
            #'ems--gnus-summary-next-same-subject-after)

(defun ems--gnus-summary-first-unread-article-after (&rest _)
  "Speak the article. "
  (when (ems-interactive-p) (emacsvox-gnus-speak-article-body)))

(advice-add 'gnus-summary-first-unread-article :after
            #'ems--gnus-summary-first-unread-article-after)

(defun ems--gnus-summary-goto-last-article-after (&rest _)
  "Speak the article. "
  (when (ems-interactive-p) (emacsvox-gnus-speak-article-body)))

(advice-add 'gnus-summary-goto-last-article :after
            #'ems--gnus-summary-goto-last-article-after)

(defun ems--gnus-article-show-summary-after (&rest _)
  "Speak the modeline.\nIndicate change of selection with\n  an auditory icon if possible."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-mode-line)))

(advice-add 'gnus-article-show-summary :after
            #'ems--gnus-article-show-summary-after)

(defun ems--gnus-article-next-page-after (&rest _)
  "Speak the current window full of news"
  (when (ems-interactive-p) (emacsvox-speak-current-window)))

(advice-add 'gnus-article-next-page :after
            #'ems--gnus-article-next-page-after)

(defun ems--gnus-article-prev-page-after (&rest _)
  "Speak the current window full"
  (when (ems-interactive-p) (emacsvox-speak-current-window)))

(advice-add 'gnus-article-prev-page :after
            #'ems--gnus-article-prev-page-after)

(defun ems--gnus-article-next-button-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (let ((end (next-single-property-change (point) 'gnus-callback)))
      (emacsvox-icon 'large-movement)
      (message (buffer-substring (point) end)))))

(advice-add 'gnus-article-next-button :after
            #'ems--gnus-article-next-button-after)

(defun ems--gnus-article-press-button-before (&rest _)
  "speak" (when (ems-interactive-p) (emacsvox-icon 'button)))

(advice-add 'gnus-article-press-button :before
            #'ems--gnus-article-press-button-before)

(defun ems--gnus-article-goto-prev-page-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'scroll) (sit-for 1)
    (emacsvox-speak-current-window)))

(advice-add 'gnus-article-goto-prev-page :after
            #'ems--gnus-article-goto-prev-page-after)

(defun ems--gnus-article-goto-next-page-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'scroll) (sit-for 1)
    (emacsvox-speak-current-window)))

(advice-add 'gnus-article-goto-next-page :after
            #'ems--gnus-article-goto-next-page-after)

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
  (dtk-speak "Downcased article body"))

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
      (dtk-set-punctuations emacsvox-gnus-punctuation-mode)
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
 for f in 
 '(gnus-server-edit-buffer gnus-group-enter-server-mode gnus-browse-exit)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-speak-mode-line)))))

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

(defun ems--auth-source-do-debug-around (orig-fun &rest args)
  "silence" (ems-with-messages-silenced (apply orig-fun args)))

(advice-add 'auth-source-do-debug :around
            #'ems--auth-source-do-debug-around)

;;; xoauth:

(defun ems--auth-source-xoauth2--file-creds-around
    (orig-fun &rest args)
  "Silence messages"
  (let ((result (apply orig-fun args)))
    (let ((emacsvox-speak-messages nil))
      (apply orig-fun args) result)
    result))

(advice-add 'auth-source-xoauth2--file-creds :around
            #'ems--auth-source-xoauth2--file-creds-around)

(provide 'emacsvox-gnus)
;;;   end of file 

;; byte-compile-warnings: (deprecated )

