;;; emacsvox-cider.el --- Speech-enable CIDER -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable CIDER An Emacs Interface to cider
;; Keywords: Emacsvox,  Audio Desktop, cider
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:
;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
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
;; MERCHANTABILITY or FITNCIDER FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; Speech-Enable CIDER --- Clojure IDE

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(defvar cider-repl-use-pretty-printing)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (cider-debug-code-overlay-face voice-monotone-extra)
   (cider-debug-prompt-face voice-animate)
   (cider-deprecated-face voice-monotone-extra)
   (cider-docview-emphasis-face voice-lighten)
   (cider-docview-literal-face voice-monotone-medium)
   (cider-docview-strong-face voice-monotone-medium)
   (cider-enlightened-face voice-lighten)
   (cider-enlightened-local-face voice-lighten-extra)
   (cider-error-highlight-face voice-animate)
   (cider-fragile-button-face voice-annotate)
   (cider-instrumented-face voice-monotone-medium)
   (cider-repl-input-face voice-animate)
   (cider-repl-prompt-face voice-annotate)
   (cider-repl-result-face voice-bolden)
   (cider-repl-stderr-facevoice-animate)
   (cider-repl-stdout-face voice-bolden-medium)
   (cider-result-overlay-face voice-bolden)
   (cider-stacktrace-error-class-face voice-animate)
   (cider-stacktrace-error-message-face voice-animate-extra)
   (cider-stacktrace-face voice-bolden)
   (cider-stacktrace-filter-hidden-face voice-smoothen)
   (cider-stacktrace-filter-shown-face voice-bolden-and-animate)
   (cider-stacktrace-fn-face voice-bolden)
   (cider-stacktrace-ns-face voice-smoothen)
   (cider-stacktrace-promoted-button-face voice-animate)
   (cider-stacktrace-suppressed-button-face voice-smoothen-extra)
   (cider-test-error-face voice-animate)
   (cider-test-failure-face voice-animate-extra)
   (cider-test-success-face voice-bolden-medium)
   (cider-traced-face voice-bolden)
   (cider-warning-highlight-face voice-animate-extra)
   ))

;;; Advice:

(defvar emacsvox-cider--advice nil
  "Current CIDER targets and their native advice functions.")

(defun emacsvox-cider--register-after-group (targets feedback)
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
            emacsvox-cider--advice))))

