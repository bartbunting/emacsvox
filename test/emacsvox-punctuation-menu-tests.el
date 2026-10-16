;;; emacsvox-punctuation-menu-tests.el --- Linked punctuation editor tests -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Exercise real menu suspension with a host fixture and retained editor drafts.
;;; Code:
(require 'emacsvox-capitalization-tests)
(require 'omnivox-punctuation-tests)

(ert-deftest emacsvox-punctuation-menu-draft-and-return ()
  "Opening, help, return, and reopening keep the draft and never restart or save."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (emacsvox-test--with-capitalization
      (let ((transient--prefix nil) (transient--stack nil) (transient-show-menu t)
            (requests nil) (restarts 0))
        (switch-to-buffer source)
        (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
        (cl-letf (((symbol-function 'omnivox-punctuation--request)
                   (lambda (command)
                     (push command requests)
                     (omnivox-punctuation-tests--review)))
                  ((symbol-function 'tts-restart) (lambda () (cl-incf restarts))))
          (unwind-protect
              (progn
                (execute-kbd-macro (kbd "<f8> s p e"))
                (should (derived-mode-p 'omnivox-punctuation-mode))
                (omnivox-punctuation--change "’" "Speak a name" "curly quote")
                (let ((row (tabulated-list-get-id)))
                  (execute-kbd-macro (kbd "? q"))
                  (should (derived-mode-p 'omnivox-punctuation-mode))
                  (should (equal row (tabulated-list-get-id))))
                (execute-kbd-macro (kbd "q"))
                (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-punctuation))
                (with-selected-window transient--window
                  (should (eq (oref (button-get (button-at (point)) 'button-data) command)
                              'emacsvox-aural-menu--pronunciations)))
                (execute-kbd-macro (kbd "e"))
                (should (equal (omnivox-punctuation--value "’") "curly quote"))
                (should (omnivox-punctuation--dirty-p))
                (execute-kbd-macro (kbd "q q q q"))
                (should (eq (current-buffer) source))
                (should (= (point) 3))
                (should (equal requests '((:command "punctuation-review"))))
                (should (zerop restarts))
                (should-not (file-exists-p custom-file)))
            (when transient--prefix (execute-kbd-macro (kbd "C-q")))
            (when-let* ((buffer (get-buffer "*Omnivox Punctuation*")))
              (with-current-buffer buffer (setq kill-buffer-query-functions nil))
              (kill-buffer buffer))))))))

(ert-deftest emacsvox-punctuation-menu-direct-reopen-updates-parent ()
  "Direct entry resumes drafts and returns to its latest parent, not an old menu."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (emacsvox-test--with-capitalization
      (cl-letf (((symbol-function 'omnivox-punctuation--request)
                 (lambda (&rest _) (omnivox-punctuation-tests--review))))
        (unwind-protect
            (progn
              (switch-to-buffer source)
              (omnivox-punctuation)
              (setq-local emacsvox-aural-ui--return-function (lambda () (error "Stale callback")))
              (switch-to-buffer source)
              (omnivox-punctuation)
              (should-not emacsvox-aural-ui--return-function)
              (omnivox-punctuation-quit)
              (should (eq (current-buffer) source)))
          (when-let* ((buffer (get-buffer "*Omnivox Punctuation*")))
            (with-current-buffer buffer (setq kill-buffer-query-functions nil))
            (kill-buffer buffer)))))))
(provide 'emacsvox-punctuation-menu-tests)
;;; emacsvox-punctuation-menu-tests.el ends here
