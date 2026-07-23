;;; emacsvox-completion-tests.el --- Completion advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and native-registration coverage for migrated completion advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--completion-direct-advice
  '((pcomplete-list :after emacsvox--advice-pcomplete-list-after)
    (pcomplete-show-completions :around
     emacsvox--advice-pcomplete-show-completions-around)
    (pcomplete :around emacsvox--advice-pcomplete-around)
    (completion-at-point :around
     emacsvox--advice-completion-at-point-around)
    (minibuffer-choose-completion :around
     emacsvox--advice-minibuffer-choose-completion-around)
    (minibuffer-choose-completion-or-exit :after
     emacsvox--advice-minibuffer-choose-completion-or-exit-after))
  "Completion commands migrated to directly registered native advice.")

(ert-deftest emacsvox-completion-advice-is-directly-registered ()
  "Migrated completion advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--completion-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-completion-at-point-calls-original-once ()
  "Interactive completion calls once, preserves its result, then speaks."
  (with-temp-buffer
    (insert "prefix foo")
    (let ((ems--interactive-fn-name 'completion-at-point)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'dtk-speak)
                 (lambda (text) (push (list 'speak text) events)))
                ((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events))))
        (should
         (eq
          (emacsvox--advice-completion-at-point-around
           (lambda (&rest arguments)
             (cl-incf calls)
             (push (list 'original arguments) events)
             (insert "bar")
             'completion-result)
           'argument)
          'completion-result)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((original (argument))
          (speak "foobar")
          (icon complete)))))))

(ert-deftest emacsvox-pcomplete-preserves-region-feedback ()
  "Interactive PComplete speaks the completed region after one call."
  (with-temp-buffer
    (insert "prefix foo")
    (let ((ems--interactive-fn-name 'pcomplete)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-speak-region)
                 (lambda (start end)
                   (push
                    (list 'speak-region start end
                          (buffer-substring start end))
                    events)))
                ((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events))))
        (should
         (eq
          (emacsvox--advice-pcomplete-around
           (lambda (&rest _)
             (cl-incf calls)
             (push 'original events)
             (insert "bar")
             'pcomplete-result))
          'pcomplete-result)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '(original
          (speak-region 8 14 "foobar")
          (icon complete)))))))

(ert-deftest emacsvox-completion-advice-is-quiet-programmatically ()
  "Programmatic completion calls once without speech feedback."
  (let ((ems--interactive-fn-name nil)
        (calls 0)
        feedback)
    (cl-letf (((symbol-function 'dtk-speak)
               (lambda (&rest _) (setq feedback t)))
              ((symbol-function 'emacsvox-icon)
               (lambda (&rest _) (setq feedback t))))
      (should
       (eq
        (emacsvox--advice-minibuffer-choose-completion-around
         (lambda (&rest _)
           (cl-incf calls)
           'completion-result))
        'completion-result)))
    (should (= calls 1))
    (should-not feedback)))

(ert-deftest emacsvox-pcomplete-list-preserves-icon-order ()
  "Interactive completion listings emit help then completion icons."
  (let ((ems--interactive-fn-name 'pcomplete-list)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-pcomplete-list-after))
    (should (equal (nreverse events) '(help complete)))))

(provide 'emacsvox-completion-tests)
;;; emacsvox-completion-tests.el ends here
