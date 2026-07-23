;;; emacsvox-core-scenarios.el --- Core trace scenarios -*- lexical-binding: t; -*-

;;; Commentary:

;; Data-only scenarios shared by Emacsvox and the pinned Emacspeak reference.

;;; Code:

(defconst emacsvox-trace-core-scenarios
  '((:name forward-char
     :command forward-char
     :arguments (1)
     :interactive t
     :text "alpha beta\n"
     :point 1)
    (:name backward-char
     :command backward-char
     :arguments (1)
     :interactive t
     :text "alpha beta\n"
     :point 2)
    (:name next-line
     :command next-line
     :arguments (1)
     :interactive t
     :text "first\nsecond\n"
     :point 1)
    (:name previous-line
     :command previous-line
     :arguments (1)
     :interactive t
     :text "first\nsecond\n"
     :point 7)
    (:name beginning-of-buffer
     :command beginning-of-buffer
     :interactive t
     :text "first\nsecond\n"
     :point 9)
    (:name end-of-buffer
     :command end-of-buffer
     :interactive t
     :text "first\nsecond\n"
     :point 1)
    (:name delete-forward-char
     :command delete-forward-char
     :arguments (1)
     :interactive t
     :text "abc"
     :point 1)
    (:name kill-word
     :command kill-word
     :arguments (1)
     :interactive t
     :text "alpha beta"
     :point 1)
    (:name kill-ring-save
     :command kill-ring-save
     :arguments (1 6)
     :interactive t
     :text "alpha beta"
     :point 1
     :mark 6
     :mark-active t)
    (:name newline
     :command newline
     :arguments (1)
     :interactive t
     :text "alpha beta"
     :point 6)
    (:name beginning-of-visual-line
     :command beginning-of-visual-line
     :arguments (1)
     :interactive t
     :text "alpha beta\n"
     :point 7)
    (:name next-logical-line
     :command next-logical-line
     :arguments (1)
     :interactive t
     :text "first\nsecond\n"
     :point 1)
    (:name forward-word
     :command forward-word
     :arguments (1)
     :interactive t
     :text "alpha beta"
     :point 1)
    (:name backward-word
     :command backward-word
     :arguments (1)
     :interactive t
     :text "alpha beta"
     :point 11)
    (:name back-to-indentation
     :command back-to-indentation
     :interactive t
     :text "  alpha\n"
     :point 7)
    (:name forward-sentence
     :command forward-sentence
     :arguments (1)
     :interactive t
     :text "First sentence.  Second sentence.  Third sentence."
     :point 1)
    (:name forward-paragraph
     :command forward-paragraph
     :arguments (1)
     :interactive t
     :text "First paragraph.\n\nSecond paragraph.\n\nThird paragraph.\n"
     :point 1)
    (:name forward-list
     :command forward-list
     :arguments (1)
     :interactive t
     :mode emacs-lisp-mode
     :text "(one) (two)"
     :point 1)
    (:name forward-page
     :command forward-page
     :arguments (1)
     :interactive t
     :text "first page\n\fsecond page\n\fthird page\n"
     :point 1)
    (:name forward-sexp
     :command forward-sexp
     :arguments (1)
     :interactive t
     :mode emacs-lisp-mode
     :text "(one) (two)"
     :point 1))
  "Core scenarios used for Emacsvox and Emacspeak trace comparison.")

(provide 'emacsvox-core-scenarios)
;;; emacsvox-core-scenarios.el ends here
