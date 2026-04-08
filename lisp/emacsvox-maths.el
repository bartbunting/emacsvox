;;; emacsvox-maths.el --- Audio-Formatted Maths  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv, zorkov  $
;; Description:  Speak MathML and LaTeX math expressions
;; Keywords: Emacsvox,  Audio Desktop maths
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacsvox
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
;; MERCHANTABILITY or FITNMATHS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; @subsection Setup 
;; Do not try what follows until you have read  js/node/README.org
;; and successfully set up nvm (Node Version Manager) as described there.
;; @subsection Technical Overview 
;; Spoken mathematics on the emacsvox audio desktop. Use a NodeJS
;; based speech-rule-engine for Mathematics as the backend for
;; processing mathematical markup. The result of this processing is
;; an annotated S-expression that is rendered via Emacsvox's speech
;; facilities. Annotations follow Aural CSS as implemented in
;; Emacsvox, This allows us to map these expressions to aural
;; properties supported by specific TTS engines. 
;; 
;; Start  the server/client: M-x emacsvox-maths-start. Once the server
;; and client are started, you can browse any number of math
;; expressions using the emacsvox-maths-navigator defined in module
;; @xref{emacsvox-maths} as described below.
;; 
;; Note: In general, once everything is configured correctly, using
;; the maths navigator automatically starts the server and
;; client. Invoke the Navigator using @kbd{s-spc} --- this is the <windows>
;; key on Linux laptops.
;; Linux. Now you can use these keys:
;; @itemize
;; @item  Show Output <o> Switch to output buffer and quit Maths Navigator
;; @item Enter: <SPC>
;; Enter a LaTeX expression.
;; @item Smart-Enter: <enter> Enter the guessed expression with no prompting.
;; @item Alt-Text <a> Process alt-text
;; under point as LaTeX.
;; @item Down <down> Move down a level.
;; @item
;; Up <up> Move up a level.
;; @item Left <left> Move left.
;; @item Right
;; <right> Move right.
;; @item Exit <any other key> Exit
;; navigator.
;; 
;; 
;; @end itemize
;; The current expression is spoken after
;; each of the above commands. It is also displayed in a special
;; buffer *Spoken Math*. That buffer holds all previously generated
;; output, And Emacs commands forward-page and backward-page can be
;; used to move through each chunk of output.

;;; Code:

