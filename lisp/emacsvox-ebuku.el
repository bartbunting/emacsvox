;;; emacsvox-ebuku.el --- Speech-enable EBUKU  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2022, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop ebuku
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
;; EBUKU ==  Emacs Buku front-end to manage bookmarks.

;;; Code:

;;   Required modules

(eval-when-compile  (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'ebuku nil t)
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

(defun emacsvox--advice-ebuku--search-helper-filter-args (args)
  "Return ARGS with the optional exclude term disabled."
  (let ((result
         (append args (make-list (max 0 (- 4 (length args))) nil))))
    (setf (nth 3 result) "")
    result))

(defconst emacsvox-ebuku--search-targets
  '(ebuku-search-on-any ebuku-search-on-all
    ebuku-search ebuku-search-on-reg ebuku-search-on-tag)
  "Ebuku search commands that receive speech feedback.")

(cl-loop
 for target in emacsvox-ebuku--search-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Speak search results after `%s'." target)
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'task-done)
       (emacsvox-speak-line)
       (save-excursion
         (forward-line -2)
         (forward-word 2)
         (tts-notify (word-at-point)))))))

(defun emacsvox--advice-ebuku-show-all-after (&rest _)
  "Speak after showing every bookmark."
  (when (ems-interactive-p 'ebuku-show-all)
    (tts-speak "Showing all bookmarks")))

(defun emacsvox--advice-ebuku-toggle-results-limit-after (&rest _)
  "Report the new Ebuku results limit."
  (when (ems-interactive-p 'ebuku-toggle-results-limit)
    (message "Results limit: %s" ebuku-results-limit)
    (emacsvox-icon 'button)))

(defconst emacsvox-ebuku--movement-targets
  '(ebuku-previous-bookmark ebuku-next-bookmark)
  "Ebuku bookmark navigation commands.")

(cl-loop
 for target in emacsvox-ebuku--movement-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Speak after `%s'." target)
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'select-object)
       (emacsvox-read-previous-line)))))

(defun emacsvox--advice-ebuku-open-url-after (&rest _)
  "Play a button icon after opening an Ebuku URL."
  (when (ems-interactive-p 'ebuku-open-url)
    (emacsvox-icon 'button)))

(defun emacsvox--advice-ebuku-after (&rest _)
  "Speak after opening Ebuku."
  (when (ems-interactive-p 'ebuku)
    (emacsvox-speak-mode-line) (emacsvox-icon 'open-object)))

(defconst emacsvox-ebuku--after-targets
  (append emacsvox-ebuku--search-targets
          '(ebuku-show-all ebuku-toggle-results-limit)
          emacsvox-ebuku--movement-targets
          '(ebuku-open-url ebuku))
  "Current Ebuku targets that receive native after advice.")

(defconst emacsvox-ebuku--advice
  (append
   '((ebuku--search-helper :filter-args
      emacsvox--advice-ebuku--search-helper-filter-args))
   (mapcar
    (lambda (target)
      (list target :after
            (intern (format "emacsvox--advice-%s-after" target))))
    emacsvox-ebuku--after-targets))
  "Current Ebuku native advice specifications.")

(defun emacsvox-ebuku--install-advice ()
  "Install native advice after the optional Ebuku package loads."
  (dolist (entry emacsvox-ebuku--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

;;; Additional Keybindings:

(cl-declaim (special ebuku-mode-map))

(defun emacsvox-ebuku--install-keys ()
  "Install Emacsvox bindings in `ebuku-mode-map'."
  (cl-loop
   for b in
   '(
     ("/" ebuku-search-on-any)
     ("l" ebuku-search-on-all)
     ("r" ebuku-search-on-reg)
     ("t" ebuku-search-on-tag))
   do
   (emacsvox-keymap-update ebuku-mode-map b)))

(with-eval-after-load 'ebuku
  (emacsvox-ebuku--install-advice)
  (emacsvox-ebuku--install-keys))

(provide 'emacsvox-ebuku)

;;; emacsvox-ebuku.el ends here
