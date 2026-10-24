;;; emacsvox-agent-shell-output-tests.el --- Patched Codex output checks -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Supplemental regression for Agent Shell's terminal-output-delta patch.
;; Load the patched Agent Shell before this suite, with its dependencies on
;; load-path, then run in a fresh graphical Emacs.  The pinned upstream commit
;; does not contain that patch yet; the ordinary integration gate therefore
;; does not load this file.  No substitute renderer is installed by the test.
;; See test/README.org for the required testing route.

;;; Code:

(require 'emacsvox-agent-shell-tests)

(ert-deftest emacsvox-agent-shell-streamed-output-graphical-reading ()
  "Read streamed output after expansion and announce the completed result."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (emacsvox-agent-shell-test--with-current-session
      (switch-to-buffer (current-buffer))
      (use-local-map agent-shell-mode-map)
      (let ((emacsvox-agent-shell-tool-output-verbosity 'full)
            (agent-shell-tool-use-expand-by-default nil)
            (agent-shell-activity-group-expand-by-default t)
            spoken)
        (cl-letf (((symbol-function 'emacsvox-aural-submit)
                   (lambda (text &rest args) (push (cons text args) spoken))))
          (dolist (update
                   '(((status . "in_progress") (title . "Run tests")
                      (rawInput (command . "printf result"))
                      (_meta (terminal_output_delta (data . "First result\n"))))
                     ((status . "completed")
                      (_meta (terminal_output_delta (data . "Last result\n"))
                             (terminal_exit (exit_code . 0))))
                     ((status . "completed"))))
            (agent-shell--on-notification
             :state agent-shell--state
             :acp-notification
             `((method . "session/update")
               (params (update (sessionUpdate . "tool_call_update")
                               (toolCallId . "delta-command") ,@update)))))
          (let ((results
                 (seq-filter
                  (lambda (entry) (string-search "Last result" (car entry)))
                  spoken)))
            (should (= 1 (length results)))
            (should (string-search "First result" (caar results)))
            (should (eq 'notification (plist-get (cdar results) :lane))))
          (goto-char (point-min))
          (search-forward "First result")
          (let* ((output (match-beginning 0))
                 (block (agent-shell-ui--block-range :position output)))
            (should (invisible-p output))
            (goto-char (map-elt block :start))
            (call-interactively (key-binding (kbd "RET")))
            (should-not (invisible-p output))
            (redisplay t)
            (should (pos-visible-in-window-p output))
            (goto-char output)
            (let ((events (emacsvox-agent-shell-test--capture-events
                            (call-interactively #'next-line))))
              (should
               (seq-some (lambda (event)
                           (and (eq (car event) 'speak)
                                (string-search "Last result" (cadr event))))
                         events)))))))))

(provide 'emacsvox-agent-shell-output-tests)

;;; emacsvox-agent-shell-output-tests.el ends here
