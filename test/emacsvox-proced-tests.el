;;; emacsvox-proced-tests.el --- Proced advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Proced advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-proced.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--proced-advice
  '((proced-mark :before emacsvox--advice-proced-mark-before)
    (proced-unmark :before emacsvox--advice-proced-unmark-before)
    (proced-mark-all :after emacsvox--advice-proced-mark-all-after)
    (proced-unmark-all :after emacsvox--advice-proced-unmark-all-after)
    (proced :around emacsvox--advice-proced-around)
    (proced-update :around emacsvox--advice-proced-update-around)
    (proced-sort-pcpu :after emacsvox--advice-proced-sort-pcpu-after)
    (proced-sort-start :after emacsvox--advice-proced-sort-start-after)
    (proced-sort-time :after emacsvox--advice-proced-sort-time-after)
    (proced-sort-interactive
     :after emacsvox--advice-proced-sort-interactive-after)
    (proced-sort-user :after emacsvox--advice-proced-sort-user-after)
    (proced-sort-pmem :after emacsvox--advice-proced-sort-pmem-after)
    (proced-sort-pid :after emacsvox--advice-proced-sort-pid-after))
  "Native advice registrations in the Proced integration.")

(ert-deftest emacsvox-proced-advice-is-directly-registered ()
  "Proced advice uses native advice directly."
  (dolist (entry emacsvox-test--proced-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-proced-mark-feedback-is-target-aware ()
  "Only the matching interactive mark command produces feedback."
  (let ((ems--interactive-fn-name 'proced-unmark)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-proced-speak-this-field)
               (lambda () (push 'speak-field events))))
      (emacsvox--advice-proced-mark-before)
      (emacsvox--advice-proced-unmark-before))
    (should
     (equal
      (nreverse events)
      '((icon deselect-object) speak-field)))))

(ert-deftest emacsvox-proced-update-preserves-result-and-feedback-order ()
  "Interactive update runs once, refreshes caches, then gives feedback."
  (let ((ems--interactive-fn-name 'proced-update)
        events)
    (cl-letf (((symbol-function 'emacsvox-proced-update-fields)
               (lambda () (push 'update-fields events)))
              ((symbol-function 'emacsvox-proced-update-process-cache)
               (lambda () (push 'update-process-cache events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda ()
                 (interactive)
                 (push 'speak-mode-line events))))
      (should
       (eq
        'original-result
        (emacsvox--advice-proced-update-around
         (lambda (&rest _)
           (push (list 'original emacsvox-speak-messages) events)
           'original-result)
         t nil)))
      (should
       (equal
        (nreverse events)
        '((original nil)
          update-fields
          update-process-cache
          (icon open-object)
          speak-mode-line))))))

(ert-deftest emacsvox-proced-update-is-quiet-programmatically ()
  "Programmatic update runs once and refreshes caches without feedback."
  (let ((calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-proced-update-fields)
               (lambda () (push 'update-fields events)))
              ((symbol-function 'emacsvox-proced-update-process-cache)
               (lambda () (push 'update-process-cache events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda ()
                 (interactive)
                 (push 'speak-mode-line events))))
      (should
       (eq
        'original-result
        (emacsvox--advice-proced-update-around
         (lambda (&rest _)
           (cl-incf calls)
           'original-result))))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '(update-fields update-process-cache))))))

(ert-deftest emacsvox-proced-sort-feedback-is-target-aware ()
  "Only the matching interactive sort command produces feedback."
  (let ((ems--interactive-fn-name 'proced-sort-pcpu)
        events)
    (cl-letf (((symbol-function 'emacsvox-proced-speak-this-field)
               (lambda () (push 'speak-field events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-proced-sort-user-after)
      (emacsvox--advice-proced-sort-pcpu-after))
    (should
     (equal
      (nreverse events)
      '(speak-field (icon task-done))))))

(provide 'emacsvox-proced-tests)
;;; emacsvox-proced-tests.el ends here
