;;; emacsvox-region-tests.el --- Region editing advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated region-editing advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--region-direct-advice
  '((kill-ring-save :around
     emacsvox--advice-kill-ring-save-around)
    (delete-region :around
     emacsvox--advice-delete-region-around)
    (kill-region :around
     emacsvox--advice-kill-region-around)
    (completion-kill-region :around
     emacsvox--advice-completion-kill-region-around)
    (downcase-region :after
     emacsvox--advice-downcase-region-after)
    (upcase-region :after
     emacsvox--advice-upcase-region-after))
  "Region-editing commands using individually named native advice.")

(ert-deftest emacsvox-region-advice-is-directly-registered ()
  "Migrated region advice uses native advice directly."
  (dolist (entry emacsvox-test--region-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-region-deletion-calls-original-once ()
  "Interactive deletion counts first, calls once, and preserves its result."
  (with-temp-buffer
    (insert "one\ntwo\nthree\n")
    (let ((ems--interactive-fn-name 'delete-region)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'tts-speak) #'ignore)
                ((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push
                    (list 'message
                          (apply #'format format-string arguments))
                    events))))
        (should
         (eq
          (emacsvox--advice-delete-region-around
           (lambda (beginning end)
             (cl-incf calls)
             (push (list 'original beginning end) events)
             (delete-region beginning end)
             'delete-result)
           (point-min) (point-max))
          'delete-result)))
      (should (= calls 1))
      (should (= (point-min) (point-max)))
      (should
       (equal
        (nreverse events)
        '((original 1 15)
          (icon delete-object)
          (message "Killed region containing 3 lines")))))))

(ert-deftest emacsvox-kill-region-preserves-optional-argument ()
  "Interactive kill advice passes its optional argument through unchanged."
  (let ((ems--interactive-fn-name 'kill-region)
        (calls 0)
        observed-arguments)
    (cl-letf (((symbol-function 'tts-speak) #'ignore)
              ((symbol-function 'emacsvox-icon) #'ignore)
              ((symbol-function 'message) #'ignore)
              ((symbol-function 'count-lines)
               (lambda (beginning end)
                 (should (= beginning 2))
                 (should (= end 7))
                 1)))
      (should
       (eq
        (emacsvox--advice-kill-region-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (setq observed-arguments arguments)
           'kill-result)
         2 7 'region)
        'kill-result)))
    (should (= calls 1))
    (should (equal observed-arguments '(2 7 region)))))

(ert-deftest emacsvox-region-deletion-is-quiet-programmatically ()
  "Programmatic region deletion calls once without feedback."
  (let ((ems--interactive-fn-name nil)
        (calls 0)
        feedback)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (&rest _) (setq feedback t)))
              ((symbol-function 'tts-speak)
               (lambda (&rest _) (setq feedback t)))
              ((symbol-function 'message)
               (lambda (&rest _) (setq feedback t)))
              ((symbol-function 'count-lines)
               (lambda (&rest _)
                 (setq feedback t)
                 1)))
      (should
       (eq
        (emacsvox--advice-completion-kill-region-around
         (lambda (&rest _)
           (cl-incf calls)
           'completion-result)
         1 2)
        'completion-result)))
    (should (= calls 1))
    (should-not feedback)))

(ert-deftest emacsvox-region-case-feedback-uses-explicit-range ()
  "Case conversion reports its arguments without consulting the mark."
  (with-temp-buffer
    (insert "one\ntwo\nthree\n")
    (set-marker (mark-marker) nil)
    (let ((ems--interactive-fn-name 'downcase-region)
          events)
      (cl-letf (((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push
                    (apply #'format format-string arguments)
                    events))))
        (emacsvox--advice-upcase-region-after
         (point-min) (point-max) nil)
        (emacsvox--advice-downcase-region-after
         (point-min) (point-max) nil))
      (should
       (equal events
              '("Downcased region containing 3 lines"))))))

(ert-deftest emacsvox-region-kill-and-copy-use-main-speech ()
  "Kill and copy replace main speech once without notification duplicates."
  (dolist (command '(kill-region kill-ring-save))
    (with-temp-buffer
      (insert "one\ntwo\nthree\n")
      (goto-char (point-min))
      (set-mark (point-max))
      (let ((ems--interactive-fn-name command)
            (emacsvox-speak-messages t)
            (kill-ring nil)
            (interprogram-cut-function nil)
            (select-active-regions nil)
            spoken notifications displayed policies)
        (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
                  ((symbol-function 'tts-stop) #'ignore)
                  ((symbol-function 'tts--speak)
                   (lambda (text)
                     (should emacsvox-aural-submission-controls-interruption)
                     (push text spoken)
                     (push (list emacsvox-aural-submission-lane
                                 emacsvox-aural-submission-delivery-policy
                                 emacsvox-aural-submission-replacement-key
                                 emacsvox-aural-submission-interruption-policy)
                           policies)))
                  ((symbol-function 'tts-notify)
                   (lambda (&rest args) (push args notifications)))
                  ((symbol-function 'message)
                   (lambda (format-string &rest arguments)
                     (setq displayed (apply #'format format-string arguments))
                     (when emacsvox-speak-messages
                       (tts-notify displayed)))))
          (funcall-interactively command (point-min) (point-max)))
        (should (equal spoken
                       (list (if (eq command 'kill-region)
                                 "Killed region containing 3 lines"
                               "region containing 3 lines copied to kill ring "))))
        (should (equal displayed (car spoken)))
        (should-not notifications)
        (should (equal policies '((main replaceable speaker lane))))
        (should (equal (car kill-ring) "one\ntwo\nthree\n"))
        (should (equal (buffer-string)
                       (if (eq command 'kill-region) "" "one\ntwo\nthree\n")))))))

(ert-deftest emacsvox-copy-stops-before-visual-feedback ()
  "Copy interrupts immediately, skips blinking and silences copy messages."
  (let ((ems--interactive-fn-name 'kill-ring-save)
        (emacsvox-speak-messages t)
        (copy-region-blink-delay 1)
        events)
    (cl-letf (((symbol-function 'tts-stop)
               (lambda (&optional all)
                 (should-not all)
                 (push 'stop events))))
      (should
       (eq (emacsvox--advice-kill-ring-save-around
            (lambda (&rest args)
              (should (equal args '(1 8 region)))
              (should-not emacsvox-speak-messages)
              (should (zerop copy-region-blink-delay))
              (push 'copy-and-visual-feedback events)
              'copied)
            1 8 'region)
           'copied)))
    (should (equal (nreverse events) '(stop copy-and-visual-feedback)))
    (should emacsvox-speak-messages)
    (should (= copy-region-blink-delay 1))))

(ert-deftest emacsvox-copy-programmatic-call-does-not-interrupt ()
  "Programmatic copying preserves message speech and does not stop audio."
  (let ((ems--interactive-fn-name nil)
        (emacsvox-speak-messages t))
    (cl-letf (((symbol-function 'tts-stop)
               (lambda (&rest _) (ert-fail "Unexpected interruption"))))
      (should
       (eq (emacsvox--advice-kill-ring-save-around
            (lambda (&rest _)
              (should emacsvox-speak-messages)
              'copied)
            1 8)
           'copied)))))

(ert-deftest emacsvox-copy-graphical-feedback-stops-first ()
  "Visible and off-screen copy feedback cannot delay or duplicate speech."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (dolist (offscreen '(nil t))
      (with-temp-buffer
        (dotimes (_ (if offscreen 200 3)) (insert "sample line\n"))
        (goto-char (point-min))
        (set-mark (point-max))
        (set-window-buffer (selected-window) (current-buffer))
        (set-window-start (selected-window) (point-min))
        (redisplay t)
        (should (eq (not (pos-visible-in-window-p (mark))) offscreen))
        (let ((emacsvox-speak-messages t)
              (emacsvox-last-message nil)
              (kill-ring nil) (kill-ring-yank-pointer nil)
              (interprogram-cut-function nil)
              (select-active-regions nil)
              (transient-mark-mode nil)
              (copy-region-blink-predicate #'always)
              (copy-region-blink-delay 1)
              started count-time events notifications)
          (let ((probe (lambda (original &rest args)
                         (should-not emacsvox-speak-messages)
                         (push 'visual-feedback events)
                         (apply original args))))
            (advice-add 'indicate-copied-region :around probe)
            (unwind-protect
                (cl-letf (((symbol-function 'tts-stop)
                           (lambda (&rest _) (push 'stop events)))
			  ((symbol-function 'emacsvox-icon) #'ignore)
			  ((symbol-function 'tts-notify)
			   (lambda (&rest args) (push args notifications)))
			  ((symbol-function 'emacsvox-aural--submit-content)
			   (lambda (_text _actions)
                             (setq count-time (float-time))
                             (push 'count events) nil)))
		  (setq started (float-time))
                  (call-interactively #'kill-ring-save))
              (advice-remove 'indicate-copied-region probe)))
          (should-not notifications)
          (should (= copy-region-blink-delay 1))
          (let ((emacsvox-speak-messages nil))
            (message "Copy feedback (%s): %.1f ms"
                     (if offscreen "off-screen" "visible")
                     (* 1000 (- count-time started))))
          (should (< (- count-time started) 0.5))
          (should (equal (nreverse events)
                         '(stop visual-feedback count))))))))

(provide 'emacsvox-region-tests)
;;; emacsvox-region-tests.el ends here
