;;; emacsvox-outline-tests.el --- Outline advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Outline advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-outline.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

;; Trigger the optional Foldout advice while exercising the same Emacs 31
;; library that users load.
(require 'foldout)

(defconst emacsvox-test--outline-after-targets
  '(outline-next-heading outline-previous-heading outline-next-preface
    outline-next-visible-heading outline-previous-visible-heading
    outline-back-to-heading outline-up-heading
    outline-backward-same-level outline-forward-same-level
    outline-insert-heading outline-cycle-buffer outline-cycle
    outline-show-only-headings outline-hide-entry outline-show-entry
    outline-hide-body outline-show-all outline-hide-subtree
    outline-hide-leaves outline-show-subtree outline-hide-sublevels
    outline-hide-other outline-show-branches outline-show-children)
  "Outline commands expected to use direct native after advice.")

(defconst emacsvox-test--foldout-after-targets
  '(foldout-zoom-subtree foldout-exit-fold)
  "Foldout commands expected to use direct native after advice.")

(ert-deftest emacsvox-outline-enables-only-for-emacsvox-source ()
  "Emacsvox Lisp sources automatically use Outline minor mode."
  (should
   (memq #'emacsvox-outline--enable-for-source emacs-lisp-mode-hook))
  (let ((emacs-lisp-mode-hook
         '(emacsvox-outline--enable-for-source)))
    (with-temp-buffer
      (setq buffer-file-name
            (expand-file-name "lisp/emacsvox-test-source.el"
                              emacsvox-directory))
      (emacs-lisp-mode)
      (should outline-minor-mode))
    (with-temp-buffer
      (setq buffer-file-name
            (expand-file-name "emacsvox-test-outside.el"
                              temporary-file-directory))
      (emacs-lisp-mode)
      (should-not outline-minor-mode))))

(ert-deftest emacsvox-outline-advice-is-directly-registered ()
  "Outline advice uses native advice directly."
  (dolist (target emacsvox-test--outline-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (should
   (advice-member-p
    #'emacsvox--advice-outline-flag-region-around
    'outline-flag-region)))

(ert-deftest emacsvox-outline-navigation-feedback-is-target-aware ()
  "Only the matching navigation command cues and speaks its line."
  (let ((ems--interactive-fn-name 'outline-next-visible-heading)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-outline-previous-visible-heading-after 1)
      (emacsvox--advice-outline-next-visible-heading-after 1))
    (should
     (equal
      (nreverse events)
      '((icon section) speak-line)))))

(ert-deftest emacsvox-outline-cycle-feedback-preserves-order ()
  "Interactive visibility cycling cues before speaking its line."
  (let ((ems--interactive-fn-name 'outline-cycle)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-outline-cycle-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) speak-line)))))

(ert-deftest emacsvox-outline-hide-sublevels-uses-explicit-levels ()
  "The hide-sublevels announcement reports its native LEVELS argument."
  (let ((ems--interactive-fn-name 'outline-hide-sublevels)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push (cons 'message
                             (cons format-string arguments))
                       events))))
      (emacsvox--advice-outline-hide-sublevels-after 4))
    (should
     (equal
      (nreverse events)
      '((icon close-object)
        (message "Hid everything except the top  %s levels" 4))))))

(ert-deftest emacsvox-outline-flag-region-calls-original-once ()
  "Flagging mirrors invisibility and preserves the original result."
  (with-temp-buffer
    (insert "heading\nbody\n")
    (let ((calls 0)
          observed)
      (should
       (eq
        (emacsvox--advice-outline-flag-region-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (setq observed
                 (list arguments ems--voiceify-overlays
                       inhibit-read-only))
           'flag-result)
         0 9 t)
        'flag-result))
      (should (= calls 1))
      (should (equal observed '((0 9 t) nil t)))
      (should (eq (get-text-property (point-min) 'invisible) 'outline))
      (should-not (get-text-property 9 'invisible)))))

(ert-deftest emacsvox-outline-flag-region-clears-invisibility ()
  "Unflagging removes the mirrored Outline invisibility property."
  (with-temp-buffer
    (insert (propertize "heading\n" 'invisible 'outline))
    (emacsvox--advice-outline-flag-region-around
     (lambda (&rest _) nil)
     (point-min) (point-max) nil)
    (should-not (get-text-property (point-min) 'invisible))))

(ert-deftest emacsvox-foldout-advice-is-directly-registered ()
  "Optional Foldout advice uses native advice directly."
  (dolist (target emacsvox-test--foldout-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-foldout-zoom-feedback-preserves-content ()
  "Interactive Foldout zoom reports the heading and visible line count."
  (with-temp-buffer
    (insert "Heading\nBody\n")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'foldout-zoom-subtree)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'ems--this-line)
                 (lambda () "Heading"))
                ((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push (cons 'message
                               (cons format-string arguments))
                         events))))
        (emacsvox--advice-foldout-zoom-subtree-after))
      (should
       (equal
        (nreverse events)
        '((icon open-object)
          (message "Zoomed into outline %s containing %s lines"
                   "Heading" 2)))))))

(provide 'emacsvox-outline-tests)
;;; emacsvox-outline-tests.el ends here
