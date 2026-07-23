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
     :point 6))
  "Core scenarios used for Emacsvox and Emacspeak trace comparison.")

(provide 'emacsvox-core-scenarios)
;;; emacsvox-core-scenarios.el ends here
