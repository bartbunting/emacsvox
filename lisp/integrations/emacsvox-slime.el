;;; emacsvox-slime.el --- Speech-enable SLIME -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop slime
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
 ;;; SLIME == Superior  Lisp Interaction Mode For Emacs

;; Slime is a powerful IDE for developing in Common Lisp and Clojure.
;; It's similar but more modern than package ILisp that I used as a
;; graduate student when developing AsTeR.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (slime-error-face voice-animate)
   (slime-warning-face voice-animate-medium)
   (slime-style-warning-face voice-animate-medium)
   (slime-note-face voice-monotone-extra)
   (slime-highlight-face voice-animate-extra)
   (slime-apropos-symbol voice-monotone-medium)
   (slime-apropos-label voice-monotone-medium)
   (slime-inspector-topline-face voice-bolden-medium)
   (slime-inspector-label-face voice-monotone-medium)
   (slime-inspector-value-face voice-animate)
   (slime-inspector-action-face voice-bolden)
   (slime-inspector-type-face voice-smoothen)
   (sldb-catch-tag-face   voice-lighten)
   (sldb-condition-face  voice-smoothen)
   (sldb-detailed-frame-line-face voice-monotone-extra)
   (sldb-frame-label-face voice-annotate)
   (sldb-frame-line-face voice-lighten-extra)
   (sldb-local-name-face voice-bolden)
   (sldb-local-value-face voice-animate)
   (sldb-non-restartable-frame-line-face voice-animate-extra)
   (sldb-reference-face voice-smoothen-extra)
   (sldb-restart-face voice-bolden)
   (sldb-restart-number-face voice-smoothen)
   (sldb-restart-type-face voice-animate)
   (sldb-restartable-frame-line-face voice-bolden)
   (sldb-section-face voice-bolden-medium)
   (sldb-topline-face voice-bolden)
   (slime-reader-conditional-face  voice-brighten)
   (slime-repl-input-face voice-brighten-medium)
   (slime-repl-inputed-output-face voice-bolden-and-animate)
   (slime-repl-output-face voice-bolden)
   (slime-repl-output-mouseover-face voice-bolden-and-animate)
   (slime-repl-prompt-face voice-smoothen)
   (slime-repl-result-face voice-animate)))

;;;  Navigation And Repl:

(defvar emacsvox-slime--advice nil
  "Current Slime targets and their native advice functions.")
(setq emacsvox-slime--advice nil)

(defun emacsvox-slime--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback))))
      (push (list target :after advice-function) emacsvox-slime--advice))))

