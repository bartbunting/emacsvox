;;; emacsvox-denote-tests.el --- Denote advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'cl-lib)
(require 'ert)
(require 'ert-x)
(require 'package)
(package-initialize)
(require 'denote)
(load (expand-file-name "../lisp/integrations/emacsvox-denote.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-denote-advice-is-current-and-direct ()
  "Current Denote targets use native advice directly."
  (dolist (entry emacsvox-denote--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-denote-feedback-is-target-aware ()
  "Only the matching interactive Denote command produces feedback."
  (let ((ems--interactive-fn-name 'denote-link)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-denote-rename-file-using-front-matter-after)
      (emacsvox--advice-denote-link-after))
    (should
     (equal (nreverse events)
            '((icon complete) (speak "Linked"))))))

(ert-deftest emacsvox-denote-interactive-rename-feedback ()
  "Speak once for an applied keyword edit or rename and stay quiet on cancel."
  (ert-with-temp-directory directory
    (let* ((denote-directory directory)
           (denote-rename-confirmations '(modify-file-name))
           (denote-rename-rewrite-front-matter nil)
           (denote-current-data nil)
           (denote-used-identifiers nil)
           (denote-prompts '(title))
           (original (expand-file-name "20260102T030405--note__old.org" directory))
           (updated (expand-file-name "20260102T030405--note__new.org" directory))
           (renamed (expand-file-name "20260102T030405--renamed__new.org" directory))
           (confirm t)
           (keywords '("new"))
           events)
      (write-region "* Note\n" nil original nil 'silent)
      (with-current-buffer (find-file-noselect original)
        (unwind-protect
            (cl-letf (((symbol-function 'denote-keywords-prompt)
                       (lambda (&rest _) (if (eq keywords 'quit) (signal 'quit nil) keywords)))
                      ((symbol-function 'denote-title-prompt) (lambda (&rest _) "Renamed"))
                      ((symbol-function 'y-or-n-p) (lambda (&rest _) confirm))
                      ((symbol-function 'emacsvox-icon) (lambda (cue) (push cue events)))
                      ((symbol-function 'tts-speak) (lambda (text) (push text events))))
              (call-interactively #'denote-rename-file-keywords)
              (should (equal buffer-file-name updated))
              (should (file-exists-p updated))
              (should-not (file-exists-p original))
              (should (equal (nreverse events) '(task-done "Keywords updated")))

              (setq events nil)
              (call-interactively #'denote-rename-file-keywords)
              (should-not events)

              (setq confirm nil keywords '("old"))
              (call-interactively #'denote-rename-file-keywords)
              (should (equal buffer-file-name updated))
              (should-not (file-exists-p original))
              (should-not events)

              (setq keywords 'quit)
              (should (eq (condition-case nil (call-interactively #'denote-rename-file-keywords)
                            (quit 'cancelled))
                          'cancelled))
              (should-not events)

              (setq confirm t)
              (call-interactively #'denote-rename-file)
              (should (file-exists-p renamed))
              (should (equal (nreverse events) '(task-done "Renamed")))

              (setq events nil)
              (denote-rename-file renamed 'keep-current '("scripted")
                                  'keep-current 'keep-current 'keep-current)
              (should (equal (denote-extract-keywords-from-path buffer-file-name) '("scripted")))
              (should-not events))
          (kill-buffer (current-buffer)))))))

(provide 'emacsvox-denote-tests)
;;; emacsvox-denote-tests.el ends here
