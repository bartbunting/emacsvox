;;; emacsvox-ange-ftp-tests.el --- Ange FTP advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Ange FTP progress advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defvar ange-ftp-last-percent)

(ert-deftest emacsvox-ange-ftp-advice-is-directly-registered ()
  "Migrated Ange FTP advice uses native advice directly."
  (should
   (fboundp 'emacsvox--advice-ange-ftp-process-handle-hash-around))
  (should
   (advice-member-p
    #'emacsvox--advice-ange-ftp-process-handle-hash-around
    'ange-ftp-process-handle-hash)))

(ert-deftest emacsvox-ange-ftp-progress-preserves-original-result ()
  "FTP progress feedback runs quietly after one call and returns its string."
  (let ((ange-ftp-last-percent 42)
        (emacsvox-speak-messages t)
        (inhibit-message nil)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon)
                 (push
                  (list 'icon icon
                        emacsvox-speak-messages inhibit-message)
                  events)))
              ((symbol-function 'dtk-speak)
               (lambda (text)
                 (push
                  (list 'speak text
                        emacsvox-speak-messages inhibit-message)
                  events)
                 'speech-result)))
      (should
       (equal
        (emacsvox--advice-ange-ftp-process-handle-hash-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (push
            (list 'original arguments
                  emacsvox-speak-messages inhibit-message)
            events)
           "processed FTP output")
         "###")
        "processed FTP output")))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((original ("###") nil t)
        (icon progress nil t)
        (speak " 42 percent" nil t))))
    (should emacsvox-speak-messages)
    (should-not inhibit-message)))

(provide 'emacsvox-ange-ftp-tests)
;;; emacsvox-ange-ftp-tests.el ends here
