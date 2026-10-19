;;; emacsvox-speak-filters-tests.el --- Reading column filter tests -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Preserve column selection, buffer scope and saved filters across extraction.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-speak)

(ert-deftest emacsvox-speak-filters-preserve-text-and-other-properties ()
  "Normal and inverted filters mark the selected columns without editing text."
  (dolist (invert '(nil t))
    (let ((emacsvox-speak-line-column-filter '((0 2) (4 6) (8 12)))
          (text (propertize "abcdefgh" 'face 'bold)))
      (should (eq text (emacsvox-speak-line-apply-column-filter text invert)))
      (should (equal (substring-no-properties text) "abcdefgh"))
      (dotimes (index (length text))
        (should (eq (get-text-property index 'face text) 'bold))
        (should
         (eq (get-text-property index 'personality text)
             (when (if invert (memq index '(2 3 6 7))
                     (memq index '(0 1 4 5)))
               'inaudible)))))))

(ert-deftest emacsvox-speak-filters-keep-buffer-scope-and-saved-defaults ()
  "Editing one buffer's filter or inversion leaves another buffer unchanged."
  (let ((emacsvox-speak-filter-table (make-hash-table)))
    (with-temp-buffer
      (setq buffer-file-name "/tmp/emacsvox-filter-sample")
      (setq-local emacsvox-speak-line-invert-filter nil)
      (emacsvox-speak-line-set-column-filter '((0 4)))
      (cl-letf (((symbol-function 'tts--protocol-sync) #'ignore))
        (emacsvox-toggle-speak-line-invert-filter))
      (should emacsvox-speak-line-invert-filter)
      (with-temp-buffer
        (should-not emacsvox-speak-line-column-filter)
        (should-not emacsvox-speak-line-invert-filter)
        (should (equal (emacsvox-speak-lookup-persistent-filter
                        "/tmp/emacsvox-filter-sample")
                       '((0 4))))
        (insert "abc")
        (should (equal (emacsvox-speak-lookup-persistent-filter "new-file")
                       '((0 3)))))
      (should (equal emacsvox-speak-line-column-filter '((0 4))))
      (emacsvox-speak-line-set-column-filter 'invalid)
      (should-not emacsvox-speak-line-column-filter)
      (should (equal (emacsvox-speak-lookup-persistent-filter buffer-file-name)
                     '((0 4)))))))

(ert-deftest emacsvox-speak-filters-round-trip-saved-settings ()
  "Saved filters reload once and register the existing save-on-exit hook."
  (let* ((directory (make-temp-file "emacsvox-filter-settings-" t))
         (emacsvox-speak-filter-persistent-store
          (expand-file-name ".filters" directory))
         (emacsvox-speak-filter-table (make-hash-table))
         (emacsvox-speak-filters-loaded-p nil)
         (emacsvox-speak-messages nil)
         (kill-emacs-hook nil)
         (noninteractive nil)
         (key (expand-file-name "a file with spaces" directory)))
    (unwind-protect
        (progn
          (emacsvox-speak-set-persistent-filter key '((0 4) (8 10)))
          (emacsvox-speak-set-persistent-filter "fundamental-mode" '((2 6)))
          (emacsvox-speak-persist-filter-settings)
          (should (file-exists-p emacsvox-speak-filter-persistent-store))
          (setq emacsvox-speak-filter-table (make-hash-table))
          (emacsvox-speak-load-filter-settings)
          (should (equal (emacsvox-speak-lookup-persistent-filter key)
                         '((0 4) (8 10))))
          (should (equal (emacsvox-speak-lookup-persistent-filter 'fundamental-mode)
                         '((2 6))))
          (should emacsvox-speak-filters-loaded-p)
          (should (memq #'emacsvox-speak-persist-filter-settings kill-emacs-hook))
          ;; A second load must not discard edits made during the session.
          (emacsvox-speak-set-persistent-filter key '((1 3)))
          (emacsvox-speak-load-filter-settings)
          (should (equal (emacsvox-speak-lookup-persistent-filter key) '((1 3))))
          (should (= (cl-count #'emacsvox-speak-persist-filter-settings
                              kill-emacs-hook)
                     1))
          (run-hooks 'kill-emacs-hook)
          (setq emacsvox-speak-filter-table (make-hash-table)
                emacsvox-speak-filters-loaded-p nil)
          (emacsvox-speak-load-filter-settings)
          (should (equal (emacsvox-speak-lookup-persistent-filter key) '((1 3)))))
      (dolist (buffer (buffer-list))
        (when-let* ((file (buffer-file-name buffer))
                    ((file-in-directory-p file directory)))
          (with-current-buffer buffer (set-buffer-modified-p nil))
          (kill-buffer buffer)))
      (delete-directory directory t))))

(provide 'emacsvox-speak-filters-tests)
;;; emacsvox-speak-filters-tests.el ends here
