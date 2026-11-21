;;; emacsvox-caps-lock-tests.el --- Caps Lock announcement tests -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Capture submissions and exercise real asynchronous process cleanup.
;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'emacsvox-caps-lock)
(require 'tts-speak)

(defmacro emacsvox-caps-lock-test--with-watcher (&rest body)
  "Run BODY with isolated watcher state and captured speech.
Bind `focused' to the simulated display and `spoken' to submissions."
  (declare (indent 0) (debug t))
  `(let ((emacsvox-caps-lock-mode nil)
         (emacsvox-caps-lock-reminder-presentation 'spoken)
         (emacsvox-caps-lock--timer nil)
         (emacsvox-caps-lock--deadline nil)
         (emacsvox-caps-lock--process nil)
         (emacsvox-caps-lock--program nil)
         (emacsvox-caps-lock--display nil)
         (emacsvox-caps-lock--focus-pending nil)
         (emacsvox-caps-lock--reminder-pending nil)
         (emacsvox-caps-lock--input-count num-nonmacro-input-events)
         (emacsvox-caps-lock--modifier-program nil)
         (emacsvox-caps-lock--modifier-process nil)
         (emacsvox-caps-lock--modifier-deadline nil)
         (emacsvox-caps-lock--modifier-retry-at 0)
         (emacsvox-caps-lock--modifier-error nil)
         (emacsvox-caps-lock--states (make-hash-table :test #'equal))
         (emacsvox-caps-lock--retry-at 0)
         (emacsvox-caps-lock--last-error nil)
         (after-focus-change-function nil)
         (post-command-hook nil)
         (kill-emacs-hook nil)
         (focused ":test") spoken)
     (cl-letf (((symbol-function 'emacsvox-caps-lock--focused-display)
                (lambda () focused))
               ((symbol-function 'emacsvox-aural-submit)
                (lambda (&rest args) (push args spoken))))
       (unwind-protect (progn ,@body)
         (emacsvox-caps-lock-mode -1)))))

(defun emacsvox-caps-lock-test--wait (predicate)
  "Wait up to three seconds for PREDICATE while processing callbacks."
  (let ((end (+ (float-time) 3)))
    (while (and (not (funcall predicate)) (< (float-time) end))
      (accept-process-output nil 0.01))
    (should (funcall predicate))))

(ert-deftest emacsvox-caps-lock-parses-named-state ()
  "Read the named indicator regardless of LED masks or other lock states."
  (should (eq 'off (emacsvox-caps-lock--parse
                   "LED mask: 00000001\n  03: Caps Lock:   off  01: Num Lock: on\n")))
  (should (eq 'on (emacsvox-caps-lock--parse
                  "LED mask: 00000000\n  00: Caps Lock: on  01: Num Lock: off")))
  (dolist (output '("" "Caps Lock: unknown" "Caps Lock: only" "Num Lock: on"))
    (should-not (emacsvox-caps-lock--parse output))))

(ert-deftest emacsvox-caps-lock-default-tone-preserves-speech ()
  "The default reminder resolves to an overlay tone without text or a speech stop."
  (let ((emacsvox-caps-lock-reminder-presentation
         (eval (car (get 'emacsvox-caps-lock-reminder-presentation 'standard-value)) t))
        (emacsvox-caps-lock-reminder-tone
         '(:pitch 725 :duration 60 :volume 0.45 :shape (:waveform triangle)))
        submissions spoken)
    (cl-letf (((symbol-function 'emacsvox-aural-submit-actions)
               (lambda (&rest args) (push args submissions)))
              ((symbol-function 'emacsvox-aural-submit)
               (lambda (&rest args) (push args spoken))))
      (emacsvox-caps-lock--remind)
      (emacsvox-caps-lock--remind t))
    (should-not spoken)
    (should (= (length submissions) 2))
    (dolist (submission submissions)
      (should (eq (plist-get submission :lane) 'main))
      (should (eq (plist-get submission :interruption-policy) 'none))
      (should (eq (plist-get submission :delivery-policy) 'ordered))
      (let* ((render (emacsvox-aural-resolve-active nil (plist-get submission :context)))
             (actions (emacsvox-aural-render-plan-before render))
             (tone (car actions)))
        (should (= (length actions) 1))
        (should (eq (emacsvox-aural-action-kind tone) 'tone))
        (should (eq (emacsvox-aural-action-audio-mode tone) 'overlay))
        (should (= (emacsvox-aural-action-pitch tone) 725))
        (should (= (emacsvox-aural-action-duration tone) 60))
        (should (= (emacsvox-aural-action-volume tone) 0.45))
        (should (equal (emacsvox-aural-action-shape tone) '(:waveform triangle)))))))

(ert-deftest emacsvox-caps-lock-tone-delivery-retains-active-letter ()
  "Real reminder delivery preserves active speech and sends its overlay now."
  (dolist (immediate '(nil t))
    (let* ((speaker (make-pipe-process :name "caps-tone-delivery" :noquery t))
           (tts-speaker-process speaker)
           (tts-notify-process nil)
           (tts-stop-immediately t)
           (tts-stopped-hook nil)
           (tts--tracked-dispatches (make-hash-table :test #'eql))
           (tts--marker-dispatches (make-hash-table :test #'eql))
           (tts--dispatch-lifecycles (make-hash-table :test #'eql))
           (emacsvox-aural--pending-deliveries (make-hash-table :test #'equal))
           (emacsvox-caps-lock-reminder-presentation 'tone)
           (emacsvox-aural-user-rules nil)
           (emacsvox-aural-session-rules nil)
           (emacsvox-aural-buffer-rules nil)
           writes terminal)
      (unwind-protect
          (progn
            (emacsvox-aural-enable-presentation-tone speaker 3)
            ;; Represent a letter already handed to the speech worker.
            (puthash 77 (cons speaker (lambda (&rest event) (push event terminal)))
                     tts--tracked-dispatches)
            (cl-letf (((symbol-function 'process-send-string)
                       (lambda (process command)
                         (should (eq process speaker))
                         (push command writes))))
              (emacsvox-caps-lock--remind immediate))
            (should (gethash 77 tts--tracked-dispatches))
            (should-not terminal)
            (should-not (member "s\n" writes))
            (should (zerop (hash-table-count emacsvox-aural--pending-deliveries)))
            (should (string-match-p "emacsvox_tone 3 overlay "
                                    (mapconcat #'identity writes ""))))
        (emacsvox-aural-cancel-pending-deliveries speaker)
        (delete-process speaker)))))

(ert-deftest emacsvox-caps-lock-tone-customization-rejects-invalid-values ()
  "Invalid Customize input must leave the working tone intact."
  (let ((before (copy-tree emacsvox-caps-lock-reminder-tone)))
    (should-error (funcall (get 'emacsvox-caps-lock-reminder-tone 'custom-set)
                           'emacsvox-caps-lock-reminder-tone
                           '(:pitch -20 :duration 40 :volume 0.4)))
    (should (equal before emacsvox-caps-lock-reminder-tone))))

(ert-deftest emacsvox-caps-lock-baseline-and-changes ()
  "Start silently, then announce each observed change once on the main lane."
  (emacsvox-caps-lock-test--with-watcher
    (setq emacsvox-caps-lock-mode t)
    (emacsvox-caps-lock--accept focused 'off)
    (should-not spoken)
    (dolist (state '(off on on off off))
      (emacsvox-caps-lock--accept focused state))
    (should (equal (mapcar #'car (reverse spoken)) '("Caps Lock on" "Caps Lock off")))
    (dolist (submission spoken)
      (should (eq (plist-get (cdr submission) :lane) 'main))
      (should (eq (plist-get (cdr submission) :interruption-policy) 'lane))
      (should (eq (plist-get (cdr submission) :delivery-policy) 'replaceable)))))

(ert-deftest emacsvox-caps-lock-focus-return ()
  "Each focus gain warns when on, including unchanged state, and is quiet off."
  (emacsvox-caps-lock-test--with-watcher
    (setq emacsvox-caps-lock-mode t)
    (cl-letf (((symbol-function 'emacsvox-caps-lock--query) #'ignore))
      (emacsvox-caps-lock--poll)
      (emacsvox-caps-lock--accept focused 'on)
      (should (equal (mapcar #'car spoken) '("Caps Lock on")))
      (setq focused nil)
      (emacsvox-caps-lock--poll)
      (emacsvox-caps-lock--accept ":test" 'off)
      (should (= (length spoken) 1))
      (setq focused ":test")
      (emacsvox-caps-lock--poll)
      (emacsvox-caps-lock--accept focused 'on)
      (emacsvox-caps-lock--accept focused 'on)
      (should (equal (mapcar #'car spoken) '("Caps Lock on" "Caps Lock on")))
      (setq focused nil)
      (emacsvox-caps-lock--poll)
      (setq focused ":test")
      (emacsvox-caps-lock--poll)
      (emacsvox-caps-lock--accept focused 'off)
      (should (= (length spoken) 2))
      ;; Once focused, actual toggles still announce both on and off.
      (emacsvox-caps-lock--accept focused 'on)
      (emacsvox-caps-lock--accept focused 'off)
      (should (equal (mapcar #'car spoken)
                     '("Caps Lock off" "Caps Lock on" "Caps Lock on" "Caps Lock on"))))))

(ert-deftest emacsvox-caps-lock-key-reminders-use-current-state ()
  "A key requests a fresh state; reminders append once and are quiet when off."
  (emacsvox-caps-lock-test--with-watcher
    (let ((num-nonmacro-input-events 10) (last-input-event ?A)
          (this-command 'self-insert-command))
      (setq emacsvox-caps-lock-mode t emacsvox-caps-lock--input-count 10)
      (emacsvox-caps-lock--accept focused 'on)
      (cl-incf num-nonmacro-input-events)
      (emacsvox-caps-lock--observe-input)
      (should-not spoken)
      (emacsvox-caps-lock--accept focused 'on)
      (should (equal (mapcar #'car spoken) '("Caps Lock")))
      (should (eq (plist-get (cdar spoken) :interruption-policy) 'none))
      (emacsvox-caps-lock--observe-input)
      (emacsvox-caps-lock--accept focused 'on)
      (should (= (length spoken) 1))
      (cl-incf num-nonmacro-input-events)
      (emacsvox-caps-lock--observe-input)
      (emacsvox-caps-lock--accept focused 'off)
      (should (equal (mapcar #'car spoken) '("Caps Lock off" "Caps Lock")))
      (cl-incf num-nonmacro-input-events)
      (emacsvox-caps-lock--observe-input)
      (emacsvox-caps-lock--accept focused 'off)
      (should (= (length spoken) 2)))))

(ert-deftest emacsvox-caps-lock-ignores-mouse-focus-macros-and-stop ()
  "Non-key events and explicit speech stops never schedule a reminder."
  (emacsvox-caps-lock-test--with-watcher
    (let ((num-nonmacro-input-events 10) (this-command 'self-insert-command))
      (setq emacsvox-caps-lock-mode t emacsvox-caps-lock--input-count 10)
      (dolist (last-input-event '(nil focus-in focus-out switch-frame help-echo
                                     mouse-1 wheel-up (mouse-1 (nil 1 (0 . 0) 0))))
        (cl-incf num-nonmacro-input-events)
        (emacsvox-caps-lock--observe-input)
        (ert-info ((format "Unexpected reminder for %S" last-input-event))
          (should-not emacsvox-caps-lock--reminder-pending)))
      (let ((last-input-event ?s) (this-command 'tts-stop))
        (setq emacsvox-caps-lock--reminder-pending t)
        (cl-incf num-nonmacro-input-events)
        (emacsvox-caps-lock--observe-input)
        (should-not emacsvox-caps-lock--reminder-pending))
      (let ((last-input-event ?a) (executing-kbd-macro [97]))
        (cl-incf num-nonmacro-input-events)
        (emacsvox-caps-lock--observe-input)
        (should-not emacsvox-caps-lock--reminder-pending)))))

(ert-deftest emacsvox-caps-lock-modifier-records-and-cleanup ()
  "Split helper records work; background, malformed and retired output cannot speak."
  (emacsvox-caps-lock-test--with-watcher
    (setq emacsvox-caps-lock-mode t)
    (emacsvox-caps-lock--accept focused 'on)
    (let ((process (make-process :name "caps-test-modifier" :command '("cat")
                                 :connection-type 'pipe :noquery t)))
      (setq emacsvox-caps-lock--modifier-process process)
      (process-put process 'display focused)
      (emacsvox-caps-lock--modifier-filter process "rea")
      (should-not spoken)
      (emacsvox-caps-lock--modifier-filter process "dy\nmodi")
      (emacsvox-caps-lock--modifier-filter process "fier\n")
      (should (equal (mapcar #'car spoken) '("Caps Lock")))
      (should (eq (plist-get (cdar spoken) :interruption-policy) 'lane))
      (setq focused nil)
      (emacsvox-caps-lock--modifier-filter process "modifier\n")
      (should (= (length spoken) 1))
      (setq focused ":test")
      (emacsvox-caps-lock--modifier-filter process (make-string 129 ?x))
      (should-not (process-live-p process))
      (should emacsvox-caps-lock--modifier-error)
      (emacsvox-caps-lock--modifier-filter process "modifier\n")
      (should (= (length spoken) 1)))))

(ert-deftest emacsvox-caps-lock-displays-have-separate-baselines ()
  "Moving to another display must not look like a Caps Lock toggle."
  (emacsvox-caps-lock-test--with-watcher
    (setq emacsvox-caps-lock-mode t)
    (emacsvox-caps-lock--accept focused 'off)
    (setq focused ":other")
    (emacsvox-caps-lock--accept focused 'on)
    (should-not spoken)
    (setq focused ":test")
    (emacsvox-caps-lock--accept focused 'on)
    (should (equal (mapcar #'car spoken) '("Caps Lock on")))))

(ert-deftest emacsvox-caps-lock-async-query-and-failure ()
  "Use actual process callbacks; a failed query never means Caps Lock off."
  (emacsvox-caps-lock-test--with-watcher
    (let ((make (symbol-function 'make-process))
          (default-directory "/no-such-caps-lock-working-directory/")
          (delete-exited-processes nil)
          (output "printf 'Caps Lock: off\\n'"))
      (cl-letf (((symbol-function 'make-process)
                 (lambda (&rest args)
                   (should (equal (getenv "LC_ALL") "C"))
                   (should (equal (cdr (plist-get args :command))
                                  '("-display" ":test" "-q")))
                   (apply make (plist-put args :command (list "sh" "-c" output))))))
        (setq emacsvox-caps-lock-mode t emacsvox-caps-lock--program "xset")
        (dolist (command '("printf 'Caps Lock: off\\n'"
                           "printf 'Caps Lock: on\\n'" "exit 1"))
          (setq output command)
          (emacsvox-caps-lock--poll)
          (emacsvox-caps-lock-test--wait
           (lambda () (not emacsvox-caps-lock--process))))
        (should (equal (mapcar #'car spoken) '("Caps Lock on")))
        (should (eq (gethash focused emacsvox-caps-lock--states) 'on))
        (should emacsvox-caps-lock--last-error)
        (should (> emacsvox-caps-lock--retry-at (float-time)))
        (emacsvox-caps-lock--poll)
        (should-not emacsvox-caps-lock--process)
        (should-not (cl-find "emacsvox-caps-lock" (process-list)
                             :key #'process-name :test #'equal))))))

(ert-deftest emacsvox-caps-lock-pending-query-lifecycle ()
  "One query at a time; losing focus, timeout and disable clean up promptly."
  (emacsvox-caps-lock-test--with-watcher
    (let ((make (symbol-function 'make-process)) (starts 0) old buffer)
      (cl-letf (((symbol-function 'make-process)
                 (lambda (&rest args)
                   (cl-incf starts)
                   (apply make (plist-put args :command '("cat"))))))
        (setq emacsvox-caps-lock-mode t emacsvox-caps-lock--program "xset")
        (emacsvox-caps-lock--poll)
        (setq old emacsvox-caps-lock--process buffer (process-buffer old))
        (emacsvox-caps-lock--poll)
        (should (= starts 1))
        (setq focused nil)
        (emacsvox-caps-lock--poll)
        (should-not (process-live-p old))
        (should-not (buffer-live-p buffer))
        (should-not emacsvox-caps-lock--deadline)
        (setq focused ":test")
        (emacsvox-caps-lock--poll)
        ;; A completion or timeout from the retired query cannot cancel its successor.
        (emacsvox-caps-lock--finished old "finished")
        (emacsvox-caps-lock--timeout old)
        (should (process-live-p emacsvox-caps-lock--process))
        (setq old emacsvox-caps-lock--process)
        (emacsvox-caps-lock--timeout old)
        (should-not (process-live-p old))
        (should emacsvox-caps-lock--last-error)
        (emacsvox-caps-lock--poll)
        (should (= starts 2))
        (setq emacsvox-caps-lock--retry-at 0)
        (emacsvox-caps-lock--poll)
        (setq old emacsvox-caps-lock--process)
        (emacsvox-caps-lock-mode -1)
        (should-not (process-live-p old))
        (should-not emacsvox-caps-lock--process)
        (should-not spoken)))))

(ert-deftest emacsvox-caps-lock-start-failure-is-retried ()
  "A disappeared utility neither leaks a buffer nor changes the cached state."
  (emacsvox-caps-lock-test--with-watcher
    (setq emacsvox-caps-lock-mode t emacsvox-caps-lock--program "/no-such-xset")
    (emacsvox-caps-lock--accept focused 'on)
    (let ((buffers (buffer-list)))
      (emacsvox-caps-lock--poll)
      (should-not (cl-set-difference (buffer-list) buffers)))
    (should emacsvox-caps-lock--last-error)
    (should-not spoken)
    (should (eq (gethash focused emacsvox-caps-lock--states) 'on))))

(ert-deftest emacsvox-caps-lock-enable-disable-and-missing-utility ()
  "Enabling twice leaves one timer; disabling removes hooks and pending work."
  (emacsvox-caps-lock-test--with-watcher
    (cl-letf (((symbol-function 'executable-find) (lambda (_) "/test/xset")))
      (emacsvox-caps-lock-mode 1)
      (let ((first emacsvox-caps-lock--timer))
        (emacsvox-caps-lock-mode 1)
        (should-not (memq first timer-list)))
      (should (memq emacsvox-caps-lock--timer timer-list))
      (should (functionp after-focus-change-function))
      (should (memq #'emacsvox-caps-lock--poll post-command-hook))
      (emacsvox-caps-lock-mode -1)
      (should-not emacsvox-caps-lock--timer)
      (should-not after-focus-change-function)
      (should-not (memq #'emacsvox-caps-lock--poll post-command-hook))
      (should-not (memq #'emacsvox-caps-lock--stop kill-emacs-hook)))
    (cl-letf (((symbol-function 'executable-find) (lambda (_) nil)))
      (should-error (emacsvox-caps-lock-mode 1) :type 'user-error)
      (should-not emacsvox-caps-lock-mode)
      (should-not emacsvox-caps-lock--timer)
      (should-not after-focus-change-function))))

(ert-deftest emacsvox-caps-lock-saved-mode-restores-in-fresh-emacs ()
  "A saved global mode activates its watcher through the generated autoload."
  (emacsvox-caps-lock-test--with-watcher
    (let* ((directory (make-temp-file "emacsvox-caps-lock-custom-" t))
           (custom-file (expand-file-name "custom.el" directory))
           (user-init-file custom-file)
           (properties (copy-tree (symbol-plist 'emacsvox-caps-lock-mode))))
      (unwind-protect
          (progn
            (customize-save-variable 'emacsvox-caps-lock-mode t)
            (with-temp-buffer
              (should
               (zerop
                (call-process
                 (expand-file-name invocation-name invocation-directory) nil t nil
                 "-Q" "--batch" "-L" emacsvox-lisp-directory
                 "-l" "emacsvox-preamble" "-l" "emacsvox-loaddefs"
                 "--eval"
                 (format
                  "(progn (load %S nil t) (prin1 (list emacsvox-caps-lock-mode (timerp emacsvox-caps-lock--timer) (symbol-file 'emacsvox-caps-lock-mode))) (emacsvox-caps-lock-mode -1))"
                  custom-file))))
              (should (string-match-p "(t t \".*emacsvox-caps-lock\\.elc?\")"
                                      (buffer-string)))))
        (setplist 'emacsvox-caps-lock-mode properties)
        (when (get-file-buffer custom-file) (kill-buffer (get-file-buffer custom-file)))
        (delete-directory directory t)))))

(provide 'emacsvox-caps-lock-tests)
;;; emacsvox-caps-lock-tests.el ends here