;;   Required modules:
(require 'emacsvox-preamble)
(eval-when-compile (require 'cl-lib))
(require 'comint)
(eval-when-compile (require 'derived))
(require 'nvm "nvm" 'no-error)

;;;  Customizations And Variables:
(defconst emacsvox-maths-node (executable-find "node") "Node
executable")

(defvar emacsvox-maths-inferior-program
  (cond
   ((and (locate-library "nvm")
         (nvm--installed-versions))
    (let ((v (car (sort (mapcar #'car (nvm--installed-versions)) #'string>))))
      (nvm-use v)
      emacsvox-maths-node))
   ;; The fallback below  --- /usr/bin/node e.g. on Ubuntu/Debian  is old.
   (emacsvox-maths-node emacsvox-maths-node) 
   (t  nil))
  "Location of `node' executable.  Make sure the environment in which
Emacs is launched finds the right installation of node.  M-x
package-install nvm makes it easier to have Emacs find the right node
install.")

(cl-defstruct emacsvox-maths
  server-buffer ; comint buffer
  server-process ; node process handle
  client-buffer ; network socket stream
  client-process ; network connection
  input  ; LaTeX we send
  output ; where output is displayed
  pause ; pending pause to add
  result
  )

(defvar emacsvox-maths nil
  "Structure holding all runtime context.")

;;;  Parser Setup:

(defvar emacsvox-maths-handler-table (make-hash-table :test #'eq)
  "Map of handlers for parsing Maths Server output.")
(defun emacsvox-maths-handler-set (name handler)
  "Set up handler for name `name'."
  
  (puthash name handler emacsvox-maths-handler-table))

(defun emacsvox-maths-handler-get (name)
  "Return handler  for name `name'.
Throw error if no handler defined."
  
  (or (gethash name emacsvox-maths-handler-table)
      (error "No handler defined for %s" name)))

;;;  Handlers:

;; All handlers are called with the body of the unit being parsed.
;; Handlers process input and render to output buffer
;; Except for the pause handler that merely records the pause,
;; Leaving it to the next text handler to consume that pause.

;; Helper: Handle plain strings

(defun emacsvox-maths-handle-string (string)
  "Handle plain, unannotated string."
  
  (with-current-buffer (emacsvox-maths-output emacsvox-maths)
    (let ((start (point)))
      (insert (format "%s\n" string))
      (emacsvox-maths-apply-pause start))))

(defun emacsvox-maths-parse (sexp)
  "Top-level parser dispatch.
If sexp is a string, return it.
Otherwise, Examine head of sexp, and applies associated handler to the tail."
  (cond
   ((stringp sexp)
    (emacsvox-maths-handle-string sexp))
   (t
    (cl-assert  (listp sexp) t "%s is not a list." sexp)
    (let ((handler (emacsvox-maths-handler-get(car sexp))))
      (cl-assert (fboundp handler) t "%s is not  a function.")
      (funcall handler (cdr sexp))))))

(defun emacsvox-maths-handle-exp (contents)
  "Handle top-level exp returned from Maths Server."
  
  (with-current-buffer (emacsvox-maths-output emacsvox-maths)
    (goto-char (point-max))
    (let ((inhibit-read-only  t)
          (start (point))
          (end nil))
      (mapc #'emacsvox-maths-parse contents)
      (setq end (point))
      (insert "\f")
      (goto-char start)
      (display-buffer (emacsvox-maths-output emacsvox-maths))
      (tts-with-punctuations 'some
                             (emacsvox-speak-region start end)))))

(defun emacsvox-maths-acss (acss-alist)
  "Return ACSS voice corresponding to acss-alist."
  (let-alist acss-alist
    (voice-from-acss
     (make-acss
      :average-pitch  .average-pitch
      :pitch-range .pitch-range
      :stress .stress
      :richness .richness))))

;; Helper: Apply pause and consume:

(defun emacsvox-maths-apply-pause (start)
  "Apply pause."
  
  (let ((pause (emacsvox-maths-pause emacsvox-maths)))
    (when pause
      (save-excursion
        (goto-char start)
        (skip-syntax-forward " ")
        (put-text-property
         (point) (1+ (point))
         'pause pause))
      (setf (emacsvox-maths-pause emacsvox-maths) nil))))

(defun emacsvox-maths-handle-text (contents)
  "Handle body of annotated text from Maths Server.
Expected: ((acss) string)."
  
  (cl-assert (listp contents) t "%s is not a list. " contents)
  (let ((acss (cl-first contents))
        (string (cl-second contents))
        (start nil))
    (with-current-buffer  (emacsvox-maths-output emacsvox-maths)
      (setq start (goto-char (point-max)))
      (insert (format "%s\n" string))
      (put-text-property
       start (point)
       'personality (emacsvox-maths-acss acss))
      (emacsvox-maths-apply-pause start))))

(defun emacsvox-maths-handle-pause (ms)
  "Handle Pause value."
  
  (cl-assert (numberp ms) t "%s is not a number. " ms)
  (cond
   ((null (emacsvox-maths-pause emacsvox-maths))
    (setf (emacsvox-maths-pause emacsvox-maths) ms))
   ((numberp (emacsvox-maths-pause emacsvox-maths))
    (cl-incf (emacsvox-maths-pause emacsvox-maths) ms))
   (t (error "Invalid pause %s set earlier."
             (emacsvox-maths-pause emacsvox-maths)))))

(defun emacsvox-maths-handle-error (contents)
  "Display error message."
  (let ((msg (car contents)))
    (dtk-notify
     (cond
      ((string= "38" msg) "Top of tree")
      ((string= "39" msg) "Last Node at this level")
      ((string= "40" msg) "Bottom of tree")
      ((string= "37" msg) "First node at this level")
      (t msg)))))

(defun emacsvox-maths-handle-parse-error (contents)
  "Display parse-error message."
  (message "%s" contents))

(defun emacsvox-maths-handle-welcome (contents)
  "Handle welcome message."
  (message "%s" contents))

;;;  Map Handlers:

(cl-loop
 for f in
 '(exp pause text error welcome parse-error)
 do
 (emacsvox-maths-handler-set
  f
  (intern (format "emacsvox-maths-handle-%s"  (symbol-name f)))))

;;;  Process Filter:

(defun emacsvox-maths-read-output ()
  "Parse and return one complete chunk of output. Throws an error on an
incomplete parse, that is expected to be caught by the caller."
   ;;; return first sexp and move point
  (emacsvox-maths-parse (read (current-buffer))))

(defun emacsvox-maths-process-filter (proc string)
  "Handle process output from Node math-server.
All complete chunks of output are consumed. Partial output is
left for next run."
  
  (with-current-buffer (process-buffer proc)
    (let ((moving (= (point) (process-mark proc))))
      (save-excursion
        ;; Insert the text, advancing the process marker.
        (goto-char (process-mark proc))
        (insert string)
        (set-marker (process-mark proc) (point)))
      ;; Consume process output
      (save-excursion
        (goto-char (point-min))
        (flush-lines "^ *$")
        (goto-char (point-min))
        (skip-syntax-forward " >")
        (let((result nil)
             (start (point)))
          (condition-case nil
              (while (not (eobp))
                ;; Parse one complete chunk
                (setq result (emacsvox-maths-read-output))
                ;; Todo: perhaps accumulate instead of just using recent
                (setf (emacsvox-maths-result emacsvox-maths) result)
                (skip-syntax-forward " >")
                (delete-region start (point))
                (setq start (point)))
            (error nil))))
      (if moving (goto-char (process-mark proc))))))

;;;  Setup:

(defvar emacsvox-maths-server-program
  (expand-file-name "../js/node/math-server.js" emacsvox-lisp-directory)
  "NodeJS implementation of math-server.")
;;;###autoload
(defun emacsvox-maths-start ()
  "Start Maths server bridge."
  (interactive)
  (cl-declare (special emacsvox-maths-inferior-program
                       emacsvox-maths emacsvox-maths-server-program))
  (cl-assert emacsvox-maths-inferior-program nil "No node executable found.")
  (let ((server
         (make-comint
          "Server-Maths" emacsvox-maths-inferior-program nil
          emacsvox-maths-server-program))
        (client nil))
    (accept-process-output (get-buffer-process server) 1.0 nil 'just-this-one)
    (setq client
          (open-network-stream "Client-Math" "*Client-Math*" "localhost" 5000))
    (setf emacsvox-maths
          (make-emacsvox-maths
           :output (emacsvox-maths-setup-output)
           :server-buffer  server
           :server-process (get-buffer-process server)
           :client-process client
           :client-buffer (process-buffer client)))
    (set-process-filter client #'emacsvox-maths-process-filter))
  (when (called-interactively-p 'interactive)
    (message "Started Maths server and client.")))

(defun emacsvox-maths-shutdown ()
  "Shutdown client and server processes."
  (interactive)
  
  (when (process-live-p (emacsvox-maths-client-process emacsvox-maths))
    (delete-process (emacsvox-maths-client-process emacsvox-maths)))
  (when (process-live-p (emacsvox-maths-server-process emacsvox-maths))
    (delete-process (emacsvox-maths-server-process emacsvox-maths)))
  (when (buffer-live-p (emacsvox-maths-server-buffer emacsvox-maths))
    (kill-buffer (emacsvox-maths-server-buffer emacsvox-maths)))
  (when (buffer-live-p (emacsvox-maths-client-buffer emacsvox-maths))
    (kill-buffer (emacsvox-maths-client-buffer emacsvox-maths)))
  (when (called-interactively-p 'interactive)
    (message "Shutdown Maths server and client.")))

(defun emacsvox-maths-flush-output ()
  "Flush client buffer if things go out of sync."
  (interactive)
  
  (when
      (process-live-p (emacsvox-maths-client-process emacsvox-maths))
    (with-current-buffer
        (process-buffer (emacsvox-maths-client-process emacsvox-maths))
      (erase-buffer)))
  (when (called-interactively-p 'interactive)
    (message "Flushed client buffer.")))

(defun emacsvox-maths-ensure-server ()
  "Start up Maths Server bridge if not already running."
  
  (unless
      (and emacsvox-maths
           (process-live-p (emacsvox-maths-server-process emacsvox-maths))
           (process-live-p (emacsvox-maths-client-process emacsvox-maths)))
    (emacsvox-maths-start)))

(defun emacsvox-maths-restart ()
  "Restart Node math-server if running. Otherwise starts a new one."
  (interactive)
  (emacsvox-maths-shutdown)
  (emacsvox-maths-start)
  (message "Restarting Maths server and client."))

;;;  Navigators:

(declare-function calc-kill "calc-yank" (flag no-delete))
;; Guess expression from Calc:
(defun emacsvox-maths-guess-calc ()
  "Guess expression to speak in calc buffers.
Set calc-language to tex to use this feature."
  
  (cl-assert (eq major-mode 'calc-mode) nil "This is not a Calc buffer.")
  (calc-kill 1 'no-delete)
  (substring (car calc-last-kill) 2))

;; Guess expression from sage

(declare-function emacsvox-sage-get-output-as-latex "emacsvox-sage" nil)

(defun emacsvox-maths-guess-sage ()
  "Guess expression to speak in sage-mode buffers."
  (cl-assert
   (eq major-mode 'sage-shell:sage-mode) nil "This is not a Sage buffer.")
  (sit-for 0.1)
  (emacsvox-sage-get-output-as-latex))

;; Helper: Guess current math expression from TeX/LaTeX

(defun emacsvox-maths-guess-tex ()
  "Extract math content around point."
  
  (cl-assert (require 'texmathp) nil "Install package auctex to get texmathp")
  (when (texmathp)
    (let ((delimiter (car texmathp-why))
          (start (cdr texmathp-why))
          (begin nil)
          (end nil))
      (cond
       ;; $ and $$
       ((or (string= "$" delimiter)
            (string= "$$" delimiter))
        (save-excursion
          (goto-char start)
          (forward-char (length delimiter))
          (setq begin (point))
          (skip-syntax-forward "^$")
          (setq end (point))
          (buffer-substring begin end)))
       ;; \( and \[
       ((string= "\\(" delimiter)
        (goto-char start)
        (setq begin (+ start  2))
        (search-forward "\\)")
        (setq end (- (point) 2))
        (buffer-substring begin end))
       ((string= "\\[" delimiter)
        (goto-char start)
        (setq begin (+ start  2))
        (search-forward "\\]")
        (setq end (- (point) 2))
        (buffer-substring begin end))
       ;; begin equation
       ((string= "equation" delimiter)
        (goto-char start)
        (forward-char (length "\\begin{equation}"))
        (setq begin (point))
        (search-forward "\\end{equation}")
        (backward-char (length "\\begin{equation}"))
        (setq end (point))
        (buffer-substring begin end))

       (t nil)))))

(defun emacsvox-maths-guess-input ()
  "Examine current mode, text around point etc. to guess Math content to read."
  
  (unless emacsvox-maths (emacsvox-maths-start))
  (setf
   (emacsvox-maths-input emacsvox-maths)
   (cond
    ((eq major-mode 'calc-mode)
     (emacsvox-maths-guess-calc))
    ((eq major-mode 'sage-shell:sage-mode)
     (emacsvox-maths-guess-sage))
    ((and (memq major-mode '(tex-mode plain-tex-mode latex-mode ams-tex-mode))
          (featurep 'texmathp))
     (emacsvox-maths-guess-tex))
    ((and
      (eq major-mode 'eww-mode)
      (not
       (string-equal
        (get-text-property (point) 'shr-alt)
        "No image under point")))
     (get-text-property (point) 'shr-alt))
    (t
     (read-from-minibuffer
      "Maths: " nil nil nil nil
      (when mark-active (buffer-substring (region-beginning)(region-end))))))))

;;;###autoload
(defun emacsvox-maths-enter-guess ()
  "Send the guessed  LaTeX expression to Maths server. "
  (interactive)
  
  (emacsvox-maths-ensure-server)        
  (emacsvox-maths-guess-input)         ;guess based on context
  (process-send-string
   (emacsvox-maths-client-process emacsvox-maths)
   (format "enter: %s" (emacsvox-maths-input emacsvox-maths))))

;;;###autoload
(defun emacsvox-maths-enter (latex)
  "Send a LaTeX expression to Maths server,
 guess  based on context. "
  (interactive (list (emacsvox-maths-guess-input)))
  
  (emacsvox-maths-ensure-server)
  (when (or (null latex) (string= "" latex))
    (setq latex (read-from-minibuffer "Enter expression:")))
  (setf (emacsvox-maths-input emacsvox-maths) latex)
  (process-send-string
   (emacsvox-maths-client-process emacsvox-maths)
   (format "enter: %s"latex)))

(cl-loop
 for move in
 '("left" "right" "up" "down" "root" "depth")
 do
 (eval
  `(defun ,(intern (format "emacsvox-maths-%s" move)) ()
     ,(format "Move %s in current Math expression. (auto-generated)" move)
     (interactive)
     
     (process-send-string
      (emacsvox-maths-client-process emacsvox-maths)
      ,(format "%s:\n" move)))))

;;;  Output: spoken-math mode:

(define-derived-mode emacsvox-maths-spoken-mode special-mode
  "Spoken Math On The Complete Audio Desktop"
  "Special mode for interacting with Spoken Math.

This mode is used by the special buffer that displays spoken math
returned from the Node server.
This mode is similar to Emacs' `view-mode'.
see the key-binding list at the end of this description.
Emacs online help facility to look up help on these commands.

\\{emacsvox-maths-spoken-mode-map}"
  (goto-char (point-min))
  (setq header-line-format "Spoken Math")
  (modify-syntax-entry 10 ">"))
(cl-declaim (special emacsvox-maths-spoken-mode-map))
(cl-loop
 for b in
 '(
   ("[" backward-page)
   ("]" forward-page)
   ("j" emacsvox-maths-down)
   ("k" emacsvox-maths-up)
   ("h" emacsvox-maths-left)
   ("l" emacsvox-maths-right)
   )
 do
 (emacsvox-keymap-update emacsvox-maths-spoken-mode-map b))

(defun emacsvox-maths-setup-output ()
  "Set up output buffer for displaying spoken math."
  (with-current-buffer (get-buffer-create "*Spoken Math*")
    (let ((inhibit-read-only t))
      (erase-buffer))
    (emacsvox-maths-spoken-mode)
    (current-buffer)))
(defun emacsvox-maths-switch-to-output ()
  "Switch to output buffer."
  (interactive)
  
  (funcall-interactively
   #'pop-to-buffer (emacsvox-maths-output emacsvox-maths)))

;;;  Helpers:

(defun emacsvox-maths-speak-alt ()
  "Speak alt text as Maths.
For use on Wikipedia pages  for example."
  (interactive)
  (cl-assert (eq major-mode 'eww-mode) "Not in an EWW buffer.")
  (let ((alt-text (get-text-property (point) 'shr-alt)))
    (unless (string-equal alt-text "No image under point")
      (funcall-interactively #'emacsvox-maths-enter alt-text))))

;;;  Advice Preview:

(defun ems--preview-at-point-after (&rest _)
  "Also preview using speech."
  (when
      (and (ems-interactive-p) emacsvox-maths
           (process-live-p
            (emacsvox-maths-client-process emacsvox-maths)))
    (let
        ((preview-state
          (mapcar #'(lambda (o) (overlay-get o 'preview-state))
                  (overlays-at (point)))))
      (when (cl-some #'identity preview-state)
        (emacsvox-maths-enter (emacsvox-maths-guess-tex))))))

(advice-add 'preview-at-point :after #'ems--preview-at-point-after)

(provide 'emacsvox-maths)
;;;  end of file

