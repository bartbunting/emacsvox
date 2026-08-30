;;; emacsvox-elpy.el --- Speech-enable ELPY -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop elpy
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
;; ELPY ==  Emacs Lisp Python IDE
;; Speech-enables all aspects of elpy.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'emacsvox-python)

;;;  Advice Interactive Commands:

(defconst emacsvox-elpy--started-targets
  '(elpy-check elpy-occur-definitions elpy-rgrep-symbol
    elpy-shell-send-statement-and-step elpy-shell-send-region-or-buffer
    )
  "Elpy commands that start checking, searching, or code execution.")

(defconst emacsvox-elpy--completed-targets
  '(elpy-autopep8-fix-code
    elpy-set-project-root elpy-set-project-variable elpy-set-test-runner
    elpy-use-cpython elpy-use-ipython
    elpy-importmagic-add-import elpy-importmagic-fixup)
  "Elpy commands whose synchronous operation has completed.")

(defconst emacsvox-elpy--destination-targets
  '(elpy-config elpy-shell-switch-to-buffer elpy-shell-switch-to-shell
    elpy-find-file)
  "Elpy commands that select a different buffer or interface.")

(defconst emacsvox-elpy--task-targets
  (append emacsvox-elpy--started-targets emacsvox-elpy--completed-targets)
  "Elpy operation commands, retained for compatibility with integrations.")

(defun emacsvox-elpy--submit-text
    (text facts occasion &optional icon)
  "Submit Elpy TEXT under FACTS and OCCASION with optional ICON."
  (emacsvox-aural-submit
   text
   :facts facts
   :module 'python
   :occasion occasion
   :compatibility-actions
   (when icon
     (list (emacsvox-aural-compatibility-icon icon)))))

(defun emacsvox-elpy--submit-message
    (text facts occasion &optional icon)
  "Display and natively present Elpy TEXT."
  (let ((emacsvox-speak-messages nil))
    (message "%s" text))
  (emacsvox-elpy--submit-text text facts occasion icon))

(defun emacsvox-elpy--present-operation (target outcome)
  "Present Elpy operation TARGET with OUTCOME and current buffer context."
  (emacsvox-elpy--submit-text
   (emacsvox-python--buffer-summary)
   (emacsvox-python--operation-facts target outcome)
   'state-change))

(cl-loop
 for target in (append
                emacsvox-elpy--started-targets
                emacsvox-elpy--completed-targets)
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Present the result of `%s'." target)
     (when (ems-interactive-p ',target)
       (emacsvox-elpy--present-operation
        ',target
        ,(if (memq target emacsvox-elpy--started-targets)
             ''started
           ''completed))))))

(cl-loop
 for target in emacsvox-elpy--destination-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Present the destination selected by `%s'." target)
     (when (ems-interactive-p ',target)
       (emacsvox-elpy--submit-text
        (emacsvox-python--buffer-summary)
        '(:role code-construct
          :events (focus-entered)
          :syntax-role destination)
        'navigation 'open-object)))))

(defun emacsvox--advice-elpy-enable-after (&rest _)
  "Report enabling Elpy."
  (when (ems-interactive-p 'elpy-enable)
    (emacsvox-elpy--submit-message
     "Enabled Elpy"
     '(:role code-operation
       :events (state-changed)
       :code-operation-kind elpy-enable)
     'state-change 'on)))

(defun emacsvox--advice-elpy-disable-after (&rest _)
  "Report disabling Elpy."
  (when (ems-interactive-p 'elpy-disable)
    (emacsvox-elpy--submit-message
     "Disabled Elpy"
     '(:role code-operation
       :events (state-changed)
       :code-operation-kind elpy-disable)
     'state-change 'off)))

(defun emacsvox--advice-elpy-doc-after (&rest _)
  "Report displaying Elpy documentation."
  (when (ems-interactive-p 'elpy-doc)
    (emacsvox-elpy--submit-message
     "Displayed help in other window"
     '(:role code-construct
       :events (focus-entered)
       :syntax-role documentation)
     'navigation 'help)))

(defconst emacsvox-elpy--navigation-targets
  '(elpy-flymake-next-error elpy-flymake-previous-error
    elpy-goto-definition
    elpy-nav-backward-block elpy-nav-backward-indent
    elpy-nav-expand-to-indentation elpy-nav-forward-block
    elpy-nav-forward-indent)
  "Elpy commands that navigate among source constructs.")

(defconst emacsvox-elpy--edit-targets
  '(elpy-nav-indent-shift-left elpy-nav-indent-shift-right
    elpy-open-and-indent-line-below elpy-open-and-indent-line-above
    elpy-nav-move-line-or-region-down elpy-nav-move-line-or-region-up)
  "Elpy commands that edit indentation or source structure.")

(defconst emacsvox-elpy--movement-targets
  (append emacsvox-elpy--navigation-targets emacsvox-elpy--edit-targets)
  "Elpy movement and edit targets retained for compatibility.")

(cl-loop
 for target in emacsvox-elpy--movement-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Present the source result of `%s'." target)
     (when (ems-interactive-p ',target)
       (if (memq ',target emacsvox-elpy--navigation-targets)
           (emacsvox-python--present-current-line
            '(:role code-construct
              :events (focus-entered)
              :syntax-role construct
              :code-navigation-kind elpy)
            'navigation)
         (emacsvox-python--present-current-line
          (emacsvox-python--edit-facts
           (cond
            ((eq ',target 'elpy-nav-indent-shift-left) 'shift-left)
            ((eq ',target 'elpy-nav-indent-shift-right) 'shift-right)
            (t 'elpy-structural))
           'block)
          'edit))))))

(defconst emacsvox-elpy--removed-targets
  '(elpy-shell-send-current-statement)
  "Obsolete Elpy command names removed during migration.")

(defconst emacsvox-elpy--advice-targets
  (append emacsvox-elpy--task-targets
          emacsvox-elpy--destination-targets
          '(elpy-enable elpy-disable elpy-doc)
          emacsvox-elpy--movement-targets)
  "Current Elpy targets that receive native after advice.")

(defun emacsvox-elpy--install-advice ()
  "Install native advice after the optional Elpy package loads."
  (dolist (target emacsvox-elpy--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'elpy
  (emacsvox-elpy--install-advice))

(provide 'emacsvox-elpy)

;;; emacsvox-elpy.el ends here
