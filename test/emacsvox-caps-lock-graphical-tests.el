;;; emacsvox-caps-lock-graphical-tests.el --- Private X11 checks -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Use make graphical-caps-lock-test; never change the real desktop keyboard.
;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'emacsvox-caps-lock)

(defun emacsvox-caps-lock-test--x11 (&rest args)
  "Apply ARGS with the private display fixture."
  (should (equal (getenv "DISPLAY") (getenv "EMACSVOX_CAPS_LOCK_TEST_DISPLAY")))
  (should (zerop
           (apply #'call-process "python3" nil nil nil
                  (expand-file-name "caps-lock-x11.py"
                                    (file-name-directory
                                     (symbol-file 'emacsvox-caps-lock-test--x11)))
                  args))))

(defun emacsvox-caps-lock-test--display-wait (predicate)
  "Process X events and callbacks for up to three seconds for PREDICATE."
  (let ((deadline (+ (float-time) 3)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (sit-for 0.02))
    (should (funcall predicate))))

(ert-deftest emacsvox-caps-lock-graphical-real-state-and-focus ()
  "Read actual XKB transitions; suppress background speech and catch up on return."
  (should (eq window-system 'x))
  (should (getenv "EMACSVOX_CAPS_LOCK_TEST_DISPLAY"))
  (let ((display (frame-parameter nil 'display)) spoken)
    (cl-letf (((symbol-function 'emacsvox-aural-submit)
               (lambda (text &rest _) (push text spoken))))
      (unwind-protect
          (progn
            (redisplay t)
            (emacsvox-caps-lock-test--x11 "off")
            (emacsvox-caps-lock-test--x11 "focus" (frame-parameter nil 'outer-window-id))
            (emacsvox-caps-lock-test--display-wait (lambda () (eq (frame-focus-state) t)))
            (emacsvox-caps-lock-mode 1)
            (emacsvox-caps-lock-test--display-wait
             (lambda () (eq (gethash display emacsvox-caps-lock--states) 'off)))
            (should-not spoken)
            (emacsvox-caps-lock-test--x11 "on")
            (emacsvox-caps-lock-test--display-wait (lambda () (equal spoken '("Caps Lock on"))))
            (sit-for 0.45)
            (should (equal spoken '("Caps Lock on")))
            (emacsvox-caps-lock-test--x11 "off")
            (emacsvox-caps-lock-test--display-wait (lambda () (= (length spoken) 2)))
            (should (equal spoken '("Caps Lock off" "Caps Lock on")))
            (emacsvox-caps-lock-test--x11 "blur")
            (emacsvox-caps-lock-test--display-wait (lambda () (null (frame-focus-state))))
            (emacsvox-caps-lock-test--x11 "on")
            (sit-for 0.45)
            (should (= (length spoken) 2))
            (should-not emacsvox-caps-lock--process)
            (should-not emacsvox-caps-lock--modifier-process)
            (emacsvox-caps-lock-test--x11 "focus" (frame-parameter nil 'outer-window-id))
            (emacsvox-caps-lock-test--display-wait (lambda () (= (length spoken) 3)))
            (should (equal spoken '("Caps Lock on" "Caps Lock off" "Caps Lock on")))
            ;; Returning with the unchanged on state must warn again.
            (emacsvox-caps-lock-test--x11 "blur")
            (emacsvox-caps-lock-test--display-wait (lambda () (null (frame-focus-state))))
            (emacsvox-caps-lock-test--x11 "focus" (frame-parameter nil 'outer-window-id))
            (emacsvox-caps-lock-test--display-wait (lambda () (= (length spoken) 4)))
            (should (equal (car spoken) "Caps Lock on"))
            ;; Turning off outside Emacs must not produce an off announcement on return.
            (emacsvox-caps-lock-test--x11 "blur")
            (emacsvox-caps-lock-test--display-wait (lambda () (null (frame-focus-state))))
            (emacsvox-caps-lock-test--x11 "off")
            (emacsvox-caps-lock-test--x11 "focus" (frame-parameter nil 'outer-window-id))
            (emacsvox-caps-lock-test--display-wait
             (lambda () (eq (gethash display emacsvox-caps-lock--states) 'off)))
            (sit-for 0.25)
            (should (= (length spoken) 4))
            (emacsvox-caps-lock-mode -1)
            (emacsvox-caps-lock-test--x11 "off")
            (sit-for 0.45)
            (should (= (length spoken) 4))
            (should-not emacsvox-caps-lock--timer)
            (should-not emacsvox-caps-lock--process))
        (emacsvox-caps-lock-mode -1)))))

(defun emacsvox-caps-lock-test--type-native-key (key)
  "Send KEY through the real command loop on the private display."
  (let ((press (run-at-time 0.05 nil #'emacsvox-caps-lock-test--x11 "press" key))
        (release (run-at-time 0.1 nil #'emacsvox-caps-lock-test--x11 "release" key))
        (finish (run-at-time 0.6 nil #'exit-recursive-edit)))
    (unwind-protect (recursive-edit)
      (mapc #'cancel-timer (list press release finish)))))

(defun emacsvox-caps-lock-test--exercise-reminders (presentation)
  "Exercise PRESENTATION with real modifier presses and ordinary typing."
  (should (eq window-system 'x))
  (let ((buffer (generate-new-buffer " *Caps Lock typing test*"))
        (emacsvox-caps-lock-reminder-presentation presentation)
        (reminder (if (eq presentation 'tone) 'tone "Caps Lock")) spoken)
    (cl-letf (((symbol-function 'emacsvox-aural-submit)
               (lambda (text &rest _) (push text spoken)))
              ((symbol-function 'emacsvox-aural-submit-actions)
               (lambda (&rest args)
                 (should (eq (plist-get args :interruption-policy) 'none))
                 (push 'tone spoken))))
      (unwind-protect
          (save-window-excursion
            (switch-to-buffer buffer)
            (fundamental-mode)
            (redisplay t)
            (emacsvox-caps-lock-test--x11 "on")
            (emacsvox-caps-lock-test--x11 "focus" (frame-parameter nil 'outer-window-id))
            (emacsvox-caps-lock-test--display-wait (lambda () (eq (frame-focus-state) t)))
            (emacsvox-caps-lock-mode 1)
            (emacsvox-caps-lock-test--display-wait
             (lambda () (and (equal spoken '("Caps Lock on"))
                             (process-live-p emacsvox-caps-lock--modifier-process)
                             (not emacsvox-caps-lock--modifier-deadline))))
            (dolist (key '("Shift_L" "Control_L" "Alt_L" "Super_L"))
              (let ((before (length spoken)))
                (unwind-protect
                    (progn
                      (emacsvox-caps-lock-test--x11 "press" key)
                      (emacsvox-caps-lock-test--display-wait
                       (lambda () (= (length spoken) (1+ before))))
                      (should (equal (car spoken) reminder)))
                  (emacsvox-caps-lock-test--x11 "release" key))
                (sit-for 0.15)
                (should (= (length spoken) (1+ before)))))
            (setq spoken nil)
            (emacsvox-caps-lock-test--type-native-key "a")
            (should (equal (buffer-string) "A"))
            (should (equal spoken (list reminder)))
            ;; Losing the optional helper leaves ordinary key reminders usable.
            (delete-process emacsvox-caps-lock--modifier-process)
            (emacsvox-caps-lock-test--display-wait
             (lambda () (not emacsvox-caps-lock--modifier-process)))
            (should emacsvox-caps-lock--modifier-error)
            (setq spoken nil)
            (emacsvox-caps-lock-test--type-native-key "b")
            (should (equal (buffer-string) "AB"))
            (should (equal spoken (list reminder)))
            ;; Restart the real helper before testing modifier silence when off.
            (setq emacsvox-caps-lock--modifier-retry-at 0)
            (emacsvox-caps-lock--poll)
            (emacsvox-caps-lock-test--display-wait
             (lambda () (and (process-live-p emacsvox-caps-lock--modifier-process)
                             (not emacsvox-caps-lock--modifier-deadline))))
            ;; Neither typing nor a modifier press reminds when Caps Lock is off.
            (emacsvox-caps-lock-test--x11 "off")
            (emacsvox-caps-lock-test--display-wait
             (lambda () (equal (car spoken) "Caps Lock off")))
            (setq spoken nil)
            (emacsvox-caps-lock-test--type-native-key "c")
            (should (equal (buffer-string) "ABc"))
            (emacsvox-caps-lock-test--x11 "press" "Control_L")
            (emacsvox-caps-lock-test--x11 "release" "Control_L")
            (sit-for 0.25)
            (should-not spoken))
        (emacsvox-caps-lock-mode -1)
        (kill-buffer buffer)))))

(ert-deftest emacsvox-caps-lock-graphical-modifiers-and-typing ()
  "Spoken modifier reminders precede release; normal typing reaches Emacs."
  (emacsvox-caps-lock-test--exercise-reminders 'spoken))

(ert-deftest emacsvox-caps-lock-graphical-tone-modifiers-and-typing ()
  "Tone reminders follow the same physical input without stopping main speech."
  (emacsvox-caps-lock-test--exercise-reminders 'tone))

(provide 'emacsvox-caps-lock-graphical-tests)
;;; emacsvox-caps-lock-graphical-tests.el ends here
