;;; run-compiled-aural-tests.el --- Verify compiled aural parity -*- lexical-binding: t; -*-

;;; Commentary:

;; Compile the runtime extension boundary and its principal callers into an
;; isolated directory, then verify them in a clean child Emacs.  No byte-code
;; is written into the source tree.

;;; Code:

(require 'bytecomp)
(require 'subr-x)

(let* ((test-directory
        (file-name-directory (or load-file-name buffer-file-name)))
       (root-directory (expand-file-name "../" test-directory))
       (lisp-directory (expand-file-name "lisp/" root-directory))
       (build-directory (make-temp-file "emacsvox-compiled-aural-" t))
       (files
        '("tts-speak.el" "emacsvox-aural-tools.el" "emacsvox-keymap.el"))
       (byte-compile-dest-file-function
        (lambda (source)
          (expand-file-name
           (concat (file-name-base source) ".elc")
           build-directory)))
       (child-program
        (expand-file-name invocation-name invocation-directory))
       (verify-file
        (expand-file-name "verify-compiled-aural.el" test-directory)))
  (unwind-protect
      (progn
        (add-to-list 'load-path lisp-directory)
        (setq load-prefer-newer t)
        (dolist (file files)
          (let ((source (expand-file-name file lisp-directory)))
            (unless (byte-compile-file source)
              (error "Could not byte-compile %s" source))))
        (let ((process-environment (copy-sequence process-environment))
              (output (get-buffer-create " *compiled-aural-child*")))
          (setenv "EMACSVOX_COMPILED_AURAL_DIR" build-directory)
          (setenv "EMACSVOX_COMPILED_AURAL_ROOT" root-directory)
          (with-current-buffer output (erase-buffer))
          (let ((status
                 (call-process
                  child-program nil (list output t) nil
                  "-Q" "--batch" "-l" verify-file)))
            (unless (zerop status)
              (princ (with-current-buffer output (buffer-string)))
              (error "Compiled aural verification failed")))))
    (delete-directory build-directory t)))

(princ "Compiled aural parity checks passed\n")

;;; run-compiled-aural-tests.el ends here
