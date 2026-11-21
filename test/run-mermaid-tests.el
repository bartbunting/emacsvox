;;; run-mermaid-tests.el --- Optional Mermaid prototype gate -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Exercise the real Node helper with speech captured, in a fresh Emacs.
;; Compiled mode verifies the actual loaded module path as well.

;;; Code:

(require 'ert)
(when (version< emacs-version "30.2") (error "Emacsvox requires Emacs 30.2 or newer"))
(let* ((root (expand-file-name "../" (file-name-directory load-file-name)))
       (compiled (equal (getenv "EMACSVOX_MERMAID_TEST_LOAD") "compiled"))
       (module (expand-file-name
                (concat "lisp/integrations/emacsvox-mermaid." (if compiled "elc" "el")) root)))
  (add-to-list 'load-path (expand-file-name "lisp/" root))
  (setq load-prefer-newer (not compiled))
  (require 'emacsvox-preamble)
  (load module nil nil t)
  (unless (equal (file-truename module) (file-truename (symbol-file 'emacsvox-mermaid-explore)))
    (error "Mermaid tests loaded the wrong module"))
  (message "Mermaid test module: %s; Emacs %s" module emacs-version)
  (load (expand-file-name "test/emacsvox-mermaid-tests.el" root) nil nil t))
(add-hook 'kill-emacs-hook (lambda () (emacsvox-mermaid--fail "Test session finished")))
(ert-run-tests-batch-and-exit)

;;; run-mermaid-tests.el ends here
