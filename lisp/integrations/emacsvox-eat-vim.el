;;; emacsvox-eat-vim.el --- Speak Vim's rendered EAT display -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: Emacsvox contributors
;; Maintainer: Emacsvox contributors
;; Keywords: accessibility, terminals
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

;; Interpret delivered keys against EAT's public, concealed-redacted screen.
;; The editor may run on another host or inside a terminal multiplexer.

;;; Code:

(require 'emacsvox-eat-presentation)
(eval-when-compile (require 'cl-lib))
(autoload 'emacsvox-speak--percentage-description "emacsvox-speak-status")

(defvar-local emacsvox-eat--vim-keys nil
  "Delivered keys awaiting visible evidence, oldest first.")
(defvar-local emacsvox-eat--vim-origin nil
  "Screen as it looked before the oldest pending key.")
(defvar-local emacsvox-eat--vim-deadline 0.0)
(defvar-local emacsvox-eat--vim-expiry nil)
(defvar-local emacsvox-eat--vim-quiet-timer nil)
(defvar-local emacsvox-eat--vim-normal-evidence nil
  "Whether an observed Normal action permits feedback for a silent replay.")
(defvar-local emacsvox-eat--vim-awaiting-match nil
  "Non-nil after a search announces its ruler while the match row is missing.")
(defvar-local emacsvox-eat--vim-quitting nil
  "Non-nil while a delivered quit awaits evidence of a return to the shell.")
(defvar-local emacsvox-eat--vim-anchor nil
  "File or screen coordinates at the observed start of a Visual selection.")
(defvar-local emacsvox-eat--vim-tabs nil
  "Last identified tab and its visible neighbours on a plain Vim tab line.")
(defvar-local emacsvox-eat--vim-last-boundary nil
  "Last confirmed file boundary and the screen where Vim reached it.")
(defconst emacsvox-eat--vim-input-limit 128)
(defconst emacsvox-eat--vim-input-timeout 3.0
  "Seconds to associate input with an SSH redraw, without polling.")

(declare-function eat-self-input "eat" (n &optional event))
(defvar emacsvox-eat-application-profile)

(defun emacsvox-eat--vim-escape ()
  "Send one Escape through EAT's normal input path."
  (interactive)
  (eat-self-input 1 27))

(defun emacsvox-eat--vim-install-input-keys ()
  "Route physical Escape and Control word arrows in Vim terminal input modes.
Keep existing explicit bindings and leave the ASCII Meta prefix available."
  (dolist (symbol '(eat-semi-char-mode-map eat-char-mode-map
                    eat-eshell-semi-char-mode-map eat-eshell-char-mode-map))
    (when-let* ((map (and (boundp symbol) (symbol-value symbol))))
      (dolist (binding '(([escape] . emacsvox-eat--vim-escape)
                         ([C-left] . eat-self-input) ([C-right] . eat-self-input)))
        (unless (lookup-key map (car binding))
          (define-key map (car binding)
                      (list 'menu-item "" (cdr binding) :filter
                            (lambda (command)
                              (when (eq emacsvox-eat-application-profile 'vim) command)))))))))

(defun emacsvox-eat--vim-forget-input ()
  "Discard keys and their original screen."
  (when (timerp emacsvox-eat--vim-expiry) (cancel-timer emacsvox-eat--vim-expiry))
  (when (timerp emacsvox-eat--vim-quiet-timer) (cancel-timer emacsvox-eat--vim-quiet-timer))
  (setq emacsvox-eat--vim-keys nil emacsvox-eat--vim-origin nil
        emacsvox-eat--vim-awaiting-match nil emacsvox-eat--vim-quitting nil
        emacsvox-eat--vim-expiry nil emacsvox-eat--vim-quiet-timer nil emacsvox-eat--vim-deadline 0.0))

(defun emacsvox-eat--vim-expire (buffer)
  "Release pending input in BUFFER even if the peer never redraws."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (let ((remaining (- emacsvox-eat--vim-deadline (float-time))))
        (if (<= remaining 0) (emacsvox-eat--vim-forget-input)
          (setq emacsvox-eat--vim-expiry
                (run-at-time remaining nil #'emacsvox-eat--vim-expire buffer)))))))

(defun emacsvox-eat--vim-reset ()
  "Forget all keyboard and selection evidence for this terminal."
  (emacsvox-eat--vim-forget-input)
  (setq emacsvox-eat--vim-anchor nil emacsvox-eat--vim-normal-evidence nil
        emacsvox-eat--vim-tabs nil emacsvox-eat--vim-last-boundary nil))

(defun emacsvox-eat--vim-word-arrows-p (keys)
  "Whether KEYS contains only Control word arrows."
  (and keys (cl-every (lambda (key) (memq key '(C-left C-right))) keys)))

(defun emacsvox-eat--vim-record-key (event count screen)
  "Remember COUNT copies of EVENT delivered at SCREEN."
  (unless (memq event '(?g ?G)) (setq emacsvox-eat--vim-last-boundary nil))
  (when (or emacsvox-eat--vim-awaiting-match emacsvox-eat--vim-quitting
            (eq emacsvox-eat--vim-quiet-timer 'announced)
            (> (float-time) emacsvox-eat--vim-deadline)
            ;; An earlier word may already be on screen awaiting speech.
            ;; Start the new key at the latest rendered cursor.
            (and (emacsvox-eat--vim-word-arrows-p emacsvox-eat--vim-keys)
                 (or (not (memq event '(C-left C-right)))
                     (and (not (eq screen emacsvox-eat--vim-origin))
                          (not (equal (emacsvox-eat--vim-point screen)
                                      (emacsvox-eat--vim-point emacsvox-eat--vim-origin)))))))
    (emacsvox-eat--vim-forget-input))
  (let ((count (or count 1))
        (key (pcase event
               ((or 13 10 'linefeed) 'return)
               (27 'escape)
               (127 'backspace)
               (_ event))))
    (cond
     ((or (null screen) (<= count 0) (null event)
          (> (+ count (length emacsvox-eat--vim-keys)) emacsvox-eat--vim-input-limit))
      (emacsvox-eat--vim-forget-input))
     (t
      (unless emacsvox-eat--vim-keys
        (setq emacsvox-eat--vim-origin screen
              emacsvox-eat--vim-expiry (run-at-time emacsvox-eat--vim-input-timeout nil
                                                    #'emacsvox-eat--vim-expire (current-buffer))))
      (setq emacsvox-eat--vim-keys (nconc emacsvox-eat--vim-keys (make-list count key))
            emacsvox-eat--vim-deadline (+ (float-time) emacsvox-eat--vim-input-timeout))
      (when (and emacsvox-eat--vim-normal-evidence
                 (memq key '(?i ?I ?a ?A ?o ?O ?c ?C ?s ?S ?R))
                 (eq key (car (emacsvox-eat--vim-command-tail emacsvox-eat--vim-keys))))
        ;; The peer can enter Insert even if it hides the mode label.
        (setq emacsvox-eat--vim-normal-evidence nil))
      (when (memq key '(return ?Z ?Q))
        (setq emacsvox-eat--vim-quitting
              (emacsvox-eat--vim-quit-command-p emacsvox-eat--vim-origin emacsvox-eat--vim-keys)))))))

(defconst emacsvox-eat--vim-ruler
  "\\([0-9]+\\),\\([0-9]+\\)\\(?:-\\([0-9]+\\)\\)?[ \t]+\\(?:Top\\|Bot\\|All\\|[0-9]+%\\)[ \t]*\\'")
(defconst emacsvox-eat--vim-modes
  '(("INSERT" . "Insert") ("REPLACE" . "Replace") ("VREPLACE" . "Virtual Replace")
    ("VISUAL" . "Visual") ("VISUAL LINE" . "Visual line") ("VISUAL BLOCK" . "Visual block")
    ("SELECT" . "Select") ("SELECT LINE" . "Select line") ("SELECT BLOCK" . "Select block")))

(defun emacsvox-eat--vim-status-index (screen)
  "Locate Vim's command row, accounting for an outer tmux status bar."
  (let* ((rows (plist-get screen :rows)) (bottom (1- (length rows)))
         (line (nth bottom rows)) (previous (and (> bottom 0) (nth (1- bottom) rows))))
    (cond
     ((< bottom (1- (cdr (plist-get screen :size)))) (1- (cdr (plist-get screen :size))))
     ((and previous
             (or (string-match-p "\\`\\[[^]\n]+\\] +[0-9]+:" line)
                 (and (string-match-p emacsvox-eat--vim-ruler previous)
                      (not (string-match-p emacsvox-eat--vim-ruler line))
                      (let ((offset (- (length (plist-get screen :text)) (length line))))
                        (cl-some (lambda (run)
                                   (and (<= (car run) offset) (>= (cadr run) (+ offset (length line)))
                                        (emacsvox-eat--highlight-signature (caddr run))))
                                 (plist-get screen :styles))))))
      (1- bottom))
     (t bottom))))

(defun emacsvox-eat--vim-buffer-list (rows end)
  "Read the visible Vim buffer list immediately above the prompt at END in ROWS."
  (let ((above (reverse (seq-take rows end))) entries)
    (while (and above
                (string-match
                 (rx string-start (* blank) (group (+ digit)) (+ blank)
                     (group (* (any ?- "u%#ah=+xRF? "))) "\"" (group (* nonl)) "\""
                     (+ blank) "line" (+ blank) (group (+ digit)) (* blank) string-end)
                 (car above)))
      (let* ((line (pop above)) (number (match-string 1 line)) (flags (match-string 2 line))
             (name (match-string 3 line)) (position (match-string 4 line)))
        (push (concat "Buffer " number ", " name
                      (when (string-search "%" flags) ", current")
                      (when (string-search "#" flags) ", alternate")
                      (when (string-search "+" flags) ", modified")
                      (unless (equal position "0") (concat ", line " position)))
              entries)))
    (when (and entries
               (or (null above)
                   (string-match-p (rx string-start ":" (or "ls" "buffers" "files")
                                       (or string-end "!" blank)) (string-trim (car above)))))
      (string-replace "\n" ". " (emacsvox-eat--bounded-output entries)))))

(defun emacsvox-eat--vim-table-result (rows end)
  "Read visible marks or registers under their table heading before END in ROWS."
  (let* ((above (seq-take rows end))
         (marks (rx string-start (* blank) "mark" (+ blank) "line" (+ blank) "col" (+ blank) "file/text" (* blank) string-end))
         (regs (rx string-start (* blank) "Type" (+ blank) "Name" (+ blank) "Content" (* blank) string-end))
         (heading (cl-position-if (lambda (s) (or (string-match-p marks s) (string-match-p regs s)))
                                  above :from-end t)))
    (when heading
      (let ((mark-table (string-match-p marks (nth heading above))) entries)
        (dolist (s (nthcdr (1+ heading) above))
          (cond
           ((and mark-table
                 (string-match (rx string-start (* blank) (group (not blank)) (+ blank) (group (+ digit))
                                   (+ blank) (group (+ digit)) (+ blank) (group (* nonl))) s))
            (push (format "Mark %s, line %s, column %s, %s" (match-string 1 s) (match-string 2 s)
                          (match-string 3 s) (string-trim-right (match-string 4 s))) entries))
           ((and (not mark-table)
                 (string-match (rx string-start (* blank) (any "clb") (+ blank) "\"" (group (not blank))
                                   (+ blank) (group (* nonl))) s))
            (push (format "Register %s, %s" (match-string 1 s) (string-trim-right (match-string 2 s))) entries))))
        (when entries (string-replace "\n" ". " (emacsvox-eat--bounded-output (nreverse entries))))))))

(defun emacsvox-eat--vim-confirmation (screen row ruler question)
  "Describe QUESTION and its visible substitution match above ROW on SCREEN."
  (let* ((hits (cl-remove-if-not
                (lambda (region)
                  (and (< (plist-get region :row-start) row)
                       (or (not ruler) (= (plist-get region :column-start) (1- (cdr ruler))))))
                (emacsvox-eat--highlight-regions screen)))
         (hit (and (length= hits 1) (car hits)))
         (point (when hit
                  (let ((view (copy-sequence screen)))
                    (setq view (plist-put view :cursor-row (plist-get hit :row-start))
                          view (plist-put view :cursor-column (plist-get hit :column-start)))
                    (emacsvox-eat--vim-point view)))))
    (string-join
     (delq nil (list (when ruler (format "Line %d, column %d" (car ruler) (cdr ruler)))
                     (when point (emacsvox-eat--vim-row-text (plist-get point :line)))
                     question))
     ". ")))

(defun emacsvox-eat--vim-swap-prompt (rows row)
  "Read the available choices in a Vim swap question ending on ROW of ROWS."
  (let ((text (mapconcat #'identity (seq-subseq rows (max 0 (- row 6)) (1+ row)) "")))
    (when (string-match (rx (* nonl) (group (any "[(") "O" (any "])") "pen Read-Only, " (* nonl)
                                            (any "[(") "A" (any "])") "bort:") (* blank) string-end) text)
      (let ((choices (match-string 1 text)))
        (concat "Swap file already exists. "
                (string-join
                 (cl-loop for (key . label) in '(("O" . "O open read-only") ("E" . "E edit anyway")
                                                 ("R" . "R recover") ("D" . "D delete it")
                                                 ("Q" . "Q quit") ("A" . "A abort"))
                          when (or (string-search (concat "(" key ")") choices)
                                   (string-search (concat "[" key "]") choices))
                          collect label) ", "))))))

(defun emacsvox-eat--vim-blocking-prompt (screen)
  "Read a Vim startup or continuation prompt at the cursor on SCREEN.
After the profile menu resizes EAT, the prompt can sit above the last row."
  (let* ((rows (plist-get screen :rows)) (row (plist-get screen :cursor-row))
         (line (and row (nth row rows)))
         (end (and line (string-trim-right line))))
    (when (and end (>= (plist-get screen :cursor-column) (string-width end)))
      (cond
       ((string-match-p (rx string-start (or "Press ENTER" "-- More --")) end) end)
       ((string-suffix-p ":" end) (emacsvox-eat--vim-swap-prompt rows row))))))

(defun emacsvox-eat--vim-status (screen)
  "Return visible mode, prompt, command result and ruler facts on SCREEN."
  (let* ((rows (plist-get screen :rows))
         (row (emacsvox-eat--vim-status-index screen))
         (line (or (nth row rows) ""))
         (case-fold-search nil)
         (ruler (when (string-match emacsvox-eat--vim-ruler line)
                  (prog1 (cons (string-to-number (match-string 1 line))
                               (string-to-number (or (match-string 3 line) (match-string 2 line))))
                    (setq line (substring line 0 (match-beginning 0))))))
         (text (string-trim-right line))
         (blocking (emacsvox-eat--vim-blocking-prompt screen))
         (at-command (= (or (plist-get screen :cursor-row) -1) row))
         (completion (when (string-match (rx string-start "-- "
                                             (or "Keyword completion (^N^P)" "File name completion (^F^N^P)")
                                             (+ blank) (group (+ nonl))) text)
                       (match-string 1 text)))
         (mode (cond (completion "Insert")
                     ((string-match "\\`-- \\([A-Z ]+\\) --" text)
                      (cdr (assoc (match-string 1 text) emacsvox-eat--vim-modes)))))
         (prompt (and at-command (string-match-p "\\`[:/?]" text) (aref text 0)))
         (previous (when-let* ((line (and (> row 0) (nth (1- row) rows)))) (string-trim line)))
         (confirmation
          (when (and at-command (string-match (rx string-start "replace with " (group (* nonl))
                                                   " (y/n/a/q/l/" (* nonl) ")?") text))
            (let ((replacement (match-string 1 text)))
              (emacsvox-eat--vim-confirmation
               screen row ruler
               (concat (if (string-empty-p replacement) "Replace with empty text"
                         (concat "Replace with " replacement))
                       "? y yes, n no, a all, q quit, l last, Control E or Y to scroll")))))
         (message
          (cond
           (confirmation confirmation)
           ((string-match-p (rx string-start (+ digit) blank
                                (or "match" "matches" "substitution" "substitutions")
                                " on " (+ digit) " line" (optional "s") string-end) text) text)
           ((string-match-p "\\`\\(?:Press ENTER\\|-- More --\\)" text)
            (if-let* ((result (or (and previous (string-match-p "\\`[EW][0-9]+:" previous) previous)
                                  (emacsvox-eat--vim-buffer-list rows row)
                                  (emacsvox-eat--vim-table-result rows row))))
                (concat result ". " text) text))
           ((string-match-p "\\`\\(?:[EW][0-9]+:\\|search hit \\|Pattern not found\\)" text) text)
           (blocking)
           ((and (string-prefix-p "\"" text)
                 (string-match-p "\\b\\(?:written\\|appended\\)\\'" text)) text))))
    (list :mode mode :completion completion :prompt prompt :message message :ruler ruler :text text
          :blocking blocking
          :recording (when (string-match (rx (or string-start blank) "recording @" (group alnum)
                                             (* blank) string-end) text) (match-string 1 text))
          :file-completion (and completion (string-prefix-p "-- File name completion" text))
          :pager (string-match-p (rx string-start (or "Press ENTER" "-- More --")) text)
          :confirmation confirmation
          :command (and (string-prefix-p ":" text) text)
          :pending-yank (string-match-p "\\(?:\\`\\|[ \t]\\)y\\'" text)
          :search (when (string-match "\\`[/?]\\(.+\\)" text) (match-string 1 text)))))

(defun emacsvox-eat--vim-entry-prompt (screen)
  "Read a pending question on SCREEN when selecting the Vim profile."
  (when screen
    (let ((state (emacsvox-eat--vim-status screen)))
      (when (or (plist-get state :blocking) (plist-get state :pager) (plist-get state :confirmation))
        (plist-get state :message)))))

(defun emacsvox-eat--vim-quit-command-p (origin keys)
  "Whether KEYS submit a Vim quit from the command or editing screen at ORIGIN."
  (let* ((state (emacsvox-eat--vim-status origin)) (prompt (plist-get state :prompt))
         (input (butlast keys)))
    (and (not (plist-get state :mode))
         (or (and (not prompt) (member keys '((?Z ?Z) (?Z ?Q))))
             (and (eq (car (last keys)) 'return) (cl-every #'characterp input)
                  (or (eq prompt ?:) (and (not prompt) (eq (car input) ?:)))
                  (string-match-p
                   (rx string-start ":" (* blank)
                       (or "q" "qu" "qui" "quit" "qa" "qall" "quitall" "wq" "wqa" "wqall"
                           "x" "xit" "exit" "xa" "xall")
                       (optional "!") (* blank) string-end)
                   (concat (when prompt (plist-get state :command)) (apply #'string input))))))))

(defun emacsvox-eat--vim-shell-return-p (screen integrated-prompt)
  "Confirm a pending quit using SCREEN or a newly reported INTEGRATED-PROMPT."
  (when (and emacsvox-eat--vim-quitting (<= (float-time) emacsvox-eat--vim-deadline))
    (or integrated-prompt
        (let* ((state (emacsvox-eat--vim-status screen))
               (rows (plist-get screen :rows)) (row (plist-get screen :cursor-row))
               (line (and row (nth row rows)))
               (previous (and row (> row 0) (nth (1- row) rows)))
               (command-row (emacsvox-eat--vim-status-index screen)))
          (and line (not (or (plist-get state :mode) (plist-get state :ruler)
                             (plist-get state :command) (plist-get state :message)))
               (string-match-p (rx (any "$#%>❯") (* blank) string-end) line)
               (>= (plist-get screen :cursor-column) (string-width (string-trim-right line)))
               (or (= row command-row)
                   ;; A restored tmux pane can put the prompt anywhere on screen.
                   (and previous (string-prefix-p line previous)
                        (string-match-p (rx word-start (or "vi" "vim" "nvim") word-end)
                                        (substring previous (length line))))
                   (and (< command-row (1- (length rows)))
                        (string-match-p
                         (rx (+ digit) ":" (or "sh" "bash" "dash" "zsh" "ksh" "fish") "*")
                         (car (last rows))))))))))

(defun emacsvox-eat--vim-divider-p (screen starts row column)
  "Whether ROW has an individually styled window divider at display COLUMN."
  (when (and (>= row 0) (< row (length starts)))
    (let* ((line (nth row (plist-get screen :rows)))
           (i (length (truncate-string-to-width line column)))
           (offset (+ (aref starts row) i)))
      (and (< i (length line)) (memq (aref line i) '(?| ?│ ?┃))
           (cl-some (lambda (run)
                      (and (= (car run) offset) (= (cadr run) (1+ offset))
                           (emacsvox-eat--highlight-signature (caddr run))))
                    (plist-get screen :styles))))))

(defun emacsvox-eat--vim-window (screen)
  "Return display column bounds of the cursor's window when dividers are visible."
  (let* ((row (plist-get screen :cursor-row)) (column (plist-get screen :cursor-column))
         (line (and row (nth row (plist-get screen :rows))))
         (start 0) starts left right)
    (while (and column line (string-match "[|│┃]" line start))
      (let* ((i (match-beginning 0)) (col (string-width (substring line 0 i))))
        (setq start (1+ i))
        (unless starts (setq starts (emacsvox-eat--row-start-offsets (plist-get screen :text))))
        (when (and (emacsvox-eat--vim-divider-p screen starts row col)
                   (or (emacsvox-eat--vim-divider-p screen starts (1- row) col)
                       (emacsvox-eat--vim-divider-p screen starts (1+ row) col)))
          (if (< col column) (setq left (1+ col)) (unless right (setq right col))))))
    (when (or left right) (cons (or left 0) (or right (car (plist-get screen :size)))))))

(defun emacsvox-eat--vim-line (screen row window)
  "Return the visible portion of ROW in WINDOW on SCREEN."
  (when-let* ((line (and (natnump row) (nth row (plist-get screen :rows)))))
    (if window (truncate-string-to-width line (cdr window) (car window)) line)))

(defun emacsvox-eat--vim-cursor-line (screen)
  "Return the current Vim window's row from SCREEN."
  (emacsvox-eat--vim-line screen (plist-get screen :cursor-row) (emacsvox-eat--vim-window screen)))

(defun emacsvox-eat--vim-point (screen)
  "Describe the terminal cursor using redacted text and its active window."
  (let* ((row (plist-get screen :cursor-row)) (col (plist-get screen :cursor-column))
         (window (emacsvox-eat--vim-window screen))
         (line (emacsvox-eat--vim-line screen row window))
         (column (and col (- col (or (car window) 0)))))
    (when (and line column (>= column 0))
      (list :row row :column column :window window :line line
            :index (length (truncate-string-to-width line column))))))

(defun emacsvox-eat--vim-row-text (line)
  "Return a bounded spoken form of a Vim LINE, including an empty row."
  (or (emacsvox-eat--bounded-output (list (string-trim-right line))) "blank"))

(defun emacsvox-eat--vim-say (content kind &optional icon)
  "Present CONTENT for KIND using the usual edit tone or optional auditory ICON."
  (pcase kind
    ('navigation
     (emacsvox-eat--submit content (emacsvox-eat--facts 'command-output 'focus-entered 'output-navigation)
                           'navigation icon 'replaceable (emacsvox-eat--terminal-delivery-key 'focus)))
    ('character (emacsvox-speak-this-char content))
    ('completion
     (emacsvox-eat--submit content (emacsvox-eat--facts 'command-output 'focus-entered 'completion)
                           'navigation nil 'replaceable (emacsvox-eat--terminal-delivery-key 'focus)))
    ('deletion
     (if (characterp content)
         (let ((emacsvox-aural-submission-module 'eat) (emacsvox-aural-submission-occasion 'edit))
           (emacsvox-speak-edit-operation 'deletion)
           (emacsvox-speak-this-char content))
       (emacsvox-eat--submit content (emacsvox-eat--facts 'command-input 'object-changed nil
                                                         '(:edit-operation deletion)) 'edit)))
    ((or 'uppercase 'lowercase 'line-created)
     (if content
         (emacsvox-eat--submit content (emacsvox-eat--facts 'command-input 'object-changed nil
                                                           (list :edit-operation kind)) 'edit)
       (let ((emacsvox-aural-submission-module 'eat))
         (emacsvox-speak-edit-operation kind))))
    ('paste
     (emacsvox-eat--submit content (emacsvox-eat--facts 'command-input 'object-changed nil
                                                       '(:command-input-origin copied)) 'edit 'yank-object))
    ('edit
     (emacsvox-eat--submit content (emacsvox-eat--facts 'command-input 'object-changed) 'edit icon))
    (_ (emacsvox-eat--submit content (emacsvox-eat--facts 'command-interaction 'state-changed)
                             'state-change icon))))

(declare-function emacsvox-eat--deleted-character-name "emacsvox-eat-input" (character))
(declare-function emacsvox-eat--deleted-text-content "emacsvox-eat-input" (text intent))
(defvar emacsvox-line-echo)
(defvar emacsvox-character-echo)
(defvar emacsvox-word-echo)

(defun emacsvox-eat--vim-present-echo (text after)
  "Apply typing echo preferences to verified TEXT ending at AFTER."
  (let* ((line (plist-get after :line)) (end (plist-get after :index))
         (start (max 0 (- end (length text))))
         (pos start) words)
    (when (and emacsvox-word-echo (string-match-p (rx blank) text))
      ;; Include the word already under construction when its space arrives.
      (while (and (> pos 0) (memq (char-syntax (aref line (1- pos))) '(?w ?_))) (cl-decf pos))
      (while (and (string-match (rx (group (+ (or word "_"))) (+ blank)) line pos)
                  (<= (match-end 0) end))
        (setq pos (match-end 0))
        (when (> pos start) (push (match-string 1 line) words))))
    (cond
     ((and words (or (not emacsvox-character-echo) (string-blank-p text)))
      (emacsvox-eat--vim-say (string-join (nreverse words) " ") 'edit))
     ((not emacsvox-character-echo))
     ((length= text 1) (emacsvox-speak-this-char (aref text 0)))
     ((string-blank-p text) (emacsvox-eat--vim-say (format "%d spaces" (length text)) 'edit))
     (t (emacsvox-eat--vim-say text 'edit)))))

(defun emacsvox-eat--vim-deletion (text)
  "Present verified removed TEXT using the ordinary character or text feedback."
  (list 'deletion (if (length= text 1) (aref text 0)
                    (string-trim-right (emacsvox-eat--deleted-text-content text '(:action delete))))))
(defvar emacsvox-eat--last-status-text)
(defvar emacsvox-eat--last-likely-focus)
(defvar emacsvox-eat--last-focus-presentation-identity)
(defvar emacsvox-eat--update-serial)

(defun emacsvox-eat--vim-blank-row (&optional location inspection)
  "Present the configured empty-line cue, optionally speaking LOCATION.
INSPECTION marks an explicit review rather than cursor movement."
  (let ((facts (emacsvox-eat--facts 'command-output 'focus-entered 'output-navigation
                                    '(:line-condition empty)))
        (key (emacsvox-eat--terminal-delivery-key 'focus)))
    (if location
        (emacsvox-eat--submit location facts (if inspection 'inspection 'navigation) nil
                              (unless inspection 'replaceable) (unless inspection key))
      (emacsvox-aural-submit-actions :facts facts :module 'eat :occasion 'navigation :lane 'main
                                     :delivery-policy 'replaceable :replacement-key key))))

(defun emacsvox-eat--vim-file-boundary (tail)
  "Return the buffer percentage requested by a plain gg or G in TAIL."
  (cond ((equal tail '(?g ?g)) 0) ((equal tail '(?G)) 100)))

(defun emacsvox-eat--vim-at-file-boundary-p (percent screen)
  "Whether SCREEN already places the cursor at the file boundary PERCENT."
  (let* ((state (emacsvox-eat--vim-status screen)) (ruler (plist-get state :ruler))
         (row (plist-get screen :cursor-row)) (saved (cdr emacsvox-eat--vim-last-boundary)))
    (and ruler row (not (or (plist-get state :mode) (plist-get state :prompt)
                            (plist-get state :message) (plist-get state :confirmation)))
         (or (zerop (car ruler))
             (if (zerop percent) (= (car ruler) 1)
               (or (and (eql percent (car emacsvox-eat--vim-last-boundary))
                        (equal row (plist-get saved :cursor-row))
                        (equal (plist-get screen :rows) (plist-get saved :rows)))
                   (and (< row (1- (emacsvox-eat--vim-status-index screen)))
                        (equal "~" (string-trim-right
                                    (or (emacsvox-eat--vim-line screen (1+ row)
                                          (emacsvox-eat--vim-window screen)) ""))))))))))

(defun emacsvox-eat--vim-present-boundary (percent screen)
  "Read the destination line and give the usual PERCENT position notification."
  (let ((line (emacsvox-eat--vim-cursor-line screen))
        (emacsvox-aural-submission-module 'eat))
    (emacsvox-icon 'large-movement)
    (if (string-blank-p line) (emacsvox-eat--vim-blank-row)
      (emacsvox-eat--vim-say (emacsvox-eat--vim-row-text line) 'navigation))
    (tts-notify (emacsvox-speak--percentage-description percent))
    (setq emacsvox-eat--vim-last-boundary (cons percent screen))))

(defun emacsvox-eat--vim-echo (keys before after old new replace &optional changing)
  "Match the visible inserted text between BEFORE and AFTER to a prefix of KEYS.
OLD and NEW are the public screens.  REPLACE permits a visible overwrite.
CHANGING permits a change operator to remove text before the insertion."
  (let* ((a (plist-get before :line)) (b (plist-get after :line))
         (start (plist-get before :index)) (end (plist-get after :index))
         (row (plist-get before :row)) (target (plist-get after :row))
         (width (car (plist-get old :size))))
    (when (and (= (1+ row) target) (null (plist-get before :window))
               (>= (+ (plist-get old :cursor-column) (length keys)) (1- width)))
      (let ((wrapped (nth row (plist-get new :rows))))
        (when (>= (string-width wrapped) (1- width))
          (setq end (+ (length wrapped) end) b (concat wrapped b) target row))))
    (when (and (= row target) (< start end) (<= end (length b))
               (not (equal a b)) (<= (- end start) (length keys))
               (eq t (compare-strings a 0 start b 0 start))
               (or replace
                   (and changing
                        (string-suffix-p (string-trim-right (substring b end))
                                         (string-trim-right (substring a start))))
                   (equal (string-trim-right (substring a start))
                          (string-trim-right (substring b end)))))
      (let* ((inserted (substring b start end))
             (size (length inserted)))
        (when (equal (string-to-list inserted) (seq-take keys size))
          (cons inserted (nthcdr size keys)))))))

(defun emacsvox-eat--vim-word (line index big)
  "Read the displayed word at INDEX in LINE.  BIG groups nonblank characters."
  (let ((pattern (if big "[^[:space:]]+" "[[:alnum:]_]+\\|[^[:alnum:]_[:space:]]+"))
        (start 0) word)
    (while (and (not word) (<= start index) (string-match pattern line start))
      (setq start (match-end 0))
      (when (<= (match-beginning 0) index (1- start))
        (setq word (match-string 0 line))))
    (if word (emacsvox-eat--vim-row-text word)
      (if (< index (length line)) (emacsvox-eat--deleted-character-name (aref line index)) "blank"))))

(defun emacsvox-eat--vim-row-motion-p (old new from to window direction)
  "Check a move from FROM to TO in WINDOW between OLD and NEW.
At a scrolling edge, two distinct rows must have shifted together."
  (let ((step (if (eq direction 'down) 1 -1)))
    (cond
     ((> (* step (- to from)) 0)
      (cl-loop for row from (min from to) to (max from to)
               always (equal (emacsvox-eat--vim-line old row window)
                             (emacsvox-eat--vim-line new row window))))
     ((= from to)
      (let* ((near (- to step)) (far (- to (* 2 step)))
             (a (emacsvox-eat--vim-line old from window))
             (b (emacsvox-eat--vim-line old near window)))
        (and a b (not (equal a b)) (not (equal a (emacsvox-eat--vim-line new to window)))
             (equal a (emacsvox-eat--vim-line new near window))
             (equal b (emacsvox-eat--vim-line new far window))))))))

(defun emacsvox-eat--vim-search-p (keys from)
  "Whether KEYS repeat a search or submit the search prompt visible in FROM."
  (let ((key (car (last keys))))
    (or (memq key '(?n ?N ?* ?#))
        (and (eq key 'return)
             (or (memq (plist-get from :prompt) '(?/ ??)) (memq (car keys) '(?/ ??)))))))

(defun emacsvox-eat--vim-search-ready-p (line from to)
  "Whether LINE can be the result of the visible search in FROM or TO.
A partially redrawn empty row cannot satisfy a nonempty literal search."
  (let ((pattern (or (plist-get to :search) (plist-get from :search))))
    (or (not (string-empty-p (string-trim line)))
        (and pattern (not (string-match-p (rx string-start (optional "\\<") (+ (or alnum "_"))
                                             (optional "\\>") string-end) pattern))))))

(defun emacsvox-eat--vim-motion (keys old new before after from to)
  "Describe a movement supported by KEYS and the rendered cursor and text.
OLD and NEW are screens, BEFORE and AFTER their cursor facts, FROM and TO
their respective command rows."
  (let* ((key (car (last keys)))
         (row (plist-get after :row)) (line (plist-get after :line))
         (index (plist-get after :index)) (origin (plist-get before :row))
         (column (plist-get before :index))
         (moved (or (/= row origin) (/= index column)
                    (and (plist-get to :ruler)
                         (not (equal (plist-get from :ruler) (plist-get to :ruler))))))
         (direction (cond ((memq key '(?j down)) 'down) ((memq key '(?k up)) 'up)))
         (find-key (and (cdr keys) (car (last keys 2))))
         (ruler (plist-get to :ruler))
         (tail (emacsvox-eat--vim-command-tail keys))
         (boundary (emacsvox-eat--vim-file-boundary tail))
         (mark (and (length= tail 2) (characterp key)
                    (string-match-p (rx string-start alpha string-end) (string key)))))
    (cond
     ((and boundary (or moved (not (equal line (plist-get before :line)))
                        (emacsvox-eat--vim-at-file-boundary-p boundary new)))
      (cons 'file-boundary boundary))
     ((and ruler (memq key '(?g ?G)) (characterp (car tail)) (<= ?1 (car tail) ?9)
           (cl-every #'characterp tail)
           (string-match-p (rx string-start (+ digit) (or "gg" "G") string-end) (apply #'string tail)))
      (let ((location (format "Line %d" (car ruler))))
        (if (string-blank-p line) (cons 'blank-location location)
          (cons 'jump (concat location ", " (emacsvox-eat--vim-row-text line))))))
     ((and (memq key '(C-left C-right)) moved)
      (cond
       ((string-blank-p line) (cons 'row "blank"))
       ((>= index (length line)) (cons 'navigation "End of line"))
       (t
        (let ((word (emacsvox-eat--vim-word line index (not (or (plist-get to :mode) (plist-get to :prompt))))))
          (if (or (memq (aref line index) '(?\s ?\t))
                  (and (length= word 1) (not (string-match-p "[[:alnum:]_]" word))))
              (cons 'character (aref line index))
            (cons 'navigation word))))))
     ((and mark (eq (car tail) ?m) (equal before after)
           (not (plist-get to :prompt)) ruler)
      (cons 'mark (format "Mark %c requested at line %d, column %d" key (car ruler) (cdr ruler))))
     ((and (or (memq key '(4 21 6 2 15 9 tab ?H ?M ?L))
               (and (memq (car tail) '(?\' ?\x60)) (length= tail 2)))
           (or moved (not (equal line (plist-get before :line)))
               (and ruler (memq key '(?H ?M ?L)))))
      (let ((location (format "%s, column %d" (if ruler (format "Line %d" (car ruler)) (format "Row %d" (1+ row)))
                              (or (cdr ruler) (1+ (plist-get after :column))))))
        (if (string-blank-p line) (cons 'blank-location location)
          (cons 'jump (concat location ", " (emacsvox-eat--vim-row-text line))))))
     ((and moved (memq key '(?\; ?,)) (= origin row) (< index (length line))
           (equal line (plist-get before :line)))
      (cons 'character (aref line index)))
     ((eq key 12)
      (if (and ruler (string-empty-p (string-trim line)))
          (cons 'navigation (format "Line %d, no text displayed" (car ruler)))
        (cons 'navigation (emacsvox-eat--vim-row-text line))))
     ((and moved (memq find-key '(?f ?F ?t ?T)) (characterp key)
           (= origin row) (equal line (plist-get before :line)))
      (let ((found (+ index (pcase find-key (?t 1) (?T -1) (_ 0)))))
        (when (and (<= 0 found) (< found (length line)) (= (aref line found) key)
                   (< index (length line)))
          (cons 'character (aref line index)))))
     ((and moved (memq key '(?% ?{ ?})))
      (let ((location (if ruler (format "Line %d" (car ruler)) (format "Row %d" (1+ row)))))
        (if (string-blank-p line) (cons 'blank-location location)
          (cons 'navigation
            (concat location
                    (if (and (eq key ?%) (< index (length line)))
                        (format ", column %d, %s" (or (cdr ruler) (1+ (plist-get after :column)))
                                (emacsvox-eat--deleted-character-name (aref line index)))
                      (concat ", " (emacsvox-eat--vim-row-text line))))))))
     ((and direction (emacsvox-eat--vim-row-motion-p
                      old new origin row (plist-get after :window) direction))
      (cons 'row (emacsvox-eat--vim-row-text line)))
     ((and moved (emacsvox-eat--vim-search-p keys from)
           (not (emacsvox-eat--vim-search-ready-p line from to))
           (plist-get to :ruler))
      (cons 'match-location (format "Match on line %d" (car (plist-get to :ruler)))))
     ((and (or moved (not (equal line (plist-get before :line))))
           (or (eq key ?G) (equal (last keys 2) '(?g ?g))
               (and (emacsvox-eat--vim-search-p keys from)
                    (emacsvox-eat--vim-search-ready-p line from to))))
      (cons 'row (emacsvox-eat--vim-row-text line)))
     ((and moved
           (equal line (emacsvox-eat--vim-line old row (plist-get after :window))))
      (cond
       ((memq key '(?h ?l left right ?0 ?^ ?$ home end))
        (if (< index (length line)) (cons 'character (aref line index)) (cons 'navigation "blank")))
       ((memq key '(?b ?w ?e ?B ?W ?E))
        (cons 'navigation (emacsvox-eat--vim-word line index (memq key '(?B ?W ?E))))))))))

(defun emacsvox-eat--vim-command-tail (keys)
  "Skip completed positioning keys before the final command in KEYS.
Motions at a boundary can leave no repaint to consume their input."
  (while (and (cdr keys)
              (cond ((and (eq (car keys) ?g) (eq (cadr keys) ?g) (cddr keys))
                     (setq keys (cddr keys)))
                    ((memq (car keys) '(?0 ?^ ?$ ?h ?j ?k ?l ?G home end left right up down))
                     (setq keys (cdr keys))))))
  keys)

(defun emacsvox-eat--vim-unchanged-input-p ()
  "Whether a pending Vim command may finish without changing a cell."
  (let ((keys (emacsvox-eat--vim-command-tail emacsvox-eat--vim-keys)))
    (or (emacsvox-eat--vim-file-boundary keys)
        (member keys '((?y ?y) (?y ?w) (12) (?H) (?M) (?L) (9) (tab)))
        (and (eq (car keys) ?m) (length= keys 2)))))

(defun emacsvox-eat--vim-replay-label (keys)
  "Name the replay requested by KEYS, including a repeat of the last macro."
  (let ((tail (emacsvox-eat--vim-command-tail keys)))
    (while (and (characterp (car tail)) (<= ?0 (car tail) ?9)) (setq tail (cdr tail)))
    (when (and (eq (car tail) ?@) (length= tail 2) (characterp (cadr tail)))
      (cond ((eq (cadr tail) ?@) "Replay last macro")
            ((string-match-p (rx string-start (or alnum "\"") string-end) (string (cadr tail)))
             (format "Replay register %c" (cadr tail)))))))

(defvar emacsvox-eat--secure-input-active-p)
(defvar emacsvox-eat--screen-snapshot)
(declare-function emacsvox-eat--foreground-p "emacsvox-eat-core" ())
(declare-function emacsvox-eat--following-live-p "emacsvox-eat-core" ())

(defun emacsvox-eat--vim-quiet-response (buffer keys result)
  "Present RESULT in BUFFER when delivered KEYS leave Vim's cursor still.
A numeric RESULT is a verified file boundary. A string names a requested replay."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (and (eq emacsvox-eat-application-profile 'vim)
                 (or (numberp result) emacsvox-eat--vim-normal-evidence)
                 (equal emacsvox-eat--vim-keys keys) (< (float-time) emacsvox-eat--vim-deadline)
                 (not emacsvox-eat--secure-input-active-p) (emacsvox-eat--foreground-p)
                 (emacsvox-eat--following-live-p)
                 (equal (emacsvox-eat--vim-point emacsvox-eat--vim-origin)
                        (emacsvox-eat--vim-point emacsvox-eat--screen-snapshot)))
        (if (numberp result)
            (when (emacsvox-eat--vim-at-file-boundary-p result emacsvox-eat--screen-snapshot)
              (emacsvox-eat--vim-present-boundary result emacsvox-eat--screen-snapshot)
              (emacsvox-eat--vim-forget-input))
          (emacsvox-eat--vim-say (concat result " requested") 'edit)
          ;; Keep the original screen for a late SSH result until another key.
          (setq emacsvox-eat--vim-quiet-timer 'announced))))))

(defun emacsvox-eat--vim-after-send ()
  "Allow one response for a silent replay or a jump to an existing boundary."
  (let* ((keys emacsvox-eat--vim-keys)
         (boundary (and (memq (car (last keys)) '(?G ?g))
                        (emacsvox-eat--vim-file-boundary (emacsvox-eat--vim-command-tail keys))))
         (result (cond ((and boundary (emacsvox-eat--vim-at-file-boundary-p boundary emacsvox-eat--vim-origin))
                        boundary)
                       ((and emacsvox-eat--vim-normal-evidence (memq ?@ keys))
                        (emacsvox-eat--vim-replay-label keys)))))
    (when result
      (when (timerp emacsvox-eat--vim-quiet-timer) (cancel-timer emacsvox-eat--vim-quiet-timer))
      (setq emacsvox-eat--vim-quiet-timer
            (run-at-time 0.35 nil #'emacsvox-eat--vim-quiet-response (current-buffer) (copy-sequence keys) result)))))

(defun emacsvox-eat--vim-normal-edit (keys a b i j next status)
  "Describe a Normal command in KEYS using rows A, B, indexes I, J and NEXT.
STATUS contains Vim's rendered command row."
  (setq keys (emacsvox-eat--vim-command-tail keys))
  (let ((a (string-trim-right a)) (b (string-trim-right b))
        (command (when (cl-every #'characterp keys) (apply #'string keys))))
    (when command
      (cond
       ((and (or (and (length= keys 2) (eq (car keys) ?r)) (equal command "~"))
             (< i (length a)) (< i (length b)) (/= (aref a i) (aref b i))
             (or (equal command "~") (= (cadr keys) (aref b i)))
             (equal (substring a 0 i) (substring b 0 i))
             (equal (substring a (1+ i)) (substring b (1+ i))))
        (if (equal command "~")
            (list (if (= (upcase (aref b i)) (aref b i)) 'uppercase 'lowercase)
                  (emacsvox-eat--deleted-character-name (aref b i)))
          (format "Replaced %s with %s" (emacsvox-eat--deleted-character-name (aref a i))
                  (emacsvox-eat--deleted-character-name (aref b i)))))
       ((and (equal command "D") (< i (length a)) (equal (string-trim-right (substring a 0 i)) b))
        (emacsvox-eat--vim-deletion (substring a i)))
       ((and (equal command "diw") (<= j i) (< i (length a)))
        (let ((end (+ j (- (length a) (length b)))))
          (when (and (< i end) (<= end (length a))
                     (equal b (concat (substring a 0 j) (substring a end))))
            (emacsvox-eat--vim-deletion (substring a j end)))))
       ((and (string-match-p (rx string-start (+ digit) "dd" string-end) command)
             (string-match (rx string-start (group (+ digit)) " fewer lines" string-end)
                           (plist-get status :text)))
        (list 'deletion (format "%s lines deleted, %s" (match-string 1 (plist-get status :text))
                                (emacsvox-eat--vim-row-text b))))
       ((and (equal command "J") next (not (equal a b)) (string-prefix-p a b)
             (string-suffix-p (string-trim next) b))
        (concat "Joined, " (emacsvox-eat--vim-row-text b)))
       ((and (member command '(">>" "<<")) (not (equal a b))
             (equal (string-trim-left a) (string-trim-left b)))
        (list 'indent (format "Column %d" (1+ (- (string-width b) (string-width (string-trim-left b)))))))))))

(defun emacsvox-eat--vim-edit (keys old new before after inserting status)
  "Describe an edit confirmed between OLD and NEW at BEFORE and AFTER.
INSERTING means the visible mode or command prompt accepts text.
STATUS describes the command row on NEW."
  (let* ((key (car (last keys))) (row (plist-get before :row)) (target (plist-get after :row))
         (a (plist-get before :line)) (b (plist-get after :line))
         (i (plist-get before :index)) (j (plist-get after :index))
         (window (plist-get after :window))
         (next (emacsvox-eat--vim-line old (1+ row) window))
         (same-row (= row target))
         (delete-word (and (not inserting) (eq (car (last keys 2)) ?d)
                           (memq key '(?w ?W ?e ?E ?b ?B))))
         (change (and same-row (emacsvox-eat--sequence-change (string-trim-right a)
                                                             (string-trim-right b)))))
    (cond
     ((and (not inserting) same-row
           (emacsvox-eat--vim-normal-edit keys a b i j next status)))
     ((and same-row (equal (plist-get status :mode) "Insert")
           (memq key '(21 23)) (< j i) (<= i (length a))
           (equal (string-trim-right (concat (substring a 0 j) (substring a i)))
                  (string-trim-right b)))
      (emacsvox-eat--vim-deletion (substring a j i)))
     ((and same-row (equal (plist-get status :mode) "Insert") (memq key '(9 tab))
           (< i j) (<= j (length b)) (equal (substring a 0 i) (substring b 0 i))
           (string-match-p (rx string-start (+ blank) string-end) (substring b i j))
           (equal (string-trim-right (substring a i)) (string-trim-right (substring b j))))
      (list 'indent (format "Column %d" (or (cdr (plist-get status :ruler)) (1+ (plist-get after :column))))))
     ((and (not inserting) (memq key '(?x ?X)) same-row
           (string-empty-p (string-trim a)) (not (string-empty-p (string-trim b))))
      ;; A terminal can leave a row empty until Vim edits it after closing a split.
      (concat "Current row, " (emacsvox-eat--vim-row-text b)))
     ((and (or delete-word (memq key '(backspace delete ?x ?X)))
           (or (not inserting) (memq key '(backspace delete)))
           same-row (not (equal a b)))
      (let* ((back (memq key '(backspace ?X ?b ?B))) (start (if back j i))
             (trimmed (string-trim-right b))
             ;; Closing a split can leave right-side padding until the next edit.
             (ends (if back (list i)
                     (list (+ i (- (length (string-trim-right a)) (length trimmed)))
                           (+ i (- (length a) (length b)))))))
        (cl-loop for end in ends
                 when (and (<= 0 start) (< start end) (<= end (length a))
                           (equal (string-trim-right (concat (substring a 0 start) (substring a end)))
                                  trimmed))
                 return (emacsvox-eat--vim-deletion (substring a start end)))))
     ((and inserting (eq key 'backspace) (= (1+ target) row)
           (string-suffix-p (string-trim-right a) (string-trim-right b)))
      (emacsvox-eat--vim-deletion "\n"))
     ((and inserting (eq key 'return) (= target (1+ row))
           (string-suffix-p (string-trim-right (substring a i)) (string-trim-right b)))
      (list 'line-created (and emacsvox-line-echo (emacsvox-eat--vim-row-text
                                                   (emacsvox-eat--vim-line new row window)))))
     ((and (not inserting) (equal (last keys 2) '(?d ?d))
           (or (and same-row next (equal (string-trim-right b) (string-trim-right next)))
               (and (= (1+ target) row)
                    (equal b (emacsvox-eat--vim-line old target window)))))
      (list 'deletion (emacsvox-eat--vim-row-text a)))
     ((and (not inserting) (memq key '(?p ?P)))
      (when-let* ((added
                   (cond
                    ((and change (= (plist-get change :start) (plist-get change :old-end)))
                     (substring b (plist-get change :start) (plist-get change :new-end)))
                    ((and (or (= target (1+ row)) (and same-row change))
                          (equal (emacsvox-eat--vim-line old target window)
                                 (emacsvox-eat--vim-line new (1+ target) window))) b))))
        (list 'paste (emacsvox-eat--vim-row-text added))))
     ((and (not inserting) (memq key '(?u 18 ?.)) (or change (not same-row)))
      (if (eq key ?.) (concat "Repeated change, " (emacsvox-eat--vim-row-text b))
        (list 'row (emacsvox-eat--vim-row-text b)))))))

(defun emacsvox-eat--vim-selection-position (status point)
  "Return a comparable file or screen position from STATUS and POINT."
  (if-let* ((ruler (plist-get status :ruler))) (list 'file (car ruler) (cdr ruler))
    (list 'screen (plist-get point :row) (plist-get point :column))))

(defun emacsvox-eat--vim-selection (mode position)
  "Describe the extent from the observed selection anchor to POSITION in MODE."
  (when (and emacsvox-eat--vim-anchor (eq (car position) (car emacsvox-eat--vim-anchor)))
    (let ((rows (1+ (abs (- (nth 1 position) (nth 1 emacsvox-eat--vim-anchor)))))
          (cols (1+ (abs (- (nth 2 position) (nth 2 emacsvox-eat--vim-anchor))))))
      (cond ((string-suffix-p "block" mode) (format "Selection, %d by %d" rows cols))
            ((or (> rows 1) (string-suffix-p "line" mode))
             (format "%d %s selected" rows (if (= rows 1) "line" "lines")))
            (t (format "%d %s selected" cols (if (= cols 1) "column" "columns")))))))

(defun emacsvox-eat--vim-selected-rows (screen &optional status)
  "Read contiguous visible selection spans in the cursor's pane on SCREEN.
STATUS, when supplied, is the already parsed Vim footer."
  (let* ((state (or status (emacsvox-eat--vim-status screen)))
         (mode (plist-get state :mode)))
    (when (and mode (string-match-p (rx string-start (or "Visual" "Select")) mode))
      (let* ((point (emacsvox-eat--vim-point screen)) (row (plist-get point :row))
             (col (plist-get screen :cursor-column)) (pane (plist-get point :window))
             (left (or (car pane) 0)) (right (or (cdr pane) (car (plist-get screen :size))))
             (line (plist-get point :line)) (index (plist-get point :index))
             (cell (if (< index (length line)) (max 1 (char-width (aref line index))) 1))
             (bottom (emacsvox-eat--vim-status-index screen))
             (regions (emacsvox-eat--highlight-regions screen))
             ;; Vim often draws the cursor cell without the Visual face.
             (near (cl-find-if (lambda (r)
                                 (and (= row (plist-get r :row-start) (plist-get r :row-end))
                                      (< (plist-get r :column-start) right)
                                      (> (plist-get r :column-end) left)
                                      (<= (plist-get r :column-start) (+ col cell))
                                      (>= (plist-get r :column-end) col))) regions))
             (signature (or (plist-get near :signature)
                            (and (= col left)
                                 (plist-get
                                  (cl-find-if (lambda (r)
                                                (and (= (plist-get r :row-start) (1- row))
                                                     (<= left (plist-get r :column-start))
                                                     (< (plist-get r :column-start) right))) regions)
                                  :signature))))
             (spans (make-hash-table :test #'eql))
             (first row) (last row) result)
        (when signature
          (dolist (r regions)
            (let* ((n (plist-get r :row-start)) (a (max left (plist-get r :column-start)))
                   (b (min right (plist-get r :column-end))) (span (gethash n spans)))
              (when (and (< a b) (= n (plist-get r :row-end)) (< n bottom)
                         (equal signature (plist-get r :signature))
                         (or (not span) (= a (cdr span))
                             (and (= n row) (= (cdr span) col) (= a (+ col cell)))))
                (puthash n (cons (if span (car span) a) b) spans))))
          (while (gethash (1- first) spans) (cl-decf first))
          (while (gethash (1+ last) spans) (cl-incf last)))
        (let ((span (gethash row spans))
              (count (when (string-match (rx "--" (+ blank) (group (+ digit)) (* blank) string-end)
                                         (plist-get state :text))
                       (string-to-number (match-string 1 (plist-get state :text))))))
          (when (or span (< first row) (and count (= count 1)) (string-suffix-p "line" mode))
            (cond
             ((string-suffix-p "line" mode) (puthash row (cons left right) spans))
             ((or (not span) (/= first last) (not count) (> count (- (cdr span) (car span))))
              (puthash row (cons (min col (or (car span) col))
                                 (max (+ col cell) (or (cdr span) col))) spans)))
            (cl-loop for n from first to last for bounds = (gethash n spans)
                     do (push (string-trim-right
                               (truncate-string-to-width (nth n (plist-get screen :rows))
                                                         (cdr bounds) (car bounds))) result))
            (nreverse result)))))))

(defun emacsvox-eat--vim-after-entry (keys mode prompt)
  "Return KEYS following an observed entry into MODE or PROMPT."
  (let ((entry (cond (prompt (list prompt))
                     ((equal mode "Insert") '(?i ?I ?a ?A ?o ?O ?s ?S ?c))
                     ((member mode '("Replace" "Virtual Replace")) '(?R))
                     ((and mode (string-match-p "\\`\\(?:Visual\\|Select\\)" mode)) '(?v ?V 22))
                     (t '(escape 3 ?v ?V ?y ?d ?x ?p ?P)))))
    (when-let* ((tail (cl-loop for pending on keys when (memq (car pending) entry) return pending)))
      (if (and (eq (car tail) ?c) (equal mode "Insert") (not prompt))
          ;; A change enters Insert after its motion or text object.
          (let ((motion (seq-drop-while (lambda (k) (and (integerp k) (<= ?0 k ?9)))
                                        (cdr tail))))
            (nthcdr (if (memq (car motion) '(?i ?a ?f ?F ?t ?T ?g)) 2 1) motion))
        (cdr tail)))))

(defun emacsvox-eat--vim-file-argument (state)
  "Return the displayed filename argument in an active Ex file prompt STATE."
  (when-let* (((eq (plist-get state :prompt) ?:)) (command (plist-get state :command))
              ((string-match (rx string-start ":" (* blank)
                                 (or "e" "edit" "tabedit" "tabe" "split" "vsplit" "read" "write")
                                 (optional "!") (+ blank) (group (* nonl)) string-end) command)))
    (string-replace "\\ " " " (match-string 1 command))))

(defun emacsvox-eat--vim-file-candidate (screen before after)
  "Read the completed filename at AFTER on SCREEN, using BEFORE for a single match."
  (let* ((prefix (substring (plist-get after :line) 0 (plist-get after :index)))
         (initial (substring (plist-get before :line) 0 (plist-get before :index)))
         (candidates
          (cl-loop for r in (emacsvox-eat--highlight-regions screen)
                   for name = (plist-get r :text)
                   when (and (not (= (plist-get after :row) (plist-get r :row-start)))
                             (not (string-empty-p name)) (string-suffix-p name prefix))
                   collect name)))
    (or (car (sort candidates :key #'length :lessp #'>))
        (let ((start (if (string-match (rx (* (not blank)) string-end) initial) (match-beginning 0) 0)))
          (when (and (< start (length prefix)) (string-prefix-p (substring initial 0 start) prefix))
            (substring prefix start))))))

(defun emacsvox-eat--vim-completion (status before after)
  "Read the keyword Vim inserted and the match position displayed in STATUS."
  (let ((position (string-remove-prefix "match " status))
        (prefix (substring (plist-get after :line) 0 (plist-get after :index))))
    (if (and (or (string-prefix-p "match " status) (equal status "The only match"))
             (not (equal before after))
             (string-match (rx (group (+ (or alnum "_"))) string-end) prefix))
        (concat (match-string 1 prefix) ", " position)
      status)))

(defun emacsvox-eat--vim-fold-summary (point)
  "Return the line count and description of a stock closed fold at POINT."
  (let ((line (plist-get point :line)))
    (when (string-match (rx string-start (* blank) "+" (+ "-") (+ blank) (group (+ digit))
                            " line" (optional "s") ":" (* blank) (group (* nonl))) line)
      (let ((count (match-string 1 line)) (label (match-string 2 line)))
        (cons count (string-trim-right label (rx (+ (any "-─ ")) string-end)))))))

(defun emacsvox-eat--vim-fold (keys before after)
  "Describe opening or closing a fold when KEYS and both rendered rows agree."
  (let* ((tail (emacsvox-eat--vim-command-tail keys)) (op (cadr tail)))
    (when (and (eq (car tail) ?z) (memq op '(?f ?o ?O ?c ?C ?a ?A))
               (not (equal (plist-get before :line) (plist-get after :line))))
      (let ((old (emacsvox-eat--vim-fold-summary before)) (new (emacsvox-eat--vim-fold-summary after)))
        (cond
         ((and new (memq op '(?f ?c ?C ?a ?A)))
          (list 'fold-closed (format "Fold %s, %s lines, %s" (if (eq op ?f) "created" "closed")
                                     (car new) (emacsvox-eat--vim-row-text (cdr new)))))
         ((and old (memq op '(?o ?O ?a ?A)))
          (list 'fold-opened (format "Fold opened, %s lines, %s" (car old)
                                     (emacsvox-eat--vim-row-text (plist-get after :line))))))))))

(defun emacsvox-eat--vim-replay-result (label old new before after from to)
  "Describe the visible result of LABEL between OLD and NEW.
BEFORE and AFTER are cursor views.  FROM and TO describe their command rows."
  (if (or (not (equal before after)) (not (equal (plist-get from :ruler) (plist-get to :ruler))))
      (concat label ", " (emacsvox-eat--vim-row-text (plist-get after :line)))
    (let ((window (plist-get after :window)) changes)
      (dotimes (row (emacsvox-eat--vim-status-index new))
        (let ((a (emacsvox-eat--vim-line old row window)) (b (emacsvox-eat--vim-line new row window)))
          (when (and a b (not (equal (string-trim-right a) (string-trim-right b))))
            (push (cons (1+ row) b) changes))))
      (when changes
        (let ((first (car (last changes))))
          (format "%s, %d visible %s changed. Row %d, %s" label (length changes)
                  (if (length= changes 1) "row" "rows") (car first)
                  (emacsvox-eat--vim-row-text (cdr first))))))))

(defun emacsvox-eat--vim-feedback (keys old new before after from to)
  "Return keyboard feedback proved by the two screens and their parsed views."
  (let* ((mode (plist-get to :mode))
         (prompt (plist-get to :prompt))
         (typing (or prompt (member mode '("Insert" "Replace" "Virtual Replace"))))
         (new-mode (not (equal mode (plist-get from :mode))))
         (selection (and mode (string-match-p "\\`\\(?:Visual\\|Select\\)" mode)))
         (replace (member mode '("Replace" "Virtual Replace")))
         (entry (and (or new-mode (not (plist-get from :mode)))
                     (emacsvox-eat--vim-after-entry keys (or mode "Insert") prompt)))
         (echo-before (if (and prompt (not (plist-get from :prompt)))
                          (list :line (char-to-string prompt) :index 1 :row (plist-get after :row))
                        before))
         (echo (and (not selection)
                    (or (and entry (emacsvox-eat--vim-echo
                                    entry echo-before after old new replace
                                    (and (equal mode "Insert") (eq (car keys) ?c))))
                        (emacsvox-eat--vim-echo keys before after old new replace)))))
    (cond
     ((plist-get to :blocking) nil)
     ((and (plist-get from :blocking) keys (plist-get to :ruler) (not (or mode prompt)))
      (list 'row (emacsvox-eat--vim-row-text (plist-get after :line))))
     ((and (not (or typing selection (plist-get from :prompt))) (not (plist-get from :completion))
           (emacsvox-eat--vim-fold keys before after)))
     ((and (memq (car (last keys)) '(escape 5)) (not (plist-get to :prompt))
           (emacsvox-eat--vim-file-argument from)
           (cl-some (lambda (r) (= (plist-get r :row-start) (1- (plist-get before :row))))
                    (emacsvox-eat--highlight-regions old)))
      (list 'edit "Filename completion cancelled"))
     ((and (memq (car (last keys)) '(9 tab)) (emacsvox-eat--vim-file-argument to))
      (let ((name (emacsvox-eat--vim-file-argument to)))
        (cond ((not (equal name (emacsvox-eat--vim-file-argument from)))
               (list 'completion name))
              ((and emacsvox-eat--last-bell-at
                    (>= emacsvox-eat--last-bell-at (- emacsvox-eat--vim-deadline emacsvox-eat--vim-input-timeout)))
               (list 'completion "No filename match")))))
     ((and (plist-get to :file-completion) (memq (car (last keys)) '(6 14 16)))
      (let ((status (plist-get to :completion)))
        (list 'completion
              (if (or (string-prefix-p "match " status) (equal status "The only match"))
                  (string-join (delq nil (list (emacsvox-eat--vim-file-candidate new before after)
                                                (string-remove-prefix "match " status))) ", ")
                status))))
     ((and (plist-get to :completion) (memq (car (last keys)) '(14 16)))
      (list 'completion (emacsvox-eat--vim-completion (plist-get to :completion) before after)))
     ((and (plist-get from :completion) (not (plist-get to :completion)) (equal mode "Insert"))
      (pcase (car (last keys))
        (25 (list 'edit "Completion accepted"))
        (5 (list 'edit "Completion cancelled"))
        (_ (when echo (list 'echo (car echo) (cdr echo))))))
     (echo (list 'echo (car echo) (cdr echo)))
     ((and (not (or typing selection new-mode (plist-get from :prompt)))
           (emacsvox-eat--vim-replay-label keys))
      (when-let* ((result (emacsvox-eat--vim-replay-result (emacsvox-eat--vim-replay-label keys)
                                                           old new before after from to)))
        (list 'edit result)))
     ((and (not typing) (not selection) (not new-mode)
           (member (emacsvox-eat--vim-command-tail keys) '((?y ?y) (?y ?w)))
           (not (plist-get to :pending-yank)) (equal before after)
           (or (plist-get to :ruler) (plist-get from :pending-yank)))
      ;; The register is private to Vim. Describe the requested line.
      (let ((line (plist-get after :line)))
        (list 'copy (if (eq (car (last keys)) ?y)
                        (concat "Yank line, " (emacsvox-eat--vim-row-text line))
                      (concat "Yank word, " (emacsvox-eat--vim-word
                                             (substring line (plist-get after :index)) 0 nil))))))
     ((and new-mode (not mode) (eq (car (last keys)) ?y)
           (string-prefix-p "Visual" (or (plist-get from :mode) "")))
      (list 'copy "Yanked selection"))
     ((and new-mode (not mode) (memq (car (last keys)) '(?d ?x))
           (string-prefix-p "Visual" (or (plist-get from :mode) "")))
      (let* ((window (plist-get after :window)) (row (plist-get after :row))
             (line (plist-get after :line)) (original (emacsvox-eat--vim-line old row window))
             (change (and original (emacsvox-eat--sequence-change
                                    (string-trim-right original) (string-trim-right line)))))
        (when change
          (if (= (plist-get change :start) (plist-get change :new-end))
              (emacsvox-eat--vim-deletion (substring original (plist-get change :start)
                                                     (plist-get change :old-end)))
            (list 'deletion (concat "Selection deleted. " (emacsvox-eat--vim-row-text line)))))))
     ((and selection (not new-mode) (not (equal before after)))
      (when-let* ((extent (emacsvox-eat--vim-selection
                           mode (emacsvox-eat--vim-selection-position to after))))
        (let ((rows (emacsvox-eat--vim-selected-rows new to))
              (position (emacsvox-eat--vim-selection-position to after)))
          (list 'navigation
                (if (and rows (<= (length rows) 2)
                         (< (abs (- (nth 1 position) (nth 1 emacsvox-eat--vim-anchor))) 2)
                         (<= (apply #'+ (mapcar #'length rows)) 48))
                    (concat extent ", " (string-join (mapcar #'emacsvox-eat--vim-row-text rows) ". "))
                  extent)))))
     ((and (not selection) (not new-mode))
      (if-let* ((edit (emacsvox-eat--vim-edit keys old new before after typing to)))
          (if (consp edit) edit (list 'edit edit))
        (when (or (not typing)
                  (memq (car (last keys)) '(C-left C-right))
                  (and (not prompt) (memq (car (last keys)) '(left right up down))))
          (when-let* ((motion (emacsvox-eat--vim-motion keys old new before after from to)))
            (list (car motion) (cdr motion)))))))))

(defun emacsvox-eat--vim-submitted-command (from keys)
  "Return the Ex command submitted by KEYS from the displayed prompt FROM."
  (when (eq (car (last keys)) 'return)
    (let ((input (butlast keys)) (prompt (plist-get from :prompt)))
      (when (and (cl-every #'characterp input)
                 (or (eq prompt ?:) (and (not prompt) (eq (car input) ?:))))
        (string-trim (substring (concat (and prompt (plist-get from :command))
                                        (apply #'string input)) 1))))))

(defun emacsvox-eat--vim-active-tab (screen)
  "Read the active label from a stock Vim tab line on SCREEN."
  (let ((line (car (plist-get screen :rows))))
    (when (and line (string-suffix-p "X" (string-trim-right line)))
      (cl-loop for (start end style) in (plist-get screen :styles)
               while (< start (length line))
               when (and (memq 'bold (plist-get style :traits)) (<= end (length line))
                         (not (memq 'concealed (plist-get style :traits))))
               return (string-trim (substring line start end))))))

(defun emacsvox-eat--vim-tab-name (screen reported tail changed)
  "Identify the tab on SCREEN after TAIL, using a newly REPORTED filename.
On monochrome terminals, follow the visible order only if the body CHANGED
and the preceding tab was identified on the same tab line."
  (let* ((line (car (plist-get screen :rows)))
         (names (when (and line (string-match (rx string-start (group (+? nonl)) (+ "_") "X" (* blank) string-end) line))
                  (split-string (string-trim (match-string 1 line)) " +| +" t)))
         (previous (when (and names (equal names (cdr emacsvox-eat--vim-tabs)))
                     (cl-position (car emacsvox-eat--vim-tabs) names :test #'equal)))
         (name (or (emacsvox-eat--vim-active-tab screen) reported
                   (and previous changed (member tail '((?g ?t) (?g ?T)))
                        (nth (mod (+ previous (if (eq (cadr tail) ?T) -1 1)) (length names)) names)))))
    (setq emacsvox-eat--vim-tabs (and name (member name names) (= (cl-count name names :test #'equal) 1)
                                      (cons name names)))
    name))

(defun emacsvox-eat--vim-destination (keys command from to screen after)
  "Describe a visible destination reached with KEYS or submitted COMMAND.
FROM and TO describe the footers.  AFTER is the cursor on SCREEN."
  (let* ((text (plist-get to :text)) (ruler (plist-get to :ruler))
         (verb (and command (car (split-string command "[ !]+" t))))
         (tail (emacsvox-eat--vim-command-tail keys))
         (tab (or (member verb '("tabnew" "tabedit" "tabe" "tabnext" "tabn" "tabprevious"
                                 "tabp" "tabfirst" "tablast" "tabclose" "tabonly"))
                  (and (not (or (plist-get from :prompt) (plist-get from :mode)))
                       (member tail '((?g ?t) (?g ?T))))))
         (location (and ruler (format "line %d, column %d" (car ruler) (cdr ruler))))
         (line (string-trim (plist-get after :line))))
    (cond
     ((and command
           (string-match (rx string-start "(" (group (+ digit)) " of " (group (+ digit)) ")"
                             (* (any ": ")) (group (* nonl)) string-end) text)
           (member verb '("cn" "cnext" "cp" "cprev" "cprevious" "cc" "cfirst" "clast"
                          "vimgrep" "grep" "lnext" "lprevious")))
      (string-join (delq nil (list (format "Result %s of %s" (match-string 1 text) (match-string 2 text))
                                   location (match-string 3 text))) ", "))
     ((or tab (member verb '("e" "edit" "enew" "b" "buffer" "bn" "bnext" "bp" "bprev"
                             "bprevious" "bf" "bfirst" "blast" "h" "help" "helpc" "helpclose")))
      (let* ((help (member verb '("h" "help")))
             (help-line (and help (cl-find-if (lambda (s) (string-match-p (rx "[Help]") s))
                                               (nthcdr (plist-get after :row) (plist-get screen :rows)))))
             (reported (and (or (not tab) (member verb '("tabedit" "tabe" "tabnew")))
                            (string-match (rx string-start "\"" (group (+ (not (any "\"")))) "\""
                                              (+ blank)) text)
                            (match-string 1 text)))
             (name (if tab (emacsvox-eat--vim-tab-name
                            screen reported tail
                            (and emacsvox-eat--vim-origin
                                 (not (equal after (emacsvox-eat--vim-point emacsvox-eat--vim-origin)))))
                     reported)))
        (when (and help-line (string-match emacsvox-eat--vim-ruler help-line))
          (setq location (format "line %s, column %s" (match-string 1 help-line)
                                 (or (match-string 3 help-line) (match-string 2 help-line)))))
        (string-join
         (delq nil (list (string-join (delq nil (list (cond (tab "Tab") (help "Help") (t "Buffer")) name)) " ")
                         location (emacsvox-eat--vim-row-text line))) ", "))))))

(defun emacsvox-eat--vim-window-switch (keys before after)
  "Describe the destination of a window command in KEYS from BEFORE to AFTER."
  (when (and (cdr keys) (eq (car (last keys 2)) 23)
             (memq (car (last keys)) '(?w ?W ?p ?h ?j ?k ?l 23 left right up down)))
    (let* ((left (or (car (plist-get before :window)) 0))
           (new-left (or (car (plist-get after :window)) 0))
           (row (plist-get before :row)) (new-row (plist-get after :row))
           (direction (cond ((< left new-left) "Right") ((> left new-left) "Left")
                            ((< row new-row) "Lower") ((> row new-row) "Upper"))))
      (when direction
        (list 'navigation (concat direction " window, "
                                  (emacsvox-eat--vim-row-text (plist-get after :line))))))))

(defun emacsvox-eat--vim-settled (baseline screen diff automatic)
  "Handle a foreground Vim repaint from BASELINE to SCREEN.
DIFF is retained for explicit review.  AUTOMATIC permits unsolicited messages."
  (when (> (float-time) emacsvox-eat--vim-deadline)
    (emacsvox-eat--vim-forget-input))
  (let* ((keys emacsvox-eat--vim-keys)
         (old (or emacsvox-eat--vim-origin baseline))
         (from (emacsvox-eat--vim-status old)) (to (emacsvox-eat--vim-status screen))
         (previous (if (eq old baseline) from (emacsvox-eat--vim-status baseline)))
         (prior-message (plist-get previous :message))
         (mode (plist-get to :mode)) (prior-mode (plist-get previous :mode))
         (prompt (plist-get to :prompt))
         (command (and keys (not prompt) (emacsvox-eat--vim-submitted-command from keys)))
         (after (emacsvox-eat--vim-point screen))
         ;; Vim can print the help filename before it draws and enters the split.
         (opening-help (and command (string-match-p (rx string-start (or "h" "help") (or blank string-end)) command)
                            after (= (plist-get after :row) (emacsvox-eat--vim-status-index screen))
                            (not (plist-get to :message))))
         (message (or (plist-get to :message)
                      (and command (string-match-p (rx string-start (or "set" "setlocal" "setglobal")
                                                       (+ blank) (+ (or alnum "_")) "?" string-end) command)
                           (string-match-p (rx string-start (* blank) (+ (or alnum "_"))
                                               (optional "=" (* nonl)) string-end) (plist-get to :text))
                           (string-trim (plist-get to :text)))
                      (and after keys (not (or prompt mode opening-help))
                           (emacsvox-eat--vim-destination keys command from to screen after))))
         (submitted (and (memq 'return keys) (not prompt)
                         (or (plist-get from :prompt)
                             (and (memq (car keys) '(?: ?/ ??))
                                  (or message (plist-get to :command) (plist-get to :search))))))
         (before (and keys (emacsvox-eat--vim-point old)))
         (same-display (and before after (equal (plist-get old :size) (plist-get screen :size))
                            (eq (plist-get old :alternate-screen) (plist-get screen :alternate-screen))))
         (compatible (and same-display
                          (equal (plist-get before :window) (plist-get after :window))))
         (announcement
          (cond
           ((and message (not (equal message prior-message))
                 ;; A resize can hide a result above its continuation prompt.
                 (not (and (null keys) (plist-get diff :size-changed) prior-message
                           (equal message (plist-get to :blocking))
                           (string-suffix-p (concat ". " message) prior-message)))
                 (not (and prior-message (string-prefix-p (concat message ". ") prior-message))))
            (if (plist-get to :pager) message (emacsvox-eat--vim-row-text message)))
           ((and (plist-get from :confirmation) (not (plist-get to :confirmation))
                 (memq (car (last keys)) '(?q escape ?y ?n ?a ?l)))
            (if (memq (car (last keys)) '(?q escape)) "Substitution stopped" "Substitution finished"))
           ((and (plist-get to :recording) (not (equal (plist-get to :recording) (plist-get previous :recording))))
            (concat "Recording register " (plist-get to :recording)))
           ((and (plist-get previous :recording) (not (plist-get to :recording))
                 (eq (car (last keys)) ?q) (not (or mode prompt)))
            "Recording stopped")
           ((and mode (not (equal mode prior-mode))) (concat mode " mode"))
           ((and prompt (not (eq prompt (plist-get previous :prompt))))
            (if (= prompt ?:) "Command" (if (= prompt ??) "Search backward" "Search forward")))
           ((and prior-mode (not mode) (not prompt)
                 (or (memq 'escape keys) (memq 3 keys)
                     (and (string-match-p "\\`\\(?:Visual\\|Select\\)" prior-mode)
                          (memq (car (last keys)) '(?v ?V ?y ?d ?x ?p ?P)))))
            "Normal mode")))
         (same-match (and emacsvox-eat--vim-awaiting-match compatible
                          (not (or prompt mode message))
                          (equal (plist-get from :ruler) (plist-get to :ruler))
                          (= (plist-get before :row) (plist-get after :row))
                          (= (plist-get before :column) (plist-get after :column))))
         (feedback (if emacsvox-eat--vim-awaiting-match
                       (when (and same-match (not (string-empty-p (string-trim (plist-get after :line)))))
                         (list 'row (emacsvox-eat--vim-row-text (plist-get after :line))))
                     (or (and same-display (not mode) (not prompt) (not (and announcement message))
                              (emacsvox-eat--vim-window-switch keys before after))
                         (and compatible (not (or (plist-get from :confirmation) (plist-get to :confirmation)))
                              (not (and announcement message))
                              (emacsvox-eat--vim-feedback keys old screen before after from to)))))
         (remaining (cond ((and emacsvox-eat--vim-quitting (not (or message mode))
                                (or prompt (not (plist-get to :ruler)))) keys)
                          ((eq (car feedback) 'match-location) keys)
                          ;; A peer may deliver a separate redraw for each arrow.
                          ((and (memq (car feedback) '(navigation character row))
                                (cdr keys) (emacsvox-eat--vim-word-arrows-p keys))
                           (cdr keys))
                          (feedback (nth 2 feedback))
                          ((or submitted (and announcement message)) (cdr (memq 'return keys)))
                          (announcement (emacsvox-eat--vim-after-entry keys mode prompt)))))
    (cond ((or mode prompt (plist-get to :confirmation) (eq (car feedback) 'echo))
           (setq emacsvox-eat--vim-normal-evidence nil))
          ((or feedback submitted (plist-get to :recording) (equal announcement "Normal mode")
               (equal announcement "Recording stopped"))
           (setq emacsvox-eat--vim-normal-evidence t)))
    (unless (equal mode prior-mode)
      (setq emacsvox-eat--vim-anchor
            (when (and mode after (string-match-p "\\`\\(?:Visual\\|Select\\)" mode))
              (emacsvox-eat--vim-selection-position to after))))
    (when announcement
      (setq emacsvox-eat--last-status-text announcement)
      (when (or automatic keys)
        (emacsvox-eat--vim-say
         (if (and message prior-message (string-prefix-p (concat prior-message ". ") message))
             (substring message (+ 2 (length prior-message))) announcement)
         (if (and (equal mode "Insert") (not prior-mode) compatible
                  (memq (car (emacsvox-eat--vim-command-tail keys)) '(?o ?O))
                  (or (/= (plist-get before :row) (plist-get after :row))
                      (not (equal (plist-get old :rows) (plist-get screen :rows)))))
             'line-created 'status)
         (cond ((and (plist-get to :recording) (not (plist-get previous :recording))) 'open-object)
               ((and (plist-get previous :recording) (not (plist-get to :recording))) 'close-object)
               ((and mode (string-prefix-p "Visual" mode) (not prior-mode)) 'mark-object)))))
    (pcase (car feedback)
      ('file-boundary (emacsvox-eat--vim-present-boundary (nth 1 feedback) screen))
      ('echo (emacsvox-eat--vim-present-echo (nth 1 feedback) after))
      ('match-location
       (setq emacsvox-eat--vim-awaiting-match t)
       (emacsvox-eat--vim-say (nth 1 feedback) 'navigation))
      ('blank-location (emacsvox-eat--vim-blank-row (nth 1 feedback)))
      ('row
       (let* ((row (plist-get after :row)) (text (nth 1 feedback))
              (identity (list 'cursor-row (plist-get screen :generation) row
                              (car (plist-get to :ruler)) (plist-get after :window) text))
              (focus (list :kind 'cursor-row :text text :row-start row :row-end row
                           :column-start (or (car (plist-get after :window)) 0) :confidence 'medium
                           :generation (plist-get screen :generation) :screen-serial emacsvox-eat--update-serial
                           :identity identity)))
         (setq emacsvox-eat--last-likely-focus focus)
         (setf (plist-get diff :likely-focus) focus)
         (unless (equal identity emacsvox-eat--last-focus-presentation-identity)
           (setq emacsvox-eat--last-focus-presentation-identity identity)
           (if (string-blank-p (plist-get after :line)) (emacsvox-eat--vim-blank-row)
             (emacsvox-eat--vim-say text 'navigation)))))
      ('copy (emacsvox-eat--vim-say (nth 1 feedback) 'edit 'mark-object))
      ('indent (emacsvox-eat--vim-say (nth 1 feedback) 'edit 'fill-object))
      ('fold-opened (emacsvox-eat--vim-say (nth 1 feedback) 'navigation 'open-object))
      ('fold-closed (emacsvox-eat--vim-say (nth 1 feedback) 'navigation 'close-object))
      ('mark (emacsvox-eat--vim-say (nth 1 feedback) 'navigation 'mark-object))
      ('jump (emacsvox-eat--vim-say (nth 1 feedback) 'navigation 'large-movement))
      ((or 'navigation 'character 'edit 'deletion 'paste 'line-created 'uppercase 'lowercase 'completion)
       (emacsvox-eat--vim-say (nth 1 feedback) (car feedback))))
    (cond
     (opening-help)
     (remaining
      (setq emacsvox-eat--vim-keys remaining emacsvox-eat--vim-origin screen))
     (emacsvox-eat--vim-quitting (emacsvox-eat--vim-forget-input))
     ((and emacsvox-eat--vim-awaiting-match (not same-match)) (emacsvox-eat--vim-forget-input))
     ((and compatible (not announcement) (not feedback)
           (emacsvox-eat--vim-search-p keys from)
           (not (emacsvox-eat--vim-search-ready-p (plist-get after :line) from to))))
     ((or feedback announcement submitted (and keys (or (not compatible) (not (equal before after)))))
      (emacsvox-eat--vim-forget-input)))))

(provide 'emacsvox-eat-vim)
;;; emacsvox-eat-vim.el ends here
