;;; emacsvox-aural-doctor-tests.el --- Aural Doctor tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Verify installation diagnostics, safe repairs, and spoken navigation.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-keymap)
(require 'emacsvox-aural-doctor)

(ert-deftest emacsvox-aural-doctor-summarizes-severity ()
  "The spoken summary distinguishes failures from warnings."
  (let ((findings
         (list
          (emacsvox-aural-doctor--finding
           'one 'error "One" "bad" "detail")
          (emacsvox-aural-doctor--finding
           'two 'warning "Two" "old" "detail")
          (emacsvox-aural-doctor--finding
           'three 'ok "Three" "good" "detail"))))
    (should
     (equal
      (emacsvox-aural-doctor-summary findings)
      "1 problem and 1 warning"))))

(ert-deftest emacsvox-aural-doctor-detects-stale-byte-code ()
  "A newer source file is reported against its loaded byte-code."
  (let* ((directory (make-temp-file "emacsvox-doctor-stale-" t))
         (source (expand-file-name "doctor-fixture.el" directory))
         (compiled (concat source "c"))
         (function 'emacsvox-test--doctor-fixture))
    (unwind-protect
        (progn
          (with-temp-file source
            (insert
             "(defun emacsvox-test--doctor-fixture () 'loaded)\n"))
          (byte-compile-file source)
          (load compiled nil nil t)
          (set-file-times source (time-add (current-time) 10))
          (let ((finding
                 (emacsvox-aural-doctor--loaded-file-finding
                  'fixture function)))
            (should
             (eq
              (emacsvox-aural-doctor-finding-severity finding)
              'warning))
            (should
             (equal
              (emacsvox-aural-doctor-finding-status finding)
              "stale byte-code"))
            (should
             (equal
              (emacsvox-aural-doctor-finding-repair finding)
              (list 'emacsvox-aural-doctor-reload-source source)))))
      (when (fboundp function) (fmakunbound function))
      (delete-directory directory t))))

(ert-deftest emacsvox-aural-doctor-restores-documented-bindings ()
  "The safe binding repair restores the live prefix map."
  (let ((global-map (copy-keymap global-map))
        (emacsvox-keymap (copy-keymap emacsvox-keymap)))
    (define-key emacsvox-keymap (kbd "H") #'ignore)
    (define-key emacsvox-keymap (kbd "E") #'ignore)
    (global-set-key emacsvox-prefix emacsvox-keymap)
    (emacsvox-aural-doctor-restore-bindings)
    (should (eq (key-binding (kbd "C-e H")) 'emacsvox-aural))
    (should
     (eq
      (key-binding (kbd "C-e E"))
      'emacsvox-aural-explain-presentation))))

(ert-deftest emacsvox-aural-doctor-runs-without-starting-speech ()
  "A complete diagnostic pass only reports the speech-server state."
  (let* ((directory (make-temp-file "emacsvox-doctor-data-" t))
         (emacsvox-aural-schemes-file
          (expand-file-name "absent.el" directory))
         (tts-speaker-process nil)
         (findings (emacsvox-aural-doctor-run))
         (server
          (cl-find
           'speech-server findings
           :key #'emacsvox-aural-doctor-finding-id))
         (face-policy
          (cl-find
           'face-presentation findings
           :key #'emacsvox-aural-doctor-finding-id)))
    (unwind-protect
        (progn
          (should server)
          (should
           (equal
            (emacsvox-aural-doctor-finding-status server)
            "not running"))
          (should
           (cl-find
            'active-scheme findings
            :key #'emacsvox-aural-doctor-finding-id))
          (should face-policy)
          (should
           (string-match-p
            "Voice Lock"
            (emacsvox-aural-doctor-finding-detail face-policy))))
      (delete-directory directory t))))

(ert-deftest emacsvox-aural-doctor-manager-is-spoken-and-refreshable ()
  "The doctor uses the shared titled-cell and boundary navigation contract."
  (let ((emacsvox-aural-schemes-file
         (expand-file-name
          "missing.el" (make-temp-file "emacsvox-doctor-mode-" t)))
        spoken)
    (unwind-protect
        (with-temp-buffer
          (emacsvox-aural-doctor-mode)
          (should
           (eq
            (lookup-key emacsvox-aural-doctor-mode-map (kbd "h"))
            #'emacsvox-aural))
          (cl-letf
              (((symbol-function 'tts-speak)
                (lambda (text) (push text spoken)))
               ((symbol-function 'emacsvox-icon) #'ignore))
            (emacsvox-aural-doctor-refresh)
            (emacsvox-aural-doctor-speak-current-cell)
            (should (string-match-p "Check" (car spoken)))
            (goto-char (point-min))
            (emacsvox-aural-doctor-previous)
            (should (string-match-p "top of aural doctor" (car spoken)))))
      (delete-directory
       (file-name-directory emacsvox-aural-schemes-file) t))))

(provide 'emacsvox-aural-doctor-tests)
;;; emacsvox-aural-doctor-tests.el ends here