(defun emacsvox-cider--open-feedback ()
  "Speak the mode line after opening a CIDER view."
  (emacsvox-speak-mode-line)
  (emacsvox-icon 'open-object))

(defconst emacsvox-cider--open-targets
  '(cider-selector
    cider-scratch
    cider-switch-to-last-clojure-buffer
    cider-switch-to-repl-buffer
    cider-apropos
    cider-apropos-documentation
    cider-apropos-documentation-select
    cider-apropos-select
    cider-connect-clj
    cider-connect-cljs
    cider-connect-clj&cljs)
  "CIDER commands that open a buffer, view, or connection.")
(emacsvox-cider--register-after-group
 emacsvox-cider--open-targets #'emacsvox-cider--open-feedback)

(defun emacsvox-cider--task-done-feedback ()
  "Confirm completion of a CIDER operation."
  (emacsvox-icon 'task-done))

(defconst emacsvox-cider--task-done-targets
  '(cider-format-buffer
    cider-format-region
    cider-format-edn-region
    cider-format-edn-buffer
    cider-undef
    cider-eval-defun-at-point
    cider-eval-defun-to-comment
    cider-eval-file
    cider-eval-last-sexp
    cider-eval-last-sexp-and-replace
    cider-eval-last-sexp-to-repl
    cider-eval-ns-form
    cider-eval-print-last-sexp
    cider-eval-buffer
    cider-eval-region
    cider-eval-sexp-at-point)
  "CIDER formatting and evaluation commands.")
(emacsvox-cider--register-after-group
 emacsvox-cider--task-done-targets #'emacsvox-cider--task-done-feedback)

(defun emacsvox-cider--browse-feedback ()
  "Speak the selected line in a CIDER browser."
  (with-current-buffer (window-buffer (selected-window))
    (emacsvox-icon 'open-object)
    (emacsvox-speak-line)))

(defconst emacsvox-cider--browse-targets
  '(cider-browse-instrumented-defs
    cider-browse-ns
    cider-browse-ns-all
    cider-browse-ns-operate-at-point
    cider-browse-ns-doc-at-point
    cider-classpath-operate-on-point
    cider-browse-ns-find-at-point
    cider-classpath
    cider-doc)
  "CIDER browsing commands.")
(emacsvox-cider--register-after-group
 emacsvox-cider--browse-targets #'emacsvox-cider--browse-feedback)

(defun emacsvox-cider--movement-feedback ()
  "Speak after navigating through CIDER REPL input."
  (emacsvox-icon 'large-movement)
  (emacsvox-speak-line))

(defconst emacsvox-cider--movement-targets
  '(cider-repl-previous-prompt
    cider-repl-previous-matching-input
    cider-repl-previous-input
    cider-repl-next-prompt
    cider-repl-next-matching-input
    cider-repl-next-input
    cider-repl-forward-input
    cider-repl-backward-input
    cider-repl-end-of-defun
    cider-repl-beginning-of-defun)
  "CIDER REPL navigation commands.")
(emacsvox-cider--register-after-group
 emacsvox-cider--movement-targets #'emacsvox-cider--movement-feedback)

(defun emacsvox-cider--return-feedback ()
  "Speak output inserted by a CIDER REPL return."
  (save-excursion
    (goto-char
     (previous-single-property-change (point) 'face nil (point-min)))
    (emacsvox-speak-range))
  (emacsvox-icon 'close-object))

(defconst emacsvox-cider--return-targets
  '(cider-repl-closing-return cider-repl-return)
  "CIDER REPL return commands.")
(emacsvox-cider--register-after-group
 emacsvox-cider--return-targets #'emacsvox-cider--return-feedback)

(defun emacsvox-cider--delete-feedback ()
  "Confirm deletion of CIDER output or input."
  (emacsvox-icon 'delete-object))

(defconst emacsvox-cider--delete-targets
  '(cider-clear-compilation-highlights
    cider-repl-kill-input
    cider-scratch-reset
    cider-repl-clear-buffer
    cider-find-and-clear-repl-output
    cider-repl-clear-help-banner
    cider-repl-clear-output)
  "CIDER commands that clear input, output, or highlighting.")
(emacsvox-cider--register-after-group
 emacsvox-cider--delete-targets #'emacsvox-cider--delete-feedback)

(defun emacsvox-cider--line-selection-feedback ()
  "Speak the current line and confirm selection."
  (emacsvox-speak-line)
  (emacsvox-icon 'select-object))

(defconst emacsvox-cider--line-selection-targets
  '(cider-repl-tab
    cider-repl-indent-and-complete-symbol
    cider-repl-newline-and-indent
    cider-repl-bol-mark
    cider-repl-set-ns)
  "CIDER REPL commands that select or modify the current line.")
(emacsvox-cider--register-after-group
 emacsvox-cider--line-selection-targets
 #'emacsvox-cider--line-selection-feedback)

(defun emacsvox-cider--switch-feedback ()
  "Speak after switching to another CIDER REPL."
  (emacsvox-speak-mode-line)
  (emacsvox-icon 'select-object))
(emacsvox-cider--register-after-group
 '(cider-repl-switch-to-other) #'emacsvox-cider--switch-feedback)

(defun emacsvox-cider--pretty-printing-feedback ()
  "Report the current CIDER REPL pretty-printing state."
  (emacsvox-icon (if cider-repl-use-pretty-printing 'on 'off))
  (message "Turned %s pretty printing."
           (if cider-repl-use-pretty-printing 'on 'off)))
(emacsvox-cider--register-after-group
 '(cider-repl-toggle-pretty-printing)
 #'emacsvox-cider--pretty-printing-feedback)

(defun emacsvox-cider--line-feedback ()
  "Speak the current line."
  (emacsvox-speak-line))
(emacsvox-cider--register-after-group
 '(cider-find-var cider-find-resource cider-find-ns)
 #'emacsvox-cider--line-feedback)

(defun emacsvox-cider--close-view-feedback ()
  "Speak after closing a CIDER popup."
  (with-current-buffer (window-buffer (selected-window))
    (emacsvox-icon 'close-object)
    (emacsvox-speak-mode-line)))
(emacsvox-cider--register-after-group
 '(cider-popup-buffer-quit-function cider-popup-buffer-quit)
 #'emacsvox-cider--close-view-feedback)

(defun emacsvox-cider--close-session-feedback ()
  "Confirm that a CIDER REPL session closed."
  (emacsvox-icon 'close-object)
  (message "Closed REPL session"))
(emacsvox-cider--register-after-group
 '(cider-quit) #'emacsvox-cider--close-session-feedback)

(defun emacsvox-cider--close-ancillary-feedback ()
  "Confirm that CIDER ancillary buffers closed."
  (emacsvox-icon 'close-object)
  (message "Closed ancillary buffers"))
(emacsvox-cider--register-after-group
 '(cider-close-ancillary-buffers)
 #'emacsvox-cider--close-ancillary-feedback)

(defun emacsvox-cider--describe-feedback ()
  "Confirm display of CIDER connection information."
  (emacsvox-icon 'open-object)
  (message "Displayed in other window."))
(emacsvox-cider--register-after-group
 '(cider-describe-nrepl-session cider-describe-connection)
 #'emacsvox-cider--describe-feedback)

(defun emacsvox-cider--debug-feedback ()
  "Speak the current CIDER debugger line."
  (emacsvox-speak-line)
  (emacsvox-icon 'button))
(emacsvox-cider--register-after-group
 '(cider-debug-defun cider-debug-move-here cider-debug-toggle-locals)
 #'emacsvox-cider--debug-feedback)

(defun emacsvox-cider--insert-feedback ()
  "Speak text inserted into the CIDER REPL."
  (emacsvox-speak-line)
  (emacsvox-icon 'yank-object))
(emacsvox-cider--register-after-group
 '(cider-insert-defun-in-repl
   cider-insert-form-in-repl
   cider-insert-ns-form-in-repl
   cider-insert-region-in-repl)
 #'emacsvox-cider--insert-feedback)

(defun emacsvox-cider--inspect-feedback ()
  "Speak after opening or refreshing the CIDER inspector."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-mode-line))
(emacsvox-cider--register-after-group
 '(cider-inspector-refresh
   cider-inspect
   cider-inspect-defun
   cider-inspect-expr
   cider-inspect-last-result
   cider-inspect-form
   cider-inspector-pop)
 #'emacsvox-cider--inspect-feedback)

(defun emacsvox-cider--inspect-navigation-feedback ()
  "Speak after navigating the CIDER inspector or stacktrace."
  (emacsvox-icon 'select-object)
  (emacsvox-speak-line))
(emacsvox-cider--register-after-group
 '(cider-inspector-next-inspectable-object
   cider-inspector-next-page
   cider-inspector-operate-on-click
   cider-inspector-operate-on-point
   cider-inspector-prev-page
   cider-inspector-previous-inspectable-object
   cider-stacktrace-cycle-current-cause
   cider-stacktrace-cycle-all-causes
   cider-stacktrace-cycle-cause-1
   cider-stacktrace-cycle-cause-2
   cider-stacktrace-cycle-cause-3
   cider-stacktrace-cycle-cause-4
   cider-stacktrace-cycle-cause-5
   cider-stacktrace-next-cause
   cider-stacktrace-previous-cause
   cider-stacktrace-jump)
 #'emacsvox-cider--inspect-navigation-feedback)

(defun emacsvox-cider--install-advice ()
  "Install advice for functions present in current CIDER."
  (dolist (entry emacsvox-cider--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(dolist (feature
         '(cider cider-apropos cider-browse-ns cider-classpath cider-connection
           cider-debug cider-doc cider-eval cider-format cider-inspector
           cider-mode cider-popup cider-repl cider-scratch cider-selector
           cider-stacktrace))
  (eval-after-load feature #'emacsvox-cider--install-advice))

(provide 'emacsvox-cider)
;;;  end of file
