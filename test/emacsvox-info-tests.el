;;; emacsvox-info-tests.el --- Info advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Info advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'info)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-info.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--info-node-targets
  '(info
    info-display-manual
    Info-follow-reference
    Info-goto-node
    info-emacs-manual
    Info-top-node
    Info-final-node
    Info-up
    Info-goto-emacs-key-command-node
    Info-goto-emacs-command-node
    Info-history
    Info-virtual-index
    Info-directory
    Info-help
    Info-nth-menu-item
    Info-menu
    Info-follow-nearest-node
    Info-history-back
    Info-history-forward
    Info-backward-node
    Info-forward-node
    Info-next
    Info-prev)
  "Current interactive Info commands that select a node.")

(ert-deftest emacsvox-info-advice-is-directly-registered ()
  "Info advice is attached directly to current Emacs 31 commands."
  (dolist
      (target
       (append
        emacsvox-test--info-node-targets
        '(Info-search
          Info-scroll-up
          Info-scroll-down
          Info-next-reference
          Info-prev-reference)))
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (commandp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-info-omits-stale-targets ()
  "Info variables and obsolete exits receive no module-specific advice."
  (should (boundp 'Info-menu-last-node))
  (should-not (fboundp 'Info-menu-last-node))
  (should-not
   (fboundp 'emacsvox--advice-Info-menu-last-node-after))
  (should-not (commandp 'Info-select-node))
  (should-not
   (fboundp 'emacsvox--advice-Info-select-node-after))
  (should
   (eq
    (indirect-function 'Info-exit)
    (indirect-function 'quit-window)))
  (should-not (fboundp 'emacsvox--advice-Info-exit-after)))

(ert-deftest emacsvox-info-node-feedback-is-target-aware ()
  "Only the matching Info node-selection command announces a visit."
  (let ((ems--interactive-fn-name 'Info-next)
        visits)
    (cl-letf (((symbol-function 'emacsvox-info-visit-node)
               (lambda () (push 'visit visits))))
      (emacsvox--advice-Info-prev-after)
      (emacsvox--advice-Info-next-after))
    (should (equal visits '(visit)))))

(ert-deftest emacsvox-info-search-feedback-is-target-aware ()
  "An interactive Info search announces its resulting line."
  (let ((ems--interactive-fn-name 'Info-search)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-Info-search-after))
    (should
     (equal
      (nreverse events)
      '((icon search-hit) line)))))

(ert-deftest emacsvox-info-scroll-feedback-is-target-aware ()
  "Only the matching Info scrolling command speaks the current screen."
  (let ((ems--interactive-fn-name 'Info-scroll-down)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-info-speak-current-window)
               (lambda () (push 'screen events))))
      (emacsvox--advice-Info-scroll-up-after)
      (emacsvox--advice-Info-scroll-down-after))
    (should
     (equal
      (nreverse events)
      '((icon scroll) screen)))))

(ert-deftest emacsvox-info-reference-feedback-is-target-aware ()
  "Previous and next reference movement do not cross-fire."
  (let ((ems--interactive-fn-name 'Info-prev-reference)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-Info-next-reference-after)
      (emacsvox--advice-Info-prev-reference-after))
    (should
     (equal
      (nreverse events)
      '((icon large-movement) line)))))

(ert-deftest emacsvox-info-programmatic-advice-is-quiet ()
  "Info helper advice emits no feedback outside interactive dispatch."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (&rest arguments) (push arguments events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events)))
              ((symbol-function 'emacsvox-info-speak-current-window)
               (lambda () (push 'screen events))))
      (emacsvox--advice-Info-search-after)
      (emacsvox--advice-Info-scroll-up-after)
      (emacsvox--advice-Info-next-reference-after))
    (should-not events)))

(provide 'emacsvox-info-tests)
;;; emacsvox-info-tests.el ends here
