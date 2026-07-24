;;; emacsvox-transient-tests.el --- Transient advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Transient advice.

;;; Code:

(require 'ert)
(require 'transient)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-transient.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--transient-advice
  '((transient-toggle-common :after
                             emacsvox--advice-transient-toggle-common-after)
    (transient-resume :after emacsvox--advice-transient-resume-after)
    (transient-quit-all :after
                        emacsvox--advice-transient-quit-all-after)
    (transient-quit-one :after
                        emacsvox--advice-transient-quit-one-after)
    (transient-quit-seq :after
                        emacsvox--advice-transient-quit-seq-after)
    (transient-save :after emacsvox--advice-transient-save-after)
    (transient-set :after emacsvox--advice-transient-set-after)
    (transient-history-next :after
                            emacsvox--advice-transient-history-next-after)
    (transient-history-prev :after
                            emacsvox--advice-transient-history-prev-after)
    (transient--show :after emacsvox--advice-transient--show-after)
    (transient-suspend :around
                       emacsvox--advice-transient-suspend-around)
    (transient-backward-button
     :around emacsvox--advice-transient-backward-button-around)
    (transient-forward-button
     :around emacsvox--advice-transient-forward-button-around))
  "Current Emacs 31 Transient targets and their direct native advice.")

(ert-deftest emacsvox-transient-advice-is-directly-registered ()
  "Transient advice is attached directly to current Emacs 31 targets."
  (dolist (entry emacsvox-test--transient-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-transient-feedback-is-target-aware ()
  "Only feedback for the matching Transient command is emitted."
  (let ((ems--interactive-fn-name 'transient-set)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'dtk-stop)
               (lambda (scope) (push (list 'stop scope) events))))
      (emacsvox--advice-transient-save-after)
      (emacsvox--advice-transient-set-after))
    (should
     (equal
      (nreverse events)
      '((icon save-object) (stop all))))))

(ert-deftest emacsvox-transient-show-caches-and-speaks-menu ()
  "Showing a Transient menu caches its contents and provides feedback."
  (save-window-excursion
    (with-temp-buffer
      (insert "Transient choices")
      (set-window-buffer (selected-window) (current-buffer))
      (let ((transient--window (selected-window))
            events)
        (cl-letf (((symbol-function 'emacsvox-speak-line)
                   (lambda () (push 'line events)))
                  ((symbol-function 'emacsvox-icon)
                   (lambda (icon) (push (list 'icon icon) events))))
          (emacsvox--advice-transient--show-after))
        (should (equal emacsvox-transient-cache "Transient choices"))
        (should
         (equal
          (nreverse events)
          '(line (icon open-object))))))))

(ert-deftest emacsvox-transient-suspend-calls-original-once ()
  "Interactive suspension builds the browse buffer after one original call."
  (let ((buffer-name "*Transient-Emacsvox*")
        (emacsvox-transient-cache "Transient choices")
        (ems--interactive-fn-name 'transient-suspend)
        (calls 0)
        events)
    (when (get-buffer buffer-name)
      (kill-buffer buffer-name))
    (unwind-protect
        (save-window-excursion
          (cl-letf (((symbol-function 'emacsvox-icon)
                     (lambda (icon) (push (list 'icon icon) events)))
                    ((symbol-function 'emacsvox-speak-mode-line)
                     (lambda () (push 'mode-line events))))
            (should
             (eq
              'result
              (emacsvox--advice-transient-suspend-around
               (lambda ()
                 (setq calls (1+ calls))
                 (push 'original events)
                 'result)))))
          (should (= calls 1))
          (with-current-buffer buffer-name
            (should (eq major-mode 'emacsvox-transient-mode))
            (should
             (equal
              (buffer-string)
              "r to resume, C-g to quit.\n\nTransient choices")))
          (should
           (equal
            (nreverse events)
            '(original (icon close-object) mode-line))))
      (when (get-buffer buffer-name)
        (kill-buffer buffer-name)))))

(ert-deftest emacsvox-transient-programmatic-suspend-runs-once ()
  "Programmatic suspension is quiet and invokes the original once."
  (let ((calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events))))
      (should
       (eq
        'result
        (emacsvox--advice-transient-suspend-around
         (lambda ()
           (setq calls (1+ calls))
           'result)))))
    (should (= calls 1))
    (should-not events)))

(ert-deftest emacsvox-transient-button-navigation-runs-once ()
  "Transient button movement speaks after exactly one original call."
  (save-window-excursion
    (with-temp-buffer
      (insert-text-button "Choice" 'action #'ignore)
      (goto-char (point-min))
      (set-window-buffer (selected-window) (current-buffer))
      (set-window-point (selected-window) (point))
      (let ((transient--window (selected-window))
            (ems--interactive-fn-name 'transient-forward-button)
            (calls 0)
            events)
        (cl-letf (((symbol-function 'dtk-speak)
                   (lambda (text) (push (list 'speak text) events)))
                  ((symbol-function 'emacsvox-icon)
                   (lambda (icon) (push (list 'icon icon) events))))
          (should
           (eq
            'result
            (emacsvox--advice-transient-forward-button-around
             (lambda (n)
               (setq calls (1+ calls))
               (push (list 'original n) events)
               'result)
             2))))
        (should (= calls 1))
        (should
         (equal
          (nreverse events)
          '((original 2) (speak "Choice") (icon button))))))))

(ert-deftest emacsvox-transient-setup-uses-emacs-31-settings ()
  "Transient setup uses the current Emacs 31 menu setting names."
  (should transient-enable-menu-navigation)
  (should (= transient-show-menu 1)))

(provide 'emacsvox-transient-tests)
;;; emacsvox-transient-tests.el ends here
