;;; emacsvox-ocr-tests.el --- OCR front-end tests -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:

;; Verify the PaddleOCR default and asynchronous image/PDF adapter boundary.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-ocr)

(defun emacsvox-ocr-tests--write-executable (file contents)
  "Write executable FILE containing CONTENTS and return FILE."
  (with-temp-file file
    (insert contents))
  (set-file-modes file #o700)
  file)

(defun emacsvox-ocr-tests--wait-for-process ()
  "Wait for the OCR process in the current buffer to finish."
  (let ((deadline (+ (float-time) 10))
        (process emacsvox-ocr-process))
    (while (and emacsvox-ocr-process
                (< (float-time) deadline))
      ;; Passing nil also drains the separate stderr process and reliably
      ;; dispatches the main process sentinel in batch Emacs.
      (accept-process-output nil 0.1))
    (should-not
     (and emacsvox-ocr-process
          (list (process-status process)
                (process-exit-status process))))))

(ert-deftest emacsvox-ocr-defaults-to-the-paddleocr-adapter ()
  "A new OCR setup should use the repository PaddleOCR launcher."
  (should
   (equal emacsvox-ocr-engine
          emacsvox-ocr-paddleocr-engine)))

(ert-deftest emacsvox-ocr-paddleocr-defaults-are-typed-arguments ()
  "The bundled adapter should receive normal settings without raw options."
  (let ((emacsvox-ocr-engine emacsvox-ocr-paddleocr-engine)
        (emacsvox-ocr-engine-options nil)
        (emacsvox-ocr-paddleocr-language "en")
        (emacsvox-ocr-paddleocr-device "cpu")
        (emacsvox-ocr-paddleocr-use-document-orientation t)
        (emacsvox-ocr-paddleocr-use-document-unwarping t)
        (emacsvox-ocr-paddleocr-use-text-line-orientation t)
        (emacsvox-ocr-paddleocr-use-table-recognition t)
        (emacsvox-ocr-paddleocr-use-formula-recognition t)
        (emacsvox-ocr-paddleocr-enable-mkldnn nil))
    (should
     (equal
      (emacsvox-ocr--engine-command "/tmp/page.png")
      (list emacsvox-ocr-paddleocr-engine "/tmp/page.png"
            "--lang" "en" "--device" "cpu")))))

(ert-deftest emacsvox-ocr-paddleocr-custom-options-map-to-switches ()
  "Typed customization should cover every bundled adapter feature switch."
  (let ((emacsvox-ocr-engine emacsvox-ocr-paddleocr-engine)
        (emacsvox-ocr-engine-options '("--lang" "fr"))
        (emacsvox-ocr-paddleocr-language "en")
        (emacsvox-ocr-paddleocr-device "gpu:0")
        (emacsvox-ocr-paddleocr-use-document-orientation nil)
        (emacsvox-ocr-paddleocr-use-document-unwarping nil)
        (emacsvox-ocr-paddleocr-use-text-line-orientation nil)
        (emacsvox-ocr-paddleocr-use-table-recognition nil)
        (emacsvox-ocr-paddleocr-use-formula-recognition nil)
        (emacsvox-ocr-paddleocr-enable-mkldnn t))
    (should
     (equal
      (emacsvox-ocr--engine-command "/tmp/document.pdf")
      (list emacsvox-ocr-paddleocr-engine "/tmp/document.pdf"
            "--lang" "en" "--device" "gpu:0"
            "--no-doc-orientation" "--no-doc-unwarping"
            "--no-textline-orientation" "--no-tables" "--no-formulas"
            "--enable-mkldnn" "--lang" "fr")))))

(ert-deftest emacsvox-ocr-paddleocr-python-is-process-local ()
  "The Python option should affect PaddleOCR without changing global state."
  (let ((emacsvox-ocr-engine emacsvox-ocr-paddleocr-engine)
        (emacsvox-ocr-paddleocr-python "/opt/paddle env/bin/python")
        (process-environment
         '("KEEP=this" "EMACSVOX_PADDLEOCR_PYTHON=/old/python")))
    (let ((environment (emacsvox-ocr--engine-process-environment)))
      (should (member "KEEP=this" environment))
      (should
       (member
        "EMACSVOX_PADDLEOCR_PYTHON=/opt/paddle env/bin/python"
        environment))
      (should
       (equal (getenv "EMACSVOX_PADDLEOCR_PYTHON") "/old/python")))))

(ert-deftest emacsvox-ocr-alternative-engine-keeps-generic-options ()
  "Paddle-specific options should not leak into another OCR engine."
  (let ((emacsvox-ocr-engine "/opt/other-ocr")
        (emacsvox-ocr-engine-options '("--format" "text"))
        (emacsvox-ocr-paddleocr-python "/opt/paddle/bin/python")
        (process-environment '("KEEP=this")))
    (should
     (equal
      (emacsvox-ocr--engine-command "/tmp/input.pdf")
      '("/opt/other-ocr" "/tmp/input.pdf" "--format" "text")))
    (should
     (equal (emacsvox-ocr--engine-process-environment) '("KEEP=this")))))

(ert-deftest emacsvox-ocr-page-position-vector-grows ()
  "Documents should not fail after the initial page-vector capacity."
  (with-temp-buffer
    (emacsvox-ocr-mode)
    (emacsvox-ocr--ensure-page-capacity 80)
    (should (> (length emacsvox-ocr-page-positions) 80))))

(defun emacsvox-ocr-tests--with-scanner (scanner-body compressor-body function)
  "Run FUNCTION in an OCR buffer with private fake acquisition programs."
  (unless (and (not (eq system-type 'windows-nt)) (executable-find "sh"))
    (ert-skip "Scanner fixtures require a POSIX shell"))
  (let* ((directory (make-temp-file "emacsvox scan 'fixture' " t))
         (scanner (expand-file-name "scanner with spaces" directory))
         (compressor (expand-file-name "compressor with spaces" directory))
         (errors (generate-new-buffer " *OCR acquisition errors*")))
    (unwind-protect
        (progn
          (emacsvox-ocr-tests--write-executable scanner (concat "#!/bin/sh\n" scanner-body))
          (when compressor-body
            (emacsvox-ocr-tests--write-executable
             compressor (concat "#!/bin/sh\n" compressor-body)))
          (with-temp-buffer
            (emacsvox-ocr-mode)
            (setq default-directory (file-name-as-directory directory)
                  emacsvox-ocr-document-name "a book's;$cash")
            (let ((noninteractive nil)
                  (emacsvox-ocr-scan-image scanner)
                  (emacsvox-ocr-scan-image-options "")
                  (emacsvox-ocr-compress-image (and compressor-body compressor))
                  (emacsvox-ocr-compress-image-options "")
                  (emacsvox-ocr-error-buffer (buffer-name errors)))
              (funcall function directory))))
      (kill-buffer errors)
      (delete-directory directory t))))

(ert-deftest emacsvox-ocr-scan-keeps-the-requested-original ()
  "Keep enabled retains the acquired bytes, while disabled removes staging."
  (dolist (keep '(nil t))
    (emacsvox-ocr-tests--with-scanner
     "printf 'original bytes\\n'\n"
     "printf 'compressed bytes\\n' > \"$2\"\n"
     (lambda (directory)
       (let* ((emacsvox-ocr-keep-uncompressed-image keep)
              (image (expand-file-name "a book's;$cash-p1.tif" directory))
              (original (expand-file-name "a book's;$cash-p1-uncompressed.tif" directory))
              (unrelated (expand-file-name "temp.tif" directory)))
         (with-temp-file unrelated (insert "another operation"))
         (call-interactively #'emacsvox-ocr-scan-image)
         (should (= emacsvox-ocr-last-page-number 1))
         (with-temp-buffer
           (insert-file-contents image)
           (should (equal (buffer-string) "compressed bytes\n")))
         (should (eq (file-exists-p original) keep))
         (when keep
           (with-temp-buffer
             (insert-file-contents original)
             (should (equal (buffer-string) "original bytes\n"))))
         (with-temp-buffer
           (insert-file-contents unrelated)
           (should (equal (buffer-string) "another operation")))
         (should-not (directory-files directory nil "^\\.emacsvox-scan-")))))))

(ert-deftest emacsvox-ocr-scan-without-compression-preserves-programmatic-count ()
  "Scan-and-recognize can acquire its input without advancing OCR's page."
  (emacsvox-ocr-tests--with-scanner
   "printf 'original bytes\\n'\n" nil
   (lambda (directory)
     (emacsvox-ocr-scan-image)
     (should (= emacsvox-ocr-last-page-number 0))
     (with-temp-buffer
       (insert-file-contents (expand-file-name "a book's;$cash-p1.tif" directory))
       (should (equal (buffer-string) "original bytes\n"))))))

(ert-deftest emacsvox-ocr-scanner-failure-publishes-no-image-or-success ()
  "A scanner failure removes incomplete output and preserves the page number."
  (emacsvox-ocr-tests--with-scanner
   "printf 'partial image'; printf 'scanner broke\\n' >&2; exit 7\n" nil
   (lambda (directory)
     (let (messages)
       (cl-letf (((symbol-function 'message)
                  (lambda (format-string &rest args)
                    (push (apply #'format format-string args) messages))))
         (should-error (call-interactively #'emacsvox-ocr-scan-image)))
       (should-not (cl-some (lambda (message) (string-match-p "Acquired" message)) messages)))
     (should (= emacsvox-ocr-last-page-number 0))
     (should-not (directory-files-recursively directory "\\.tif\\'"))
     (with-current-buffer emacsvox-ocr-error-buffer
       (should (string-match-p "scanner broke" (buffer-string)))))))

(ert-deftest emacsvox-ocr-compression-failure-retains-a-recoverable-original ()
  "Failed compression preserves acquired bytes and reports their actual path."
  (emacsvox-ocr-tests--with-scanner
   "printf 'original bytes\\n'\n"
   "printf 'partial compressed' > \"$2\"; printf 'compressor broke\\n' >&2; exit 9\n"
   (lambda (directory)
     (let* ((emacsvox-ocr-keep-uncompressed-image nil)
            (failure (should-error (call-interactively #'emacsvox-ocr-scan-image)))
            (description (error-message-string failure))
            (images (directory-files-recursively directory "\\.tif\\'"))
            original)
       (should (= emacsvox-ocr-last-page-number 0))
       (should-not (file-exists-p (expand-file-name "a book's;$cash-p1.tif" directory)))
       (dolist (image images)
         (with-temp-buffer
           (insert-file-contents image)
           (when (equal (buffer-string) "original bytes\n") (setq original image))))
       (should original)
       (should (string-match-p (regexp-quote original) description))
       (with-current-buffer emacsvox-ocr-error-buffer
         (should (string-match-p "compressor broke" (buffer-string))))))))

(ert-deftest emacsvox-ocr-empty-acquisition-does-not-count-as-success ()
  "Exit zero without image data must not publish or advance a page."
  (emacsvox-ocr-tests--with-scanner
   "exit 0\n" nil
   (lambda (directory)
     (let ((failure (should-error (call-interactively #'emacsvox-ocr-scan-image))))
       (should (string-match-p "produced no image" (error-message-string failure))))
     (should (= emacsvox-ocr-last-page-number 0))
     (should-not (directory-files-recursively directory "\\.tif\\'")))))

(ert-deftest emacsvox-ocr-recognition-preserves-literal-arguments ()
  "OCR should handle spaces without invoking a shell."
  (let* ((directory (make-temp-file "emacsvox ocr success " t))
         (engine
          (emacsvox-ocr-tests--write-executable
           (expand-file-name "fake engine" directory)
           (concat
            "#!/bin/sh\n"
            "for argument\n"
            "do\n"
            "  printf 'ARG=<%s>\\n' \"$argument\"\n"
            "done\n")))
         (input (expand-file-name "input document.pdf" directory))
         (error-buffer-name "*Emacsvox OCR Test Errors*"))
    (unwind-protect
        (progn
          (with-temp-file input
            (insert "test input\n"))
          (with-temp-buffer
            (emacsvox-ocr-mode)
            (setq default-directory directory
                  emacsvox-ocr-document-name "test-document"
                  emacsvox-ocr-engine engine
                  emacsvox-ocr-engine-options '("--mode" "two words")
                  emacsvox-ocr-error-buffer error-buffer-name)
            (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
                      ((symbol-function 'emacsvox-speak-line) #'ignore))
              (emacsvox-ocr-recognize-file input)
              (emacsvox-ocr-tests--wait-for-process))
            (should (= emacsvox-ocr-current-page-number 1))
            (should (= emacsvox-ocr-last-page-number 1))
            (should (string-match-p
                     (regexp-quote (format "ARG=<%s>" input))
                     (buffer-string)))
            (should (string-match-p
                     (regexp-quote "ARG=<two words>")
                     (buffer-string)))
            (should
             (file-exists-p
              (expand-file-name "test-document-p1.txt" directory)))))
      (when-let* ((buffer (get-buffer error-buffer-name)))
        (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest emacsvox-ocr-failure-rolls-back-the-page ()
  "A failed engine should leave diagnostics but no successful page."
  (let* ((directory (make-temp-file "emacsvox-ocr-failure-" t))
         (engine
          (emacsvox-ocr-tests--write-executable
           (expand-file-name "failing-engine" directory)
           "#!/bin/sh\nprintf 'recognition failed\\n' >&2\nexit 7\n"))
         (input (expand-file-name "input.png" directory))
         (error-buffer-name "*Emacsvox OCR Failure Test Errors*"))
    (unwind-protect
        (progn
          (with-temp-file input
            (insert "test input\n"))
          (with-temp-buffer
            (emacsvox-ocr-mode)
            (setq default-directory directory
                  emacsvox-ocr-document-name "failed-document"
                  emacsvox-ocr-engine engine
                  emacsvox-ocr-error-buffer error-buffer-name)
            (cl-letf (((symbol-function 'emacsvox-icon) #'ignore))
              (emacsvox-ocr-recognize-file input)
              (emacsvox-ocr-tests--wait-for-process))
            (should (= emacsvox-ocr-current-page-number 0))
            (should (= emacsvox-ocr-last-page-number 0))
            (should-not (string-match-p "Page 1" (buffer-string)))
            (with-current-buffer error-buffer-name
              (should (string-match-p "recognition failed" (buffer-string))))))
      (when-let* ((buffer (get-buffer error-buffer-name)))
        (kill-buffer buffer))
      (delete-directory directory t))))

(provide 'emacsvox-ocr-tests)
;;; emacsvox-ocr-tests.el ends here
