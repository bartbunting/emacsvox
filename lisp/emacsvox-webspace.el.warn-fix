;;; emacsvox-webspace.el --- Webspaces -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description: WebSpace provides smart updates from the Web.
;; Keywords: Emacsvox, Audio Desktop webspace
;;;  LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;; $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacsvox
;; 

;;;  Copyright:
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
;; MERCHANTABILITY or FITNWEBSPACE FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING. If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;  introduction

;;; Commentary:
;; WEBSPACE == Smart Web Gadgets For The Emacsvox Desktop
;;; Code:

;;  Required modules: 

(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)
(require 'emacsvox-we)
(require 'ring)
(require 'derived)
(require 'gweb)
(require 'emacsvox-feeds)

;;;  WebSpace Mode:

;; Define a derived-mode called WebSpace that is generally useful for
;; hypetext display.

(define-derived-mode emacsvox-webspace-mode special-mode
  "Webspace Interaction"
  "Major mode for Webspace interaction.\n\n
\\{emacsvox-webspace-mode-map}")

(cl-declaim (special emacsvox-webspace-mode-map))
(set-keymap-parent emacsvox-webspace-mode-map button-buffer-map)
(cl-loop for k in
         '(
           ("q" bury-buffer)
           ("." emacsvox-webspace-filter)
           ("'" emacsvox-speak-rest-of-buffer)
           ("<" beginning-of-buffer)
           (">" end-of-buffer)
           ("/" search-forward)
           ("?" search-backward)
           ("y" emacsvox-webspace-yank-link)
           ("n" forward-button)
           ("p" backward-button)
           ("f" forward-button)
           ("b" backward-button))
         do
         (emacsvox-keymap-update emacsvox-webspace-mode-map k))

(defun emacsvox-webspace-act-on-link (action &rest args)
  "Apply action to link under point."
  (let ((link (get-text-property (point) 'link)))
    (if link
        (apply action link args)
      (message "No link under point."))))

(defun emacsvox-webspace-yank-link ()
  "Yank link under point into kill ring."
  (interactive)
  (let ((button (button-at (point))))
    (cond
     (button (emacsvox-icon 'yank-object)
             (message "%s"
                      (kill-new
                       (or (cl-second (button-get button 'feed))
                           (button-get button 'link)
                           (button-get button 'url)))))
     (t (error "No link under point")))))

(defun emacsvox-webspace-open ()
  "Open headline at point by following its link property."
  (interactive)
  (emacsvox-webspace-act-on-link 'browse-url))

(defun emacsvox-webspace-filter ()
  "Open headline at point and filter for content."
  (interactive)
  (let ((link (get-text-property (point) 'link)))
    (if link
        (emacsvox-we-xslt-filter
         emacsvox-we-recent-xpath-filter
         link 'speak)
      (message "No link under point."))))

;;;  WebSpace Display:

(defun emacsvox-webspace-display (infolet)
  "Displays specified infolet.
Infolets use the same structure as mode-line-format and header-line-format.
Generates auditory and visual display."
  (cl-declare (special header-line-format))
  (setq header-line-format infolet)
  (dtk-speak (format-mode-line header-line-format))
  (emacsvox-icon 'progress))

;;;###autoload
(define-prefix-command 'emacsvox-webspace 'emacsvox-webspace-keymap)

(cl-declaim (special emacsvox-webspace-keymap))

(cl-loop for k in
         '(
           ("h" emacsvox-webspace-headlines)
           (" " emacsvox-webspace-headlines-browse)
           )
         do
         (define-key emacsvox-webspace-keymap (cl-first k) (cl-second k)))

;;;  Headlines:

(cl-defstruct emacsvox-webspace-fs
  feeds
  titles ; (title url)
  timer slow-timer
  index)

(defvar emacsvox-webspace-headlines nil
  "Feedstore structure to use a continuously updating ticker.")

(defvar emacsvox-webspace-headlines-period '(0 1800 0)
  "How often we fetch from a feed.")
(defun emacsvox-webspace-feed-titles (feed-url)
  "Return a list  `((title url)...) given an RSS/Atom  feed  URL."
  (cl-declare (special emacsvox-xslt-directory emacsvox-xslt
                       emacsvox-curl g-curl-options))
  (with-temp-buffer
    (shell-command
     (format "%s %s %s | %s %s - "
             emacsvox-curl g-curl-options feed-url
             emacsvox-xslt
             (expand-file-name "feed-titles.xsl" emacsvox-xslt-directory))
     (current-buffer))
    (goto-char (point-min))
    ;; newline -> spc
    (while (re-search-forward "\n" nil t) (replace-match " "))
    (goto-char (point-min))
    (read (current-buffer))))

(defun emacsvox-webspace-headlines-fetch (feed)
  "Add headlines from specified feed to our cache.
Newly found headlines are inserted into the ring within our feedstore."
  (cl-declare (special emacsvox-webspace-headlines
                       emacsvox-webspace-headlines-period))
  (let* ((last-update (get-text-property 0 'last-update feed))
         (titles (emacsvox-webspace-fs-titles emacsvox-webspace-headlines))
         (new-titles nil))
    (when                     ; check if we need to add from this feed
        (or (null last-update)          ;  at most every half hour
            (time-less-p
             emacsvox-webspace-headlines-period  (time-since last-update)))
      (put-text-property 0 1 'last-update (current-time) feed)
      (setq new-titles (emacsvox-webspace-feed-titles feed))
      (when (listp new-titles)
        (mapc
         #'(lambda (h)
             (unless (ring-member titles h)
               (ring-insert titles h)))
         new-titles)))))

(defun emacsvox-webspace-fs-next (fs)
  "Return next feed and increment index for fs."
  (let ((feed-url
         (aref
          (emacsvox-webspace-fs-feeds fs)
          (emacsvox-webspace-fs-index fs))))
    (setf (emacsvox-webspace-fs-index fs)
          (% (1+ (emacsvox-webspace-fs-index fs))
             (length (emacsvox-webspace-fs-feeds fs))))
    feed-url))

(defun emacsvox-webspace-headlines-populate ()
  "populate fs with headlines from all feeds."
  (cl-declare (special emacsvox-webspace-headlines))
  (dotimes (_i (length (emacsvox-webspace-fs-feeds
                        emacsvox-webspace-headlines)))
    (condition-case nil
        (emacsvox-webspace-headlines-fetch
         (emacsvox-webspace-fs-next emacsvox-webspace-headlines))
      (error nil))))

(defun emacsvox-webspace-headlines-refresh ()
  "Update headlines."
  (cl-declare (special emacsvox-webspace-headlines))
  (with-local-quit
    (emacsvox-webspace-headlines-fetch
     (emacsvox-webspace-fs-next emacsvox-webspace-headlines)))
  (emacsvox-icon 'progress)
  t)

(defun emacsvox-webspace-headlines-update ()
  "Setup news updates.
Updated headlines found in emacsvox-webspace-headlines."
  (interactive)
  (cl-declare (special emacsvox-webspace-headlines))
  (let ((timer nil)
        (slow-timer nil))
    (setq timer
          (run-with-idle-timer
           60 t 'emacsvox-webspace-headlines-refresh))
    (setq slow-timer
          (run-with-idle-timer
           3600
           t 'emacsvox-webspace-headlines-populate))
    (setf (emacsvox-webspace-fs-timer emacsvox-webspace-headlines) timer)
    (setf
     (emacsvox-webspace-fs-slow-timer emacsvox-webspace-headlines)
     slow-timer)))

(defun emacsvox-webspace-next-headline ()
  "Return next headline to display."
  (cl-declare (special emacsvox-webspace-headlines))
  (let ((titles (emacsvox-webspace-fs-titles emacsvox-webspace-headlines)))
    (cond
     ((ring-empty-p titles)
      (emacsvox-webspace-headlines-refresh)
      "No News Is Good News")
     (t (let ((h (ring-remove titles 0)))
          (ring-insert-at-beginning titles h)
          (cl-first h))))))
(defcustom emacsvox-webspace-feeds
  nil
  "Feeds to use in Headline Ticker."
  :type '(repeat (string :tag "URL"))
  :group 'emacsvox-webspace)

;;;###autoload
(defun emacsvox-webspace-headlines ()
  "Startup Headlines ticker using RSS/Atom  feeds."
  (interactive)
  (cl-declare (special emacsvox-webspace-headlines
                       emacsvox-webspace-feeds))
  (cl-assert
   emacsvox-webspace-feeds
   t "First add some feeds to emacsvox-webspace-feeds.")
  (unless emacsvox-webspace-headlines
    (setq emacsvox-webspace-headlines
          (make-emacsvox-webspace-fs
           :feeds
           (apply #'vector emacsvox-webspace-feeds)
           :titles (make-ring (* 10 (length emacsvox-feeds)))
           :index 0)))
  (unless (emacsvox-webspace-fs-timer emacsvox-webspace-headlines)
    (call-interactively 'emacsvox-webspace-headlines-update))
  (emacsvox-webspace-display '((:eval (emacsvox-webspace-next-headline)))))

(defvar emacsvox-webspace-headlines-buffer "*Headlines*"
  "Name of buffer that displays headlines.")

(defun emacsvox-webspace-headlines-browse ()
  "Display buffer of browsable headlines."
  (interactive)
  (cl-declare (special emacsvox-webspace-headlines
                       emacsvox-webspace-headlines-buffer))
  (unless emacsvox-webspace-headlines
    (error "No cached headlines in this Emacs session."))
  (with-current-buffer
      (get-buffer-create emacsvox-webspace-headlines-buffer)
    (setq buffer-undo-list  t)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (goto-char (point-min))
      (insert "Press enter to open stories.\n\n")
      (put-text-property (point-min) (point) 'face font-lock-doc-face)
      (cl-loop
       for h in
       (delq nil
             (ring-elements
              (emacsvox-webspace-fs-titles emacsvox-webspace-headlines)))
       and position  from 1
       do
       (insert (format "\n%d\t" position))
       (emacsvox-webspace-headlines-insert-button h))
      (goto-char (point-min))
      (flush-lines "^ *$")
      (emacsvox-webspace-mode)))
  (switch-to-buffer emacsvox-webspace-headlines-buffer)
  (goto-char (point-min))
  (emacsvox-icon 'open-object)
  (emacsvox-speak-mode-line))

(define-button-type 'emacsvox-webspace-headline
  'follow-link t
  'link nil
  'help-echo "Open Headline"
  'action #'emacsvox-webspace-headline-action)

(defun emacsvox-webspace-headline-action (button)
  "Open story associated with this button."
  (browse-url (button-get button 'link)))

(defun emacsvox-webspace-headlines-insert-button (headline)
  "Insert a button for this headline at point."
  (insert-text-button
   (car headline)
   'type 'emacsvox-webspace-headline
   'link (cadr headline)))

;;;  Feed Reader:

;; In memory of Google Reader:

(defvar emacsvox-webspace-reader-buffer "Reader"
  "Name of Reader buffer.")

;; New Reader using emacsvox-feeds:

(define-button-type 'emacsvox-webspace-feed-link
  'follow-link t
  'feed nil
  'help-echo "Open Feed"
  'action #'emacsvox-webspace-feed-reader-action)

(defun emacsvox-webspace-feed-reader-insert-button (feed)
  "Insert a button for this feed at point."
  (insert-text-button
   (cl-first feed) ; label
   'type 'emacsvox-webspace-feed-link
   'feed feed))

(defun emacsvox-webspace-feed-reader-action (button)
  "Open feed associated with this button."
  (emacsvox-feeds-browse-feed (button-get button 'feed)))

;;;###autoload
(defun emacsvox-webspace-feed-reader (&optional refresh)
  "Display Feed Reader Feed list in a WebSpace buffer.
Optional interactive prefix arg forces a refresh."
  (interactive "P")
  (cl-declare (special emacsvox-webspace-reader-buffer))
  (when (or refresh
            (not (buffer-live-p (get-buffer
                                 emacsvox-webspace-reader-buffer))))
    (emacsvox-webspace-feed-reader-create))
  (switch-to-buffer emacsvox-webspace-reader-buffer)
  (goto-char (point-min))
  (emacsvox-speak-mode-line)
  (emacsvox-icon 'open-object))
(defun emacsvox-webspace-feed-reader-create ()
  "Prepare Reader buffer."
  (cl-declare (special emacsvox-feeds emacsvox-webspace-reader-buffer))
  (with-current-buffer (get-buffer-create emacsvox-webspace-reader-buffer)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (goto-char (point-min))
      (insert "Press enter to open feeds.\n\n")
      (put-text-property (point-min) (point) 'face font-lock-doc-face)
      (cl-loop
       for f in emacsvox-feeds
       and position  from 1 do
       (insert (format "%d\t" position))
       (emacsvox-webspace-feed-reader-insert-button f)
       (insert "\n"))
      (switch-to-buffer emacsvox-webspace-reader-buffer)
      (emacsvox-webspace-mode))))

(provide 'emacsvox-webspace)
;;;  end of file

