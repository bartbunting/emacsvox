;;; emacsvox-amark.el --- BookMarks For Audio -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1996 by T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: emacsvox, audio interface to emacs MP3
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

;; Structure emacsvox-amark holds a bookmark into an mp3 file
;; path:  filename containing  marked
;; name: Bookmark tag
;; Position: time offset from start

;;  This library will be used from emacsvox-m-player to set and jump
;; to bookmarks. Amarks are stored in a .amarks.am file in the working
;; directory.  It also provides a simple AMark Browser to use from a
;; directory containing mp3 files where Amarks have been created --
;; see @command{emacsvox-amarks-browse}.
;;  @command{emacsvox-amarks-bookshelf} brings up a @strong{AmarksBookshelf}
;; that can be used to  browse available Amark files.

;;; Code:

;;; Forward variable declarations:

(defvar emacsvox-amark-file)
(defvar emacsvox-amark-list)
(defvar emacsvox-m-player-options)
(defvar emacsvox-m-player-process)
(defvar locate-command)
(defvar locate-make-command-line)

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'dired)

;;;  Structure:

(cl-defstruct
    emacsvox-amark
  "AMark: Holds name,  a file, and a time-position."
  path                                   ; filename
  name                                   ; Bookmark name
  position                               ; Offset in ms from start
  )

;;;  AMark List:

(defvar-local emacsvox-amark-list nil
  "List of buffer-local AMarks. ")

;;;  AMark Functions:

(defsubst emacsvox-amark-names ()
  "Return list of  amark names."
  
  (cl-loop for a in emacsvox-amark-list collect (emacsvox-amark-name a)))

