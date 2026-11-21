;;; emacsvox-ses-tests.el --- SES advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'ses)
(load
 (expand-file-name "../lisp/integrations/emacsvox-ses.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-ses-advice-is-directly-registered ()
  (dolist
      (target '(ses-forward-or-insert ses-recalculate-cell ses-jump))
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (commandp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-ses-feedback-is-target-aware ()
  (let ((ems--interactive-fn-name 'ses-recalculate-cell) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-ses-summarize-current-cell)
               (lambda () (push 'cell events))))
      (emacsvox--advice-ses-forward-or-insert-after)
      (emacsvox--advice-ses-recalculate-cell-after)
      (emacsvox--advice-ses-jump-after))
    (should (equal (nreverse events) '(cell task-done)))))

(ert-deftest emacsvox-ses-moves-and-speaks-native-cell-coordinates ()
  (with-temp-buffer
    (let ((ses-initial-size '(3 . 3))) (ses-mode))
    (ses-goto-print 0 1)
    (let (spoken)
      (cl-letf (((symbol-function 'tts-speak) (lambda (text) (push text spoken))))
        (dolist (step '((emacsvox-ses-forward-row-and-summarize B2)
                        (emacsvox-ses-backward-row-and-summarize B1)
                        (emacsvox-ses-forward-column-and-summarize C1)
                        (emacsvox-ses-backward-column-and-summarize B1)))
          (call-interactively (car step))
          (should (eq (emacsvox-ses-current-cell-symbol) (cadr step)))
          (should (string-prefix-p (format "%s:" (cadr step)) (car spoken))))
        (dolist (edge '((0 0 emacsvox-ses-backward-row-and-summarize)
                        (0 0 emacsvox-ses-backward-column-and-summarize)
                        (2 2 emacsvox-ses-forward-row-and-summarize)
                        (2 2 emacsvox-ses-forward-column-and-summarize)))
          (ses-goto-print (car edge) (cadr edge))
          (let ((before (point)))
            (should-error (funcall (nth 2 edge)) :type 'user-error)
            (should (= before (point)))))
        (should (= (length spoken) 4))))))

(provide 'emacsvox-ses-tests)
