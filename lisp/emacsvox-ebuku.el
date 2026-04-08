;;; emacsvox-ebuku.el --- Speech-enable EBUKU  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Keywords: Emacsvox,  Audio Desktop ebuku
;;; LCD Archive Entry:
;; emacsvox| T. V. Raman |raman@cs.cornell.edu
;; A speech interface to Emacs |
;;  $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacsvox
;;;   Copyright:

;; Copyright (C) 1995 -- 2022, T. V. Raman
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
;; EBUKU ==  Emacs Buku front-end to manage bookmarks.

;;; Code:

;;   Required modules

(eval-when-compile  (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'ebuku nil "ebuku")
;;;  Map Faces:

(voice-setup-add-map
 '(
   (ebuku-comment-face voice-monotone)
   (ebuku-heading-face voice-bolden)
   (ebuku-help-face voice-lighten)
   (ebuku-tags-face voice-bolden)
   (ebuku-title-face voice-animate)
   (ebuku-url-face voice-smoothen)
   (ebuku-url-highlight-face voice-brighten)))

;;;  Interactive Commands:

;; in fond memory of the past:
;; See obsolete emacsvox-fix-interactive in our attic.

(defun ems--ebuku-search-before (&rest _)
  "Advice prompt to speak" (interactive (list (read-char "n,l,r,t"))))

(advice-add 'ebuku-search :before #'ems--ebuku-search-before)

(defun ems--ebuku--search-helper-before (&rest _)
  "Avoid exclude to speed up interaction.." (ad-set-arg 3 ""))

(advice-add 'ebuku--search-helper :before
            #'ems--ebuku--search-helper-before)

(cl-loop
 for f in
 '(
   ebuku-search-on-any ebuku-search-on-all
   ebuku-search ebuku-search-on-reg ebuku-search-on-tag)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'task-done)
       (emacsvox-speak-line)
       (save-excursion
         (forward-line -2)
         (forward-word 2)
         (dtk-notify (word-at-point)))))))

(defun ems--ebuku-show-all-after (&rest _)
  "speak."
  (when (ems-interactive-p) (dtk-speak "Showing all bookmarks")))

(advice-add 'ebuku-show-all :after #'ems--ebuku-show-all-after)

(defun ems--ebuku-toggle-results-limit-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (message "Results limit: %s" ebuku-results-limit)
    (emacsvox-icon 'button)))

(advice-add 'ebuku-toggle-results-limit :after
            #'ems--ebuku-toggle-results-limit-after)

(cl-loop
 for f in
 '(ebuku-previous-bookmark ebuku-next-bookmark)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'select-object)
       (emacsvox-read-previous-line)))))

(defun ems--ebuku-open-url-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'button)))

(advice-add 'ebuku-open-url :after #'ems--ebuku-open-url-after)

(defun ems--ebuku-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-mode-line) (emacsvox-icon 'open-object)))

(advice-add 'ebuku :after #'ems--ebuku-after)

;;; Additional Keybindings:

(cl-declaim (special ebuku-mode-map))
(cl-loop
 for b in
 '(
   ("/" ebuku-search-on-any)
   ("l" ebuku-search-on-all)
   ("r" ebuku-search-on-reg)
   ("t" ebuku-search-on-tag))
 do
 (emacsvox-keymap-update ebuku-mode-map b))

(provide 'emacsvox-ebuku)
;;;  end of file