(defun emacsvox-amark-find (name)
  "Return matching AMark if found in buffer-local AMark list."
  (interactive (list (completing-read "Name: " (emacsvox-amark-names))))
  
  (cl-find name emacsvox-amark-list
           :test #'string= :key #'emacsvox-amark-name))

(defun emacsvox-amark-add (path name position)
  "Add an AMark to the buffer local list of AMarks. AMarks are
bookmarks in audio content. If there is an existing amark of the
given name, it is updated with path and position."
  (interactive "fPath\nsName\nnPosition")
  
  (let ((amark (emacsvox-amark-find name)))
    (when (and path (not (zerop (length path))))
      (cond
       (amark                             ; exists, reposition
        (setf (emacsvox-amark-path amark) path
              (emacsvox-amark-position amark) position))
       (t
        (push
         (make-emacsvox-amark :path path :name name :position position)
         emacsvox-amark-list))))))

(defvar emacsvox-amark-file ".amarks.am"
  "Name of file used to save AMarks.")

(defun emacsvox-amark-save ()
  "Save buffer-local AMarks in  currently playing directory."
  (interactive)
  
  (let ((l  emacsvox-amark-list)
        (print-length nil)
        (buff (find-file-noselect (expand-file-name emacsvox-amark-file))))
    (with-current-buffer buff
      (set (make-local-variable 'backup-inhibited) t)
      (setq buffer-undo-list  t)
      (erase-buffer)
      (prin1 l (current-buffer))
      (save-buffer)
      (message "Saved AMarks in %s" (buffer-file-name))
      (kill-buffer buff)
      (emacsvox-icon 'save-object))))

(defun emacsvox-amark-load ()
  "Load AMarks file from  current  media directory."
  (let* ((buff nil)
         (find-file-hook nil)
         (def default-directory)
         (dir
          (when (process-live-p emacsvox-m-player-process)
            (with-current-buffer
                (process-buffer emacsvox-m-player-process) def)))
         (file
          (cond 
           ((file-exists-p (expand-file-name emacsvox-amark-file def))
            (expand-file-name emacsvox-amark-file def))
           (t  (expand-file-name emacsvox-amark-file dir))))
         (l nil ))
    (when (file-exists-p file)
      (setq buff (find-file-noselect file))
      (with-current-buffer buff
        (goto-char (point-min))
        (setq l (read buff))
        (kill-buffer buff)))
    ;;  sort and clean up stale marks 
    (setq
     emacsvox-amark-list
     (sort
      (cl-remove-if-not
       #'(lambda (f)
           (file-exists-p
            (expand-file-name f (file-name-directory file))))
       l
       :key #'emacsvox-amark-path)
      #'(lambda (a b) ;; predicate for sort
          (string-lessp
           (emacsvox-amark-name a) (emacsvox-amark-name b )))))))

(defun emacsvox-amark-file-load ()
  "Open .amark.el on current line in AMark Browser"
  (interactive)
  (cd (file-name-directory (dired-get-filename)))
  (funcall-interactively #'emacsvox-amark-browse))

(defun emacsvox-amark-delete (amark)
  "Delete Amark and save."
  
  (setq emacsvox-amark-list (remove amark emacsvox-amark-list))
  (emacsvox-icon 'delete-object)
  (emacsvox-amark-save)
  (emacsvox-amark-browse)
  (message "Updated amarks"))

(declare-function emacsvox-m-player-seek-absolute "emacsvox-m-player" (pos))

(defun emacsvox-amark-play (amark)
  "Play amark using m-player."
  
  (let ((f (expand-file-name (emacsvox-amark-path  amark) default-directory))
        (emacsvox-m-player-options
         (append
          emacsvox-m-player-options
          `("-ss" ,(emacsvox-amark-position amark)))))
    (cl-assert (file-exists-p f) t "File does not exist:" )
    (emacsvox-m-player f)
    (message "Playing %s from %s"
             (file-name-base f) (emacsvox-amark-position amark))))

;;; Amark Mode:

(define-derived-mode emacsvox-amark-mode special-mode
  "AMark Browser"
  "A light-weight mode for the `*Emacsvox Amark Browser*'.
 1. Provides buttons for opening and removing AMarks.
 2. Enables org integration via command
 `org-store-link' bound to \\[org-store-link].
 3. Stored links can be inserted into org files in the same directory
via command `org-insert-link' bound to \\[org-insert-link]."
  (setq header-line-format "AMark Browser")
  t)

(cl-loop
 for b   in
 '(
   ("C-c i" org-insert-link)
   ("C-c l" org-store-link))
 do
 (emacsvox-keymap-update emacsvox-amark-mode-map b))

;;; Browse Amarks:

(defun emacsvox-amark-list-play ()
  "Play amark list as a playlist.
Maps command \\[emacsvox-m-player] across elements of the amarks
  list.  Pressing `y' as the current item is playing skips to the
  next item; this `y/n' prompt is produced by
  \\[emacsvox-m-player] as is usual when that command is called
  while media is already playing. Here, attempting to play the next
  item while the current item is playing produces the prompt."
  (interactive)
  
  (when (and emacsvox-amark-list (listp emacsvox-amark-list))
    (mapc #'emacsvox-amark-play emacsvox-amark-list)))

(defun emacsvox-amark-browse ()
  "Browse   amarks  in current directory using `emacsvox-amark-mode'."
  (interactive)
  
  (let ((amarks (or (emacsvox-amark-load) (error "No Amarks here")))
        (buff (get-buffer-create "*Amarks Browser"))
        (inhibit-read-only t))
    (with-current-buffer buff
      (emacsvox-amark-mode)
      (setq emacsvox-amark-list amarks)
      (local-set-key "p" 'backward-button)
      (local-set-key "." 'emacsvox-amark-list-play)
      (local-set-key "n" 'forward-button)
      (erase-buffer)
      (setq buffer-undo-list  t)
      (cl-loop
       for m in amarks do
       (insert-text-button
        (format "%s\t" (emacsvox-amark-name m))
        'mark m
        'action #'(lambda (b) (emacsvox-amark-play (button-get b 'mark))))
       (insert (format "%s\t" (emacsvox-amark-path m)))
       (insert-text-button
        "Remove\n" 'mark m
        'action #'(lambda (b) (emacsvox-amark-delete (button-get b 'mark)))))
      (emacsvox-speak-load-directory-settings)
      (goto-char (point-min)))
    (funcall-interactively #'switch-to-buffer buff)))

(defun emacsvox-amark-bookshelf(&optional pattern)
  "Open a locate buffer with all .amarks.am files.
Optional interactive prefix arg prompts for a pattern that is
used to filter the amarks files to show.  Use
\\[emacsvox-dired-open-this-file] to open the AMark Browser on
current file."
  (interactive "P")
  (when pattern (setq pattern (read-from-minibuffer "Filter Pattern:")))
  (let ((case-fold-search t)
        (locate-make-command-line
         #'(lambda (s)
             (list
              locate-command "-i" "-e" "--regexp" s))))
    (cond
     (pattern 
      (locate-with-filter
       (mapconcat
        #'identity
        (split-string pattern)
        "[ '/\"_.,-]")
       emacsvox-amark-file))
     (t (funcall-interactively #'locate emacsvox-amark-file))))
  (rename-buffer "AMark Bookshelf" 'unique)
  (emacsvox-speak-line)
  (emacsvox-icon 'open-object))

(provide  'emacsvox-amark)

;;; emacsvox-amark.el ends here
