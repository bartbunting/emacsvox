;;; emacsvox-converter-tests.el --- Tests for advice conversion -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for the conservative legacy advice converter.

;;; Code:

(require 'ert)
(require 'defadvice-to-advice-add)

(ert-deftest emacsvox-converter-converts-only-direct-after-advice ()
  "A direct after advice gains a named helper and explicit target check."
  (let ((form
         '(defadvice calendar-forward-day (after emacsvox pre act comp)
            "Speak the date."
            (when (ems-interactive-p) (message "done")))))
    (should
     (equal
      (ems--convert-defadvice-form form)
      '((defun ems--calendar-forward-day-emacsvox-after (&rest _)
          "Speak the date."
          (when (ems-interactive-p 'calendar-forward-day)
            (message "done")))
        (advice-add
         'calendar-forward-day :after
         #'ems--calendar-forward-day-emacsvox-after
         '((name . emacsvox))))))))

(ert-deftest emacsvox-converter-does-not-rewrite-quoted-examples ()
  "Quoted calls to `ems-interactive-p' remain data."
  (should
   (equal
    (ems--transform-interactive-checks
     '(list '(ems-interactive-p) (ems-interactive-p)) 'target)
    '(list '(ems-interactive-p) (ems-interactive-p 'target)))))

(ert-deftest emacsvox-converter-refuses-positional-argument-access ()
  "Advice using `ad-get-arg' is reported instead of partially converted."
  (let ((ems-manual-review-items nil)
        (form
         '(defadvice target (after emacsvox)
            (message "%s" (ad-get-arg 0)))))
    (should-not (ems--convert-defadvice-form form))
    (should
     (equal
      (plist-get (car ems-manual-review-items) :reasons)
      '("uses ad-get-arg")))))

(ert-deftest emacsvox-converter-refuses-around-advice ()
  "Even apparently simple around advice requires manual semantic review."
  (let ((ems-manual-review-items nil)
        (form
         '(defadvice target (around emacsvox)
            (let ((inhibit-message t)) ad-do-it))))
    (should-not (ems--convert-defadvice-form form))
    (should
     (equal
      (plist-get (car ems-manual-review-items) :reasons)
      '("advice class around requires manual review" "uses ad-do-it")))))

(ert-deftest emacsvox-converter-helper-names-include-advice-name ()
  "Different named advice on one target cannot overwrite its helper."
  (should
   (eq
    (ems--generate-advice-function-name 'target 'first 'after)
    'ems--target-first-after))
  (should
   (eq
    (ems--generate-advice-function-name 'target 'second 'after)
    'ems--target-second-after)))

(ert-deftest emacsvox-converter-buffer-leaves-unsafe-and-generated-forms ()
  "Buffer conversion changes safe top-level forms and reports everything else."
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert
     "(defadvice safe-target (after emacsvox)\n"
     "  (when (ems-interactive-p) (message \"safe\")))\n\n"
     "  (defadvice unsafe-target (after emacsvox)\n"
     "    (message \"%s\" (ad-get-arg 0)))\n\n"
     "(defmacro generated-advice (target)\n"
     "  `(defadvice ,target (after emacsvox)\n"
     "     (message \"generated\")))\n")
    (let ((stats (ems-convert-buffer)))
      (should (= 1 (plist-get stats :converted)))
      (should (= 1 (plist-get stats :skipped)))
      (should (= 1 (plist-get stats :nested)))
      (should (= 2 (length (plist-get stats :manual-review)))))
    (goto-char (point-min))
    (should (search-forward "ems--safe-target-emacsvox-after" nil t))
    (should (search-forward "(defadvice unsafe-target" nil t))
    (should (search-forward "`(defadvice ,target" nil t))))

(provide 'emacsvox-converter-tests)
;;; emacsvox-converter-tests.el ends here
