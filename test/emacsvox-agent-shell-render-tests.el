;;; emacsvox-agent-shell-render-tests.el --- Renderer contracts -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Exercise renderer interpretation without optional packages or speech setup.
;; Set EMACSVOX_AGENT_SHELL_TEST_LOAD=compiled after make bytecode-check to
;; exercise the same contracts against the exact compiled module.

;;; Code:

(require 'cl-lib)
(require 'ert)

(defconst emacsvox-agent-shell-render-test--file
  (expand-file-name
   (pcase (or (getenv "EMACSVOX_AGENT_SHELL_TEST_LOAD") "source")
     ("source" "../lisp/emacsvox-agent-shell-render.el")
     ("compiled" "../lisp/emacsvox-agent-shell-render.elc")
     (kind (error "Unknown Agent Shell test load kind: %s" kind)))
   (file-name-directory (or load-file-name buffer-file-name))))

(load emacsvox-agent-shell-render-test--file nil nil t)
(unless (equal (file-truename emacsvox-agent-shell-render-test--file)
               (file-truename
                (symbol-file 'emacsvox-agent-shell--semantic-block-type 'defun)))
  (error "Renderer tests loaded the wrong implementation"))

(ert-deftest emacsvox-agent-shell-render-load-is-independent ()
  "A fresh renderer load needs no integration, registrations, or speech."
  (with-temp-buffer
    (let ((status
           (call-process
            (expand-file-name invocation-name invocation-directory) nil t nil
            "-Q" "--batch" "--eval"
            (prin1-to-string
             `(progn
                ;; Rebinding primitives must not generate native trampolines
                ;; or background compiler work inside the guarded fixture.
                (setq native-comp-enable-subr-trampolines nil
                      native-comp-jit-compilation nil)
                ;; Preload the declared Emacs facilities before guarding the
                ;; integration's own load effects.
                (require 'cl-lib) (require 'map)
                (require 'seq) (require 'subr-x)
                (cl-letf (((symbol-function 'add-hook)
                           (lambda (&rest _) (error "Renderer added a hook")))
                          ((symbol-function 'advice-add)
                           (lambda (&rest _) (error "Renderer added advice")))
                          ((symbol-function 'make-process)
                           (lambda (&rest _) (error "Renderer started a process")))
                          ((symbol-function 'start-process)
                           (lambda (&rest _) (error "Renderer started a process")))
                          ((symbol-function 'make-thread)
                           (lambda (&rest _) (error "Renderer started a thread")))
                          ((symbol-function 'run-at-time)
                           (lambda (&rest _) (error "Renderer started a timer")))
                          ((symbol-function 'run-with-idle-timer)
                           (lambda (&rest _) (error "Renderer started a timer"))))
                  (load ,emacsvox-agent-shell-render-test--file nil nil t))
                (unless (featurep 'emacsvox-agent-shell-render)
                  (error "Renderer did not load"))
                (dolist (feature '(agent-shell shell-maker emacsvox-agent-shell
                                  emacsvox-preamble emacsvox-aural-transport
                                  tts-speak))
                  (when (featurep feature)
                    (error "Renderer loaded integration dependency %s" feature))))))))
      (unless (eq status 0) (ert-fail (buffer-string))))))

(ert-deftest emacsvox-agent-shell-render-copy-preserves-aural-properties ()
  "Legacy clipboard removal preserves source and speech display properties."
  (let* ((current (propertize "Heading" 'face 'agent-shell-markdown-header-1
                              'personality 'voice-brighten))
         (legacy (copy-sequence current))
         (handler (list (lambda (&rest _) (ert-fail "Clipboard handler ran")))))
    (put-text-property 0 (length legacy) 'yank-handler handler legacy)
    (let* ((before (copy-sequence legacy))
           (copy (emacsvox-agent-shell--speech-copy-without-yank-handler legacy)))
      (should (equal-including-properties copy current))
      (should (equal-including-properties legacy before))
      (should (eq (emacsvox-agent-shell--speech-copy-without-yank-handler current)
                  current)))))

(ert-deftest emacsvox-agent-shell-render-status-needs-authenticating-face ()
  "Current and legacy glyphs need matching faces to carry semantic status."
  (dolist (fixture '(("◔" agent-shell-pending pending)
                     ("…" agent-shell-pending pending)
                     ("◔" agent-shell-warning in-progress)
                     ("…" agent-shell-warning in-progress)
                     ("✓" agent-shell-success completed)
                     ("✗" agent-shell-error failed)))
    (pcase-let ((`(,glyph ,face ,expected) fixture))
      (dolist (property '(face font-lock-face))
        (let* ((text (propertize glyph property (list 'bold (list face))))
               (before (copy-sequence text)))
          (should (eq (emacsvox-agent-shell--status-at text 0) expected))
          (should (equal-including-properties text before))))
      (should-not (emacsvox-agent-shell--status-at glyph 0))
      (should-not (emacsvox-agent-shell--status-at
                   (propertize glyph 'face 'bold) 0)))))

(ert-deftest emacsvox-agent-shell-render-prompt-removal-preserves-content ()
  "Strip only faced prompts, retaining content properties and source text."
  (dolist (face '(agent-shell-prompt comint-highlight-prompt))
    (dolist (property '(face font-lock-face))
      (let* ((body (propertize "hello" 'personality 'voice-bolden))
             (text (concat " \t" (propertize "> " property (list face)) body))
             (before (copy-sequence text)))
        (should (equal-including-properties
                 (emacsvox-agent-shell--without-leading-chat-prompt text) body))
        (should (equal-including-properties text before)))))
  (let ((text "  > Ordinary prose"))
    (should (eq (emacsvox-agent-shell--without-leading-chat-prompt text) text))))

(ert-deftest emacsvox-agent-shell-render-chat-label-ignores-syntax-table ()
  "Parse display lines with properties even when newline has comment syntax."
  (with-temp-buffer
    (set-syntax-table (copy-syntax-table))
    (modify-syntax-entry ?\n ">")
    (let* ((label (propertize "Me" 'face 'agent-shell-chat-me-label))
           (text (concat "\n  " label " \r\n > "))
           (before (copy-sequence text))
           (result (emacsvox-agent-shell--chat-label-rendering text)))
      (should (equal-including-properties (car result) label))
      (should (cdr result))
      (should-not (cdr (emacsvox-agent-shell--chat-label-rendering
                        (concat label "\n \t"))))
      (should-not (emacsvox-agent-shell--chat-label-rendering "\n \t"))
      (should (equal-including-properties text before)))))

(ert-deftest emacsvox-agent-shell-render-chrome-filter-preserves-source ()
  "Remove property-scoped controls while retaining meaningful faced text."
  (let* ((heading (propertize "Thinking" 'face 'agent-shell-section-heading))
         (label (concat "✶ " heading))
         (state '(:qualified-id "1-agent_thought_chunk"))
         (text
          (concat (propertize "▶ " 'agent-shell-ui-section 'indicator)
                  (propertize label 'agent-shell-ui-section 'label-left
                              'agent-shell-ui-state state)
                  "\n" (propertize "⧉" 'agent-shell-markdown-source-block-copy t)
                  " code ▶ ✶"))
         (before (copy-sequence text))
         (spoken (emacsvox-agent-shell--remove-visual-chrome-for-speech text)))
    (should (equal (substring-no-properties spoken) "Thinking\n code ▶ ✶"))
    (should (eq (get-text-property 0 'face spoken) 'agent-shell-section-heading))
    (should (equal-including-properties text before)))
  (let ((text "▶ ✶ Thinking ⧉"))
    (should (eq (emacsvox-agent-shell--remove-visual-chrome-for-speech text) text))))

(ert-deftest emacsvox-agent-shell-render-group-provenance-beats-tool-id ()
  "A thought-shaped tool ID needs renderer styling, in strings and buffers."
  (let* ((id "turn-agent_thought_chunk")
         (state (list :qualified-id id :group-id "activity"))
         (text (propertize "Reasoning" 'agent-shell-ui-state state)))
    (should (eq (emacsvox-agent-shell--semantic-block-type id state 0 text)
                'tool-call))
    (put-text-property 0 (length text) 'face 'agent-shell-thought-body text)
    (let ((before (copy-sequence text)))
      (should (eq (emacsvox-agent-shell--semantic-block-type id state 0 text)
                  'thought))
      (should (eq (emacsvox-agent-shell--semantic-block-type
                   id (list :kind 'group) 0 text) 'activity-group))
      (should (equal-including-properties text before)))
    (with-temp-buffer
      (insert text)
      (goto-char 3)
      (let ((before (buffer-string))
            (tick (buffer-chars-modified-tick)))
        (should (eq (emacsvox-agent-shell--semantic-block-type id state 3) 'thought))
        (should (= (point) 3))
        (should (= tick (buffer-chars-modified-tick)))
        (should (equal-including-properties before (buffer-string)))))))

(ert-deftest emacsvox-agent-shell-render-answer-selection-keeps-order-and-faces ()
  "Select answer bodies only; use plain fallback only without semantic data."
  (cl-labels ((fragment (id body)
                (propertize body 'agent-shell-ui-state (list :qualified-id id)
                            'agent-shell-ui-section 'body)))
    (let* ((first (fragment "1-agent_message_chunk"
                            (propertize " First " 'face 'bold)))
           (thought (fragment "2-agent_thought_chunk" "Hidden reasoning"))
           (last (fragment "3-agent_message_chunk" "Second"))
           (text (concat first thought last))
           (before (copy-sequence text))
           (answer (emacsvox-agent-shell--agent-answer-from-response text)))
      (should (equal (substring-no-properties answer) "First\nSecond"))
      (should (eq (get-text-property 0 'face answer) 'bold))
      (should (equal-including-properties text before))
      (should-not (emacsvox-agent-shell--agent-answer-from-response thought)))
    (should (equal (emacsvox-agent-shell--agent-answer-from-response " Plain \n")
                   "Plain"))
    (should-not (emacsvox-agent-shell--agent-answer-from-response " \n"))))

(provide 'emacsvox-agent-shell-render-tests)
;;; emacsvox-agent-shell-render-tests.el ends here