(defun emacsvox-slime--movement-feedback ()
  "Speak after moving through a Slime view."
  (emacsvox-icon 'large-movement)
  (emacsvox-speak-line))

(emacsvox-slime--register-after-group
 '(slime-xref-next-line slime-xref-prev-line slime-goto-xref
   slime-repl-backward-input slime-repl-forward-input
   slime-repl-previous-matching-input slime-repl-previous-input
   slime-repl-next-matching-input slime-repl-next-input
   slime-repl-end-of-defun slime-repl-beginning-of-defun
   slime-end-of-defun slime-beginning-of-defun
   slime-close-all-parens-in-sexp slime-repl-previous-prompt
   slime-repl-next-prompt slime-next-presentation slime-previous-presentation
   slime-next-location slime-previous-location slime-edit-definition
   slime-pop-find-definition-stack slime-edit-definition-other-frame
   slime-edit-definition-other-window slime-next-note slime-previous-note)
 #'emacsvox-slime--movement-feedback)

(defun emacsvox-slime--help-buffer-feedback ()
  "Speak the current Slime help buffer."
  (emacsvox-icon 'help)
  (emacsvox-speak-buffer))

(emacsvox-slime--register-after-group
 '(slime-info)
 #'emacsvox-slime--help-buffer-feedback)

(defun emacsvox-slime--open-feedback ()
  "Speak a newly opened Slime view."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-mode-line))

(emacsvox-slime--register-after-group
 '(slime-selector slime-scratch)
 #'emacsvox-slime--open-feedback)

(add-hook
 'slime-repl-mode-hook
 'emacsvox-pronounce-refresh-pronunciations)

(defun emacsvox-slime--repl-return-feedback ()
  "Speak output produced by a Slime REPL command."
  (save-excursion
    (goto-char
     (previous-single-property-change (point) 'face nil (point-min)))
    (emacsvox-speak-range))
  (emacsvox-icon 'close-object))

(emacsvox-slime--register-after-group
 '(slime-repl-return slime-repl-closing-return
   slime-repl-set-package slime-handle-repl-shortcut)
 #'emacsvox-slime--repl-return-feedback)

(defun emacsvox-slime--completion-around (target orig-fun &rest args)
  "Call ORIG-FUN once and speak completion performed by Slime TARGET."
  (ems-with-messages-silenced
   (let* ((prior (save-excursion (skip-syntax-backward "^ >") (point)))
          (result (apply orig-fun args)))
     (when (ems-interactive-p target)
       (if (> (point) prior)
           (tts-with-punctuations
            'all
            (tts-speak (buffer-substring prior (point))))
         (emacsvox-speak-completions-if-available)))
     result)))

(dolist (target '(slime-complete-symbol slime-indent-and-complete-symbol))
  (let ((advice-function
         (intern (format "emacsvox--advice-%s-around" target))))
    (eval
     `(defun ,advice-function (orig-fun &rest args)
        ,(format "Speak completion performed by `%s'." target)
        (apply #'emacsvox-slime--completion-around
               ',target orig-fun args)))
    (push (list target :around advice-function) emacsvox-slime--advice)))

(defun emacsvox-slime--delete-feedback ()
  "Announce a Slime deletion."
  (emacsvox-icon 'delete-object))

(emacsvox-slime--register-after-group
 '(slime-delete-system-fasls slime-delete-package
   slime-repl-delete-from-input-history slime-repl-delete-current-input
   slime-repl-kill-input slime-repl-clear-output slime-repl-clear-buffer)
 #'emacsvox-slime--delete-feedback)

(defun emacsvox-slime--close-feedback ()
  "Announce closing a Slime connection or REPL."
  (emacsvox-icon 'close-object))

(emacsvox-slime--register-after-group
 '(slime-repl-sayoonara slime-repl-quit slime-disconnect-all
   slime-disconnect slime-repl-disconnect-all slime-repl-disconnect)
 #'emacsvox-slime--close-feedback)

(defun emacsvox-slime--task-feedback ()
  "Announce completion of a Slime task."
  (emacsvox-icon 'task-done))

(emacsvox-slime--register-after-group
 '(
   slime-eval-buffer slime-eval-defun
   slime-eval-last-expression slime-eval-last-expression-in-repl
   slime-eval-macroexpand-inplace slime-eval-print-last-expression
   slime-eval-region slime-expand-1 slime-expand-1-inplace
   slime-export-class slime-export-structure slime-export-symbol-at-point
   slime-format-string-expand
   slime-connect
   slime-repl-test/force-system slime-repl-test-system
   slime-repl-reload-system slime-repl-open-system slime-reload-system
   slime-repl-load/force-system slime-repl-load-system
   slime-load-file slime-load-system
   slime-repl-delete-system-fasls slime-repl-compile/force-system
   slime-quit-lisp
   slime-repl-compile-system
   slime-repl-compile-and-load slime-repl-browse-system)
 #'emacsvox-slime--task-feedback)

(defun emacsvox-slime--inspect-feedback ()
  "Announce opening the Slime inspector."
  (emacsvox-icon 'open-object))

(emacsvox-slime--register-after-group
 '(slime-repl-inspect)
 #'emacsvox-slime--inspect-feedback)

(defun emacsvox-slime--help-window-feedback ()
  "Announce Slime help displayed in another window."
  (emacsvox-icon 'help)
  (tts-speak "Displayed help in other window."))

(emacsvox-slime--register-after-group
 '(slime-list-repl-short-cuts slime-repl-shortcut-help slime-documentation)
 #'emacsvox-slime--help-window-feedback)

(defun emacsvox-slime--help-frame-feedback ()
  "Announce the Slime cheat sheet."
  (emacsvox-icon 'help)
  (tts-speak "Displaying help in new frame."))

(emacsvox-slime--register-after-group
 '(slime-cheat-sheet)
 #'emacsvox-slime--help-frame-feedback)

;;;  Writing Code:
(emacsvox-slime--register-after-group
 '(slime-compile-and-load-file
   slime-compile-defun slime-compile-file
   slime-compile-region slime-compiler-macroexpand-1
   slime-compiler-macroexpand-1-inplace
   slime-compiler-notes-default-action-or-show-details
   slime-compiler-notes-default-action-or-show-details/mouse
   slime-compiler-notes-show-details)
 #'emacsvox-slime--task-feedback)

;;;  Lisp Interaction:

;;;  Browsing Documentation:

(defun emacsvox-slime--documentation-feedback ()
  "Speak Slime's description buffer."
  (sit-for 0.1)
  (with-current-buffer (slime-buffer-name :description)
    (emacsvox-speak-buffer)
    (emacsvox-icon 'help)))

(emacsvox-slime--register-after-group
 '(
   slime-documentation-lookup
   slime-describe-function  slime-describe-symbol slime-describe-presentation
   slime-apropos slime-apropos-package slime-apropos-summary)
 #'emacsvox-slime--documentation-feedback)

;;;  Inspector:

(defun emacsvox-slime--inspector-pop-feedback ()
  "Speak after returning in the Slime inspector."
  (emacsvox-icon 'close-object)
  (emacsvox-speak-line))

(emacsvox-slime--register-after-group
 '(slime-inspector-pop)
 #'emacsvox-slime--inspector-pop-feedback)

(defun emacsvox-slime--inspector-pprint-feedback ()
  "Announce a pretty-printed Slime description."
  (tts-speak "Pretty printed description in other window.")
  (emacsvox-icon 'open-object))

(emacsvox-slime--register-after-group
 '(slime-inspector-pprint)
 #'emacsvox-slime--inspector-pprint-feedback)

(defun emacsvox-slime--inspector-quit-feedback ()
  "Speak after closing the Slime inspector."
  (emacsvox-icon 'close-object)
  (emacsvox-speak-mode-line))

(emacsvox-slime--register-after-group
 '(slime-inspector-quit)
 #'emacsvox-slime--inspector-quit-feedback)

(defun emacsvox-slime--inspector-toggle-feedback ()
  "Speak after toggling verbose Slime inspection."
  (emacsvox-icon 'button)
  (emacsvox-speak-line))

(emacsvox-slime--register-after-group
 '(slime-inspector-toggle-verbose)
 #'emacsvox-slime--inspector-toggle-feedback)

(defun emacsvox-slime--inspector-movement-feedback ()
  "Speak after moving through Slime inspector objects."
  (emacsvox-speak-range)
  (emacsvox-icon 'large-movement))

(emacsvox-slime--register-after-group
 '(slime-inspector-next-inspectable-object
   slime-inspector-previous-inspectable-object)
 #'emacsvox-slime--inspector-movement-feedback)

(defun emacsvox-slime--inspector-open-feedback ()
  "Speak an object opened in the Slime inspector."
  (emacsvox-speak-line)
  (emacsvox-icon 'open-object))

(emacsvox-slime--register-after-group
 '(
   slime-inspector-operate-on-point slime-inspector-operate-on-click
   slime-inspector-show-source slime-inspect slime-inspect-definition
   slime-inspector-reinspect slime-inspector-next slime-inspector-fetch-all
   slime-inspect-presentation-at-mouse slime-inspect-presentation-at-point)
 #'emacsvox-slime--inspector-open-feedback)

(defun emacsvox-slime--inspector-help-feedback ()
  "Speak Slime inspector help."
  (emacsvox-speak-buffer)
  (emacsvox-icon 'help))

(emacsvox-slime--register-after-group
 '(slime-inspector-history slime-inspector-describe)
 #'emacsvox-slime--inspector-help-feedback)

(defun emacsvox-slime--install-advice ()
  "Install advice for Slime features loaded so far."
  (dolist (entry emacsvox-slime--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(dolist (feature '(slime slime-asdf slime-cheat-sheet slime-compiler-notes
                   slime-fancy slime-repl))
  (eval `(with-eval-after-load ',feature
           (emacsvox-slime--install-advice))))

;;;  Debugger:

(provide 'emacsvox-slime)

;;; emacsvox-slime.el ends here
