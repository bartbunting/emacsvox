;;; emacsvox-elfeed.el --- Speech-enable ELFEED -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop elfeed, Feed Reader
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
;; ELFEED ==  Feed Reader for Emacs.
;; Install from elpa
;; M-x package-install  elfeed

;;   Required modules:
;;; Code:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'emacsvox-we)
(require 'elfeed "elfeed" 'no-error)

;;;  Map Faces to voices

(voice-setup-add-map
 '(
   (elfeed-search-date-face  voice-smoothen)
   (elfeed-search-title-face voice-lighten)
   (elfeed-search-unread-title-face voice-bolden)
   (elfeed-search-feed-face voice-animate)
   (elfeed-search-tag-face voice-lighten)))

;;;  Advice interactive commands:

(defvar emacsvox-elfeed--advice nil
  "Current Elfeed targets and their native advice functions.")
(setq emacsvox-elfeed--advice nil)

(defun emacsvox-elfeed--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback))))
      (push (list target :after advice-function)
            emacsvox-elfeed--advice))))

(defun emacsvox-elfeed--task-feedback ()
  "Confirm an Elfeed operation and speak the current line."
  (emacsvox-icon 'task-done)
  (emacsvox-speak-line))

(emacsvox-elfeed--register-after-group
 '(elfeed-apply-hooks-now elfeed-search-browse-url elfeed-show-visit
   elfeed-update-feed elfeed-update elfeed-show-refresh
   elfeed-search-update--force elfeed-search-update
   elfeed-search-untag-all-unread
   elfeed-search-untag-all elfeed-search-tag-all-unread
   elfeed-search-tag-all elfeed-load-opml elfeed-export-opml
   elfeed-db-compact elfeed-add-feed)
 #'emacsvox-elfeed--task-feedback)

(defun emacsvox-elfeed--selection-feedback ()
  "Speak an Elfeed tag selection."
  (emacsvox-icon 'select-object)
  (emacsvox-speak-line))

(emacsvox-elfeed--register-after-group
 '(elfeed-show-tag elfeed-show-untag)
 #'emacsvox-elfeed--selection-feedback)

(defun emacsvox-elfeed--open-entry-feedback ()
  "Speak an Elfeed entry after opening it."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-line))

(emacsvox-elfeed--register-after-group
 '(elfeed-show-entry)
 #'emacsvox-elfeed--open-entry-feedback)

(defun emacsvox-elfeed--task-icon-feedback ()
  "Confirm an Elfeed enclosure operation."
  (emacsvox-icon 'task-done))

(emacsvox-elfeed--register-after-group
 '(elfeed-show-add-enclosure-to-playlist elfeed-show-play-enclosure)
 #'emacsvox-elfeed--task-icon-feedback)

(defun emacsvox-elfeed--open-feedback ()
  "Play an icon after opening Elfeed."
  (emacsvox-icon 'open-object))

(emacsvox-elfeed--register-after-group
 '(elfeed)
 #'emacsvox-elfeed--open-feedback)

(defun emacsvox-elfeed--close-feedback ()
  "Speak after closing an Elfeed view."
  (emacsvox-icon 'close-object)
  (emacsvox-speak-mode-line))

(emacsvox-elfeed--register-after-group
 '(elfeed-kill-buffer elfeed-search-quit-window)
 #'emacsvox-elfeed--close-feedback)

(defun emacsvox-elfeed--yank-feedback ()
  "Play an icon after copying an Elfeed URL."
  (emacsvox-icon 'yank-object))

(emacsvox-elfeed--register-after-group
 '(elfeed-search-yank)
 #'emacsvox-elfeed--yank-feedback)

;;;  Helpers:

(defun emacsvox-elfeed-entry-at-point ()
  "Return entry at point."
  
  (let ((index  (- (line-number-at-pos (point)) elfeed-search--offset)))
    (cond
     ((>= index 0) (nth index elfeed-search-entries))
     (t (error "No entry at point.")))))

(defun emacsvox-elfeed-speak-entry-at-point ()
  "Speak entry at point."
  (interactive)
  (let* ((e (emacsvox-elfeed-entry-at-point))
         (title (and e (elfeed-entry-title e)))
         (tags (and e (elfeed-entry-tags e))))
    (unless e (message "No entry here"))
    (when title
      (tts-speak (propertize title 'personality voice-brighten))
      (when (memq 'read tags)
        (emacsvox-icon 'modified-object))
      (when (memq 'seen  tags)
        (emacsvox-icon 'mark-object))
      (emacsvox-icon 'item)
      (elfeed-tag e 'seen))))

;;;  Define additional interactive commands:

(defun emacsvox-elfeed-next-entry ()
  "Move to next entry and speak it."
  (interactive)
  (forward-line 1)
  (emacsvox-elfeed-speak-entry-at-point))

(defun emacsvox-elfeed-previous-entry ()
  "Move to previous entry and speak it."
  (interactive)
  (forward-line -1)
  (emacsvox-elfeed-speak-entry-at-point))

(defun emacsvox-elfeed-filter-entry-at-point ()
  "Display current article after filtering."
  (interactive)
  
  (let* ((entry (emacsvox-elfeed-entry-at-point))
         (link(elfeed-entry-link entry)))
    (when (string=  "" emacsvox-we-recent-xpath-filter)
      (setq emacsvox-we-recent-xpath-filter "//p"))
    (cond
     (entry (elfeed-untag  entry 'unread)
            (emacsvox-we-xslt-filter
             emacsvox-we-recent-xpath-filter link 'speak))
     (t (message "No link under point.")))))

(defun emacsvox-elfeed-eww-entry-at-point ()
  "Display current article in EWW."
  (interactive)
  (let* ((entry (emacsvox-elfeed-entry-at-point))
         (link(elfeed-entry-link entry)))
    (cond
     (entry (elfeed-untag  entry 'unread)
            (eww link))
     (t (message "No link under point.")))))

;;;  Silence warnings/errors

(defconst emacsvox-elfeed--silenced-targets
  '(elfeed-update-feed elfeed-handle-parse-error elfeed-handle-http-error
    elfeed-unjam elfeed-update)
  "Elfeed operations whose incidental errors are silenced.")

(cl-loop
 for target in emacsvox-elfeed--silenced-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(defun ,advice-function (original &rest args)
     ,(format "Call `%s' while silencing incidental errors." target)
     (ems-with-errors-silenced
      (apply original args))))
 (push (list target :around advice-function) emacsvox-elfeed--advice))

;;;  Set things up

(defun emacsvox--advice-elfeed-search-mode-after (&rest _)
  "Set up Emacsvox commands."
  
  (setq goal-column 11)
  (define-key elfeed-search-mode-map "n" 'emacsvox-elfeed-next-entry)
  (define-key elfeed-search-mode-map "p"
              'emacsvox-elfeed-previous-entry)
  (define-key elfeed-search-mode-map "."
              'emacsvox-elfeed-filter-entry-at-point)
  (define-key elfeed-search-mode-map [right]
              'emacsvox-elfeed-filter-entry-at-point)
  (define-key elfeed-search-mode-map "e"
              'emacsvox-elfeed-eww-entry-at-point)
  (define-key elfeed-search-mode-map " "
              'emacsvox-elfeed-speak-entry-at-point))

(push '(elfeed-search-mode :after
        emacsvox--advice-elfeed-search-mode-after)
      emacsvox-elfeed--advice)

(defconst emacsvox-elfeed--removed-targets
  '(elfeed-ssearch-show-entry)
  "Misspelled Elfeed targets removed during migration.")

(defun emacsvox-elfeed--install-advice ()
  "Install native advice for currently loaded Elfeed features."
  (dolist (entry emacsvox-elfeed--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function
                    (list (cons 'name function)))))))

(dolist (feature '(elfeed elfeed-db elfeed-search elfeed-show))
  (eval
   `(with-eval-after-load ',feature
      (emacsvox-elfeed--install-advice))))

(provide 'emacsvox-elfeed)

;;; emacsvox-elfeed.el ends here
