;;; actual-agent.el --- Check table fixes with recorded live dependencies -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Disposable sessions using the package paths recorded by the investigation.
;; Run in batch or on an isolated graphical frame; no personal init is loaded.
;;; Code:
(require 'cl-lib)
(require 'json)
(require 'ert)
(let* ((root (or (getenv "EMACSVOX_AUDIT_ROOT")
                 (expand-file-name "../../../../" (file-name-directory load-file-name))))
       (output (file-name-as-directory (or (getenv "EMACSVOX_AUDIT_OUTPUT")
                                           (error "Set EMACSVOX_AUDIT_OUTPUT"))))
       (profile (expand-file-name "private-profile/" output))
       (provenance
        (with-temp-buffer
          (insert-file-contents
           (expand-file-name "docs/benchmarks/data/2026-11-15-performance-audit/provenance.json" root))
          (json-parse-buffer :object-type 'alist :array-type 'list)))
       (paths (alist-get 'live_loaded_packages provenance)))
  (make-directory profile t)
  (setq user-emacs-directory profile custom-file (expand-file-name "custom.el" profile)
        package-user-dir (expand-file-name "elpa/" profile) package-directory-list nil
        native-comp-jit-compilation nil load-prefer-newer nil debug-on-error nil
        debug-on-quit nil ring-bell-function #'ignore)
  (dolist (path paths) (add-to-list 'load-path (file-name-directory (cdr path))))
  (dolist (directory '("lisp/" "test/"))
    (add-to-list 'load-path (expand-file-name directory root)))
  (setenv "TTS_PROGRAM" (expand-file-name "servers/log-null" root))
  (setenv "EMACSVOX_AGENT_SHELL_TEST_LOAD" "compiled")
  (load (expand-file-name "lisp/emacsvox-preamble.el" root) nil t t)
  (setq-default emacsvox-speak-messages nil)
  (require 'agent-shell)
  (require 'emacsvox-agent-shell-tests)
  (advice-add 'emacsvox-sounds-play-concrete-cue :override #'ignore)
  (advice-add 'message :after
              (lambda (fmt &rest args)
                (when fmt
                  (with-temp-buffer
                    (insert (apply #'format-message fmt args) "\n")
                    (write-region (point-min) (point-max)
                                  (expand-file-name "actual-agent.log" output) t 'silent)))))
  (let (loaded)
    (dolist (name '(compat acp shell-maker agent-shell))
      (let* ((path (car (cl-loop for entry in load-history
                                 when (member (cons 'provide name) (cdr entry)) collect (car entry))))
             (expected (cdr (assq name paths))))
        (unless (and path (equal (file-truename path) (file-truename expected)))
          (error "Wrong actual dependency for %s: %S; expected %S" name path expected))
        (push (cons name path) loaded)))
    (let ((stats
           (ert-run-tests-batch
            (if noninteractive
                '(member emacsvox-agent-shell-suspended-table-motion-skips-logical-parsing
                         emacsvox-agent-shell-table-on-demand-quit-and-explicit-entry
                         emacsvox-agent-shell-table-adapter-preserves-input
                         emacsvox-agent-shell-table-adapter-rejects-stale-mapping
                         emacsvox-agent-shell-table-entry-has-one-navigation-submission
                         emacsvox-agent-shell-table-entry-is-directional-in-both-views)
              '(member emacsvox-agent-shell-suspended-table-motion-skips-logical-parsing
                       emacsvox-agent-shell-table-graphical-wrapped-navigation)))))
      (with-temp-file (expand-file-name "actual-agent.eld" output)
        (prin1 (list :emacs emacs-version :agent-version agent-shell--version
                     :loaded loaded :graphical (display-graphic-p)
                     :implementation (symbol-file 'emacsvox-agent-shell--table-navigation-post-command)
                     :total (ert-stats-total stats) :unexpected (ert-stats-completed-unexpected stats)
                     :skipped (ert-stats-skipped stats)) (current-buffer)))
      (kill-emacs (if (and (zerop (ert-stats-completed-unexpected stats))
                          (zerop (ert-stats-skipped stats))) 0 1)))))
;;; actual-agent.el ends here
