;;; run-scenarios.el --- Run semantic speech scenarios -*- lexical-binding: t; -*-

;;; Commentary:

;; Batch entry point for recording core traces from either Emacsvox or a pinned
;; Emacspeak checkout.  Configuration is supplied through environment variables:
;;
;; EMACSVOX_TRACE_IMPLEMENTATION  emacsvox or emacspeak
;; EMACSVOX_TRACE_ROOT            checkout root
;; EMACSVOX_TRACE_OUTPUT          optional output file
;; EMACSVOX_TRACE_EXPECTED        optional expected trace file

;;; Code:

(require 'cl-lib)
(require 'pp)

(defconst emacsvox-trace-runner-directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory containing the trace runner.")

(defconst emacsvox-trace-emacspeak-reference
  "7482f8e2713b5b8ea87132d9d2fcea6664ff4037"
  "Pinned original Emacspeak revision used for reference traces.")

(add-to-list 'load-path emacsvox-trace-runner-directory)
(add-to-list
 'load-path (expand-file-name "scenarios/" emacsvox-trace-runner-directory))

(require 'emacsvox-trace)
(require 'emacsvox-core-scenarios)

(defun emacsvox-trace--required-environment (name)
  "Return environment variable NAME or signal a useful error."
  (or (getenv name) (error "Environment variable %s is required" name)))

(defun emacsvox-trace--load-source (root basename)
  "Load Lisp file BASENAME from the checkout at ROOT."
  (load (expand-file-name (format "lisp/%s.el" basename) root) nil nil))

(defun emacsvox-trace--git-revision (root)
  "Return the Git revision checked out at ROOT."
  (with-temp-buffer
    (let ((status
           (call-process
            "git" nil (current-buffer) nil "-C" root "rev-parse" "HEAD")))
      (unless (and (integerp status) (zerop status))
        (error "Could not determine Git revision for %s" root))
      (string-trim (buffer-string)))))

(defun emacsvox-trace--verify-emacspeak-reference (root)
  "Verify that ROOT is the pinned original Emacspeak checkout."
  (let ((actual (emacsvox-trace--git-revision root)))
    (unless (string= actual emacsvox-trace-emacspeak-reference)
      (error
       "Emacspeak reference is %s; expected %s"
       actual emacsvox-trace-emacspeak-reference)))
  (with-temp-buffer
    (let ((status
           (call-process
            "git" nil (current-buffer) nil
            "-C" root "status" "--porcelain" "--untracked-files=all")))
      (unless (and (integerp status) (zerop status))
        (error "Could not inspect Emacspeak reference worktree"))
      (unless (string-empty-p (buffer-string))
        (error "Pinned Emacspeak reference worktree is not clean"))))
  (when
      (directory-files-recursively
       (expand-file-name "lisp/" root) (rx ".elc" string-end))
    (error "Pinned Emacspeak reference contains compiled Lisp files")))

(defun emacsvox-trace--load-implementation (implementation root)
  "Load IMPLEMENTATION from ROOT without starting a speech server."
  (let ((lisp-directory (expand-file-name "lisp/" root))
        (load-prefer-newer t))
    (unless (file-directory-p lisp-directory)
      (error "No lisp directory under %s" root))
    (add-to-list 'load-path lisp-directory)
    ;; Match the physical-line movement configured by normal startup.
    (setq-default line-move-visual nil)
    (pcase implementation
      ("emacsvox"
       (emacsvox-trace--load-source root "emacsvox-preamble")
       (emacsvox-trace--load-source root "emacsvox-speak")
       (emacsvox-trace--load-source root "emacsvox-advice")
       (setq-default emacsvox-use-icons t)
       (setq-default emacsvox-speak-messages t))
      ("emacspeak"
       (emacsvox-trace--verify-emacspeak-reference root)
       (emacsvox-trace--load-source root "emacspeak-preamble")
       (emacsvox-trace--load-source root "emacspeak-speak")
       (emacsvox-trace--load-source root "emacspeak-advice")
       (setq-default emacspeak-use-icons t)
       (setq-default emacspeak-speak-messages t))
      (_ (error "Unknown trace implementation: %s" implementation)))))

(defun emacsvox-trace--read-file (filename)
  "Read and return the first Lisp value in FILENAME."
  (with-temp-buffer
    (insert-file-contents filename)
    (goto-char (point-min))
    (read (current-buffer))))

(defun emacsvox-trace--write-file (filename value)
  "Pretty-print VALUE to FILENAME."
  (with-temp-file filename
    (let ((print-length nil)
          (print-level nil))
      (pp value (current-buffer)))))

(let* ((implementation
        (emacsvox-trace--required-environment
         "EMACSVOX_TRACE_IMPLEMENTATION"))
       (root
        (file-name-as-directory
         (expand-file-name
          (emacsvox-trace--required-environment "EMACSVOX_TRACE_ROOT"))))
       (output (getenv "EMACSVOX_TRACE_OUTPUT"))
       (expected-file (getenv "EMACSVOX_TRACE_EXPECTED")))
  (emacsvox-trace--load-implementation implementation root)
  (let ((results
         (mapcar
          (lambda (scenario)
            (apply #'emacsvox-trace-run-scenario scenario))
          emacsvox-trace-core-scenarios)))
    (when expected-file
      (let ((expected (emacsvox-trace--read-file expected-file)))
        (unless (equal results expected)
          (princ "Semantic trace does not match expected output.\n")
          (princ "Actual trace follows:\n")
          (pp results)
          (kill-emacs 1))))
    (cond
     (output (emacsvox-trace--write-file output results))
     (expected-file
      (message "All %d %s semantic traces match."
               (length results) implementation))
     (t (pp results)))))

;;; run-scenarios.el ends here
