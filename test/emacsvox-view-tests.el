;;; emacsvox-view-tests.el --- View advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated View advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-view.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--view-advice
  '((view-mode emacsvox--advice-view-mode-after)
    (View-exit-and-edit emacsvox--advice-View-exit-and-edit-after)
    (View-kill-and-leave emacsvox--advice-View-kill-and-leave-after)
    (View-quit-all emacsvox--advice-View-quit-all-after)
    (View-quit emacsvox--advice-View-quit-after)
    (view-buffer emacsvox--advice-view-buffer-after)
    (view-buffer-other-frame emacsvox--advice-view-buffer-other-frame-after)
    (view-buffer-other-window emacsvox--advice-view-buffer-other-window-after)
    (view-emacs-FAQ emacsvox--advice-view-emacs-FAQ-after)
    (view-emacs-debugging emacsvox--advice-view-emacs-debugging-after)
    (view-emacs-problems emacsvox--advice-view-emacs-problems-after)
    (view-emacs-todo emacsvox--advice-view-emacs-todo-after)
    (view-external-packages emacsvox--advice-view-external-packages-after)
    (view-file-other-frame emacsvox--advice-view-file-other-frame-after)
    (view-file-other-window emacsvox--advice-view-file-other-window-after)
    (view-hello-file emacsvox--advice-view-hello-file-after)
    (view-lossage emacsvox--advice-view-lossage-after)
    (View-search-regexp-forward
     emacsvox--advice-View-search-regexp-forward-after)
    (View-search-regexp-backward
     emacsvox--advice-View-search-regexp-backward-after)
    (View-search-last-regexp-backward
     emacsvox--advice-View-search-last-regexp-backward-after)
    (View-search-last-regexp-forward
     emacsvox--advice-View-search-last-regexp-forward-after)
    (View-scroll-half-page-backward
     emacsvox--advice-View-scroll-half-page-backward-after)
    (View-scroll-half-page-forward
     emacsvox--advice-View-scroll-half-page-forward-after)
    (View-scroll-line-backward
     emacsvox--advice-View-scroll-line-backward-after)
    (View-scroll-line-forward
     emacsvox--advice-View-scroll-line-forward-after)
    (View-scroll-page-backward
     emacsvox--advice-View-scroll-page-backward-after)
    (View-scroll-page-forward
     emacsvox--advice-View-scroll-page-forward-after)
    (View-scroll-page-backward-set-page-size
     emacsvox--advice-View-scroll-page-backward-set-page-size-after)
    (View-scroll-page-forward-set-page-size
     emacsvox--advice-View-scroll-page-forward-set-page-size-after)
    (View-back-to-mark emacsvox--advice-View-back-to-mark-after)
    (View-goto-line emacsvox--advice-View-goto-line-after)
    (View-scroll-to-buffer-end
     emacsvox--advice-View-scroll-to-buffer-end-after)
    (View-goto-percent emacsvox--advice-View-goto-percent-after))
  "Native after-advice registrations in the View integration.")

(ert-deftest emacsvox-view-advice-is-directly-registered ()
  "View advice uses native advice directly."
  (dolist (entry emacsvox-test--view-advice)
    (pcase-let ((`(,target ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-view-exit-feedback-is-target-aware ()
  "Only the matching interactive View exit produces feedback."
  (let ((ems--interactive-fn-name 'View-quit)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events))))
      (emacsvox--advice-View-exit-and-edit-after)
      (emacsvox--advice-View-quit-after))
    (should
     (equal
      (nreverse events)
      '((icon close-object) speak-mode-line)))))

(ert-deftest emacsvox-view-entry-feedback-is-target-aware ()
  "Only the matching interactive View entry produces feedback."
  (let ((ems--interactive-fn-name 'view-buffer-other-window)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events))))
      (emacsvox--advice-view-buffer-after)
      (emacsvox--advice-view-buffer-other-window-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) speak-mode-line)))))

(ert-deftest emacsvox-view-search-feedback-preserves-order-and-point-cue ()
  "An interactive View search speaks with point shown, then cues the hit."
  (let ((ems--interactive-fn-name 'View-search-regexp-forward)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda ()
                 (push (list 'speak-line emacsvox-show-point) events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-View-search-regexp-forward-after))
    (should
     (equal
      (nreverse events)
      '((speak-line t) (icon search-hit))))))

(ert-deftest emacsvox-view-scroll-advice-is-active-and-target-aware ()
  "The formerly dead scroll family cues and speaks only its target."
  (let ((ems--interactive-fn-name 'View-scroll-page-forward)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-windowful)
               (lambda () (push 'speak-windowful events))))
      (emacsvox--advice-View-scroll-line-forward-after)
      (emacsvox--advice-View-scroll-page-forward-after))
    (should
     (equal
      (nreverse events)
      '((icon scroll) speak-windowful)))))

(ert-deftest emacsvox-view-goto-line-uses-native-argument ()
  "Native View line advice speaks its explicit argument."
  (let ((ems--interactive-fn-name 'View-goto-line)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'ems--this-line) (lambda () ": contents"))
              ((symbol-function 'tts-speak)
               (lambda (text)
                 (push (list 'speak (substring-no-properties text)) events))))
      (emacsvox--advice-View-goto-line-after 23))
    (should
     (equal
      (nreverse events)
      '((icon large-movement) (speak "line 23: contents"))))))

(provide 'emacsvox-view-tests)
;;; emacsvox-view-tests.el ends here
