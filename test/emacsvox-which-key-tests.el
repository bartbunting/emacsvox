;;; emacsvox-which-key-tests.el --- Which-Key advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Which-Key advice.

;;; Code:

(require 'ert)
(require 'which-key)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-which-key.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--which-key-advice
  '((which-key--show-page
     :after emacsvox--advice-which-key--show-page-after)
    (which-key--hide-popup
     :after emacsvox--advice-which-key--hide-popup-after)
    (which-key-abort
     :after emacsvox--advice-which-key-abort-after)
    (which-key-undo-key
     :after emacsvox--advice-which-key-undo-key-after)
    (which-key-show-standard-help
     :before emacsvox--advice-which-key-show-standard-help-before)
    (which-key-show-next-page-cycle
     :after emacsvox--advice-which-key-show-next-page-cycle-after)
    (which-key-show-previous-page-cycle
     :after emacsvox--advice-which-key-show-previous-page-cycle-after)
    (which-key-show-next-page-no-cycle
     :after emacsvox--advice-which-key-show-next-page-no-cycle-after)
    (which-key-show-previous-page-no-cycle
     :after emacsvox--advice-which-key-show-previous-page-no-cycle-after)
    (which-key-show-top-level
     :after emacsvox--advice-which-key-show-top-level-after)
    (which-key-show-major-mode
     :after emacsvox--advice-which-key-show-major-mode-after)
    (which-key-show-full-major-mode
     :after emacsvox--advice-which-key-show-full-major-mode-after)
    (which-key-show-minor-mode-keymap
     :after emacsvox--advice-which-key-show-minor-mode-keymap-after)
    (which-key-show-keymap
     :after emacsvox--advice-which-key-show-keymap-after))
  "Current Which-Key commands and their direct advice.")

(ert-deftest emacsvox-which-key-advice-is-directly-registered ()
  "Which-Key advice is attached directly to current Emacs 31 targets."
  (dolist (entry emacsvox-test--which-key-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-which-key-page-display-remains-unconditional ()
  "Internal page display speaks whenever automatic speech is enabled."
  (let ((emacsvox-which-key--auto-speak t)
        (ems--interactive-fn-name nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-which-key--speak-page)
               (lambda () (push 'page events))))
      (emacsvox--advice-which-key--show-page-after))
    (should (equal (nreverse events) '((icon help) page)))
    (setq emacsvox-which-key--auto-speak nil
          events nil)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-which-key--speak-page)
               (lambda () (push 'page events))))
      (emacsvox--advice-which-key--show-page-after))
    (should-not events)))

(ert-deftest emacsvox-which-key-popup-feedback-is-target-aware ()
  "Only the matching interactive popup-closing command gives feedback."
  (let ((ems--interactive-fn-name 'which-key-abort)
        events)
    (cl-letf (((symbol-function 'dtk-stop)
               (lambda (&rest arguments)
                 (push (cons 'stop arguments) events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-which-key--hide-popup-after)
      (emacsvox--advice-which-key-abort-after))
    (should
     (equal
      (nreverse events)
      '((stop all) (icon close-object))))))

(ert-deftest emacsvox-which-key-paging-feedback-is-target-aware ()
  "Only matching interactive paging announces the resulting page."
  (let ((ems--interactive-fn-name 'which-key-show-next-page-cycle)
        (which-key--pages-obj '(:page-nums 1 :num-pages 3))
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-which-key-show-previous-page-cycle-after)
      (emacsvox--advice-which-key-show-next-page-cycle-after))
    (should
     (equal
      (nreverse events)
      '((icon scroll) (speak "page 2 of 3"))))))

(ert-deftest emacsvox-which-key-show-feedback-is-target-aware ()
  "Only the matching interactive display command produces an opening cue."
  (let ((ems--interactive-fn-name 'which-key-show-major-mode)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-which-key-show-top-level-after)
      (emacsvox--advice-which-key-show-major-mode-after))
    (should (equal events '(open-object)))))

(provide 'emacsvox-which-key-tests)
;;; emacsvox-which-key-tests.el ends here
