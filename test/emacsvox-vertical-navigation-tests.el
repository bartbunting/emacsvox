;;; emacsvox-vertical-navigation-tests.el --- Graphical navigation regressions -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Exercise real partial-line scrolling and speech without an audio backend.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'emacsvox-preamble)
(load (expand-file-name "../lisp/emacsvox-advice.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil t)

(defun emacsvox-navigation-test--with-window (function)
  "Call FUNCTION in a small graphical window with mixed font heights."
  (should (display-graphic-p))
  (let ((buffer (generate-new-buffer " *navigation regression*"))
        (font (frame-parameter nil 'font))
        (window-resize-pixelwise t))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (set-frame-font (font-spec :family "DejaVu Sans Mono" :size 15) nil t)
          (switch-to-buffer buffer)
          (setq-local header-line-format "Synthetic message"
                      truncate-lines t line-move-visual nil
                      scroll-conservatively 0 scroll-margin 0
                      auto-window-vscroll t)
          (split-window-below)
          (window-resize (selected-window)
                         (- 128 (window-body-height nil t)) nil nil t)
          (funcall function))
      (set-frame-font font nil t)
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(defun emacsvox-navigation-test--insert-text ()
  "Insert ordinary text taller than the frame's default font."
  (insert
   (propertize
    (mapconcat (lambda (n) (format "Row %02d ordinary text" n))
               (number-sequence 1 60) "\n")
    'face (list :font (font-spec :family "DejaVu Sans" :size 17))))
  (goto-char (point-min))
  (set-window-start nil (point-min)))

(ert-deftest emacsvox-navigation-graphical-down-advances-and-speaks-once ()
  "A partly visible ordinary row must not consume Down without advancing."
  (emacsvox-navigation-test--with-window
   (lambda ()
     (emacsvox-navigation-test--insert-text)
     (let (spoken)
       (cl-letf (((symbol-function 'emacsvox-aural-submit)
                  (lambda (text &rest _) (push (substring-no-properties text) spoken)))
                 ((symbol-function 'emacsvox-icon) #'ignore))
         (dotimes (index 35)
           (redisplay t)
           (funcall-interactively #'next-line 1 t)
           (should (= (line-number-at-pos) (+ index 2)))
           (should auto-window-vscroll))
         (redisplay t)
         (funcall-interactively #'next-line 3 t)
         (should (= (line-number-at-pos) 39))
         (redisplay t)
         (funcall-interactively #'next-line -2 t)
         (should (= (line-number-at-pos) 37))
         (should
          (equal (nreverse spoken)
                 (mapcar (lambda (n) (format "Row %02d ordinary text" n))
                         (append (number-sequence 2 36) '(39 37))))))))))

(ert-deftest emacsvox-navigation-graphical-programmatic-movement-is-unchanged ()
  "Programmatic calls retain exactly the native movement and scrolling policy."
  (emacsvox-navigation-test--with-window
   (lambda ()
     (emacsvox-navigation-test--insert-text)
     (let ((ems--interactive-fn-name nil)
           (advice #'emacsvox--advice-next-line-around)
           paths)
       (unwind-protect
           (dolist (enabled '(t nil))
             (unless enabled (advice-remove 'next-line advice))
             (goto-char (point-min))
             (set-window-start nil (point-min))
             (set-window-vscroll nil 0 t)
             (let (path)
               (dotimes (_ 20)
                 (redisplay t)
                 (next-line 1 t)
                 (push (list (point) (window-start) (window-vscroll nil t)) path))
               (push (nreverse path) paths)))
         (advice-add 'next-line :around advice))
       (should (equal (car paths) (cadr paths)))))))

(ert-deftest emacsvox-navigation-graphical-tall-image-keeps-partial-scrolling ()
  "Down and Up can still scroll within an image taller than the window."
  (emacsvox-navigation-test--with-window
   (lambda ()
     (should (image-type-available-p 'pbm))
     (insert-image (create-image (concat "P1\n1 500\n" (make-string 500 ?0)) 'pbm t)
                   "Tall image")
     (insert "\nAfter image\n")
     (goto-char (point-min))
     (set-window-start nil (point-min))
     (redisplay t)
     (should (> (line-pixel-height) (window-body-height nil t)))
     (cl-letf (((symbol-function 'emacsvox-aural-submit) #'ignore)
               ((symbol-function 'emacsvox-icon) #'ignore))
       (let ((origin (point)))
         (funcall-interactively #'next-line 1 t)
         (redisplay t)
         (should (= (point) origin))
         (should (> (window-vscroll nil t) 0))
         (funcall-interactively #'next-line 1 t)
         (redisplay t)
         (let ((scrolled (window-vscroll nil t)))
           (funcall-interactively #'previous-line 1 t)
           (should (< (window-vscroll nil t) scrolled)))
         (should auto-window-vscroll))))))

(provide 'emacsvox-vertical-navigation-tests)
;;; emacsvox-vertical-navigation-tests.el ends here
