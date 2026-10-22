;;; emacsvox-muggles-tests.el --- Managed Muggle lifecycle tests -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'package)
(package-initialize)
(require 'emacsvox-preamble)
(require 'emacsvox-loaddefs)
(require 'emacsvox-optional-module-test-utils)
(defconst emacsvox-muggles-test--suffix
  (if (equal (getenv "EMACSVOX_MUGGLES_TEST_LOAD") "compiled") ".elc" ".el"))
(dolist (entry '(("core/emacsvox-muggles-core" . emacsvox-muggles-enable)
                 ("integrations/emacsvox-muggle-org-navigation" . emacsvox-muggle-org-navigation--begin)
                 ("integrations/emacsvox-muggle-org-table" . emacsvox-muggle-org-table--begin)
                 ("integrations/emacsvox-muggle-navigate" . emacsvox-muggle-navigate--begin)))
  (let ((file (expand-file-name (concat (car entry) emacsvox-muggles-test--suffix)
                                emacsvox-lisp-directory)))
    (load file nil nil t)
    (unless (equal (file-truename file) (file-truename (symbol-file (cdr entry) 'defun)))
      (error "Muggle tests loaded the wrong implementation: %s" file))))

(defmacro emacsvox-muggles-test--isolated (&rest body)
  "Run BODY with private bindings, preferences and speech capture."
  (declare (indent 0))
  `(let ((org-mode-map (copy-keymap org-mode-map))
         (original-global (current-global-map))
         (emacsvox-muggles-preferences nil)
         (emacsvox-muggles--session nil) (emacsvox-muggles--legacy nil)
         (emacsvox-muggles--owned nil) (emacsvox-muggles--errors nil)
         (emacsvox-muggle-org-navigation--hint-state nil)
         (emacsvox-muggle-org-table--hint-state nil)
         (emacsvox-muggle-navigate--hint-state nil)
         (hydra-is-helpful t)
         (hydra-hint-display-type #'message)
         (properties (copy-tree (symbol-plist 'emacsvox-muggles-preferences))))
     (unwind-protect
         (progn
           (use-global-map (copy-keymap original-global))
           (define-key org-mode-map (kbd "C-c C-SPC") nil)
           (global-unset-key (kbd "C-c C-SPC"))
           (define-key org-mode-map (kbd "C-c t") nil)
           (global-unset-key (kbd "C-c t"))
           (global-unset-key (kbd "s-n"))
           (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
                     ((symbol-function 'tts-stop) #'ignore)
                     ;; Org setup synchronizes voice state even without speech.
                     ((symbol-function 'tts--protocol-sync) #'ignore)
                     ((symbol-function 'tts-speak) #'ignore))
             ,@body))
       (when (and hydra-curr-map
                  (memq hydra-curr-body-fn '(emacsvox-muggles-org-nav/body
                                            emacsvox-muggles-org-table/body
                                            emacsvox-muggles-navigate/body)))
         (cl-letf (((symbol-function 'emacsvox-hydra-post) #'ignore)
                   ((symbol-function 'emacsvox-icon) #'ignore)
                   ((symbol-function 'tts-stop) #'ignore))
           (hydra-keyboard-quit)))
       (dolist (id '(org-navigation org-table navigate))
         (emacsvox-muggles--withdraw id))
       (use-global-map original-global)
       (setplist 'emacsvox-muggles-preferences properties))))

(ert-deftest emacsvox-muggles-core-load-is-passive ()
  (emacsvox-optional-module-test-load
   (concat "emacsvox-muggles-core" emacsvox-muggles-test--suffix)
   '(require 'ert)
   '(progn
      (dolist (feature '(org hydra extra-muggles emacsvox-muggles emacsvox-m-player))
        (should-not (featurep feature)))
      (should (commandp 'emacsvox-muggles-org-nav/body))
      (should-not (plist-get (emacsvox-muggles-status 'org-navigation) :enabled))
      (should-not emacsvox-muggles--owned))))

(ert-deftest emacsvox-muggles-direct-entry-loads-optional-library-on-demand ()
  (emacsvox-optional-module-test-load
   (concat "emacsvox-muggles-core" emacsvox-muggles-test--suffix)
   '(progn (require 'ert) (require 'cl-lib)
           (require 'package) (package-initialize)
           (require 'emacsvox-preamble) (require 'emacsvox-loaddefs))
   '(progn
      (should-not (featurep 'emacsvox-muggle-org-navigation))
      (require 'org)
      (with-temp-buffer
        (org-mode)
        (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
                  ((symbol-function 'tts-stop) #'ignore)
                  ((symbol-function 'tts-speak) #'ignore))
          (call-interactively #'emacsvox-muggles-org-nav/body)
          (should (featurep 'emacsvox-muggle-org-navigation))
          (should hydra-curr-map)
          (should-not emacsvox-muggles--owned)
          (hydra-keyboard-quit))))))

(ert-deftest emacsvox-muggles-toggle-preserves-point-text-and-bindings ()
  (emacsvox-muggles-test--isolated
    (with-temp-buffer
      (org-mode)
      (insert "* One\nBody\n* Two\n")
      (goto-char 4)
      (let ((before (list (point) (buffer-string))))
        (dotimes (_ 2)
          (emacsvox-muggles-enable 'org-navigation)
          (should (eq (key-binding (kbd "C-c C-SPC")) 'emacsvox-muggles-org-nav/body)))
        (should (eq (plist-get (emacsvox-muggles-status 'org-navigation) :state) 'active))
        (dotimes (_ 2) (emacsvox-muggles-disable 'org-navigation))
        (should-not (key-binding (kbd "C-c C-SPC")))
        (should (equal before (list (point) (buffer-string))))))))

(ert-deftest emacsvox-muggles-conflicts-and-later-personal-binding-survive ()
  (emacsvox-muggles-test--isolated
    (define-key org-mode-map (kbd "C-c C-SPC") 'my/org-navigation/body)
    (emacsvox-muggles-enable 'org-navigation)
    (should (eq (plist-get (emacsvox-muggles-status 'org-navigation) :state) 'conflict))
    (should (string-match-p "my/org-navigation/body"
                            (plist-get (emacsvox-muggles-status 'org-navigation) :detail)))
    (emacsvox-muggles-disable 'org-navigation)
    (should (eq (lookup-key org-mode-map (kbd "C-c C-SPC")) 'my/org-navigation/body))
    (define-key org-mode-map (kbd "C-c C-SPC") nil)
    (emacsvox-muggles-enable 'org-navigation)
    (define-key org-mode-map (kbd "C-c C-SPC") 'my/new-command)
    (emacsvox-muggles-disable 'org-navigation)
    (should (eq (lookup-key org-mode-map (kbd "C-c C-SPC")) 'my/new-command))))

(ert-deftest emacsvox-muggles-global-and-prefix-conflicts-are-not-overwritten ()
  (emacsvox-muggles-test--isolated
    (global-set-key (kbd "C-c C-SPC") #'ignore)
    (emacsvox-muggles-enable 'org-navigation)
    (should-not (lookup-key org-mode-map (kbd "C-c C-SPC")))
    (should (eq (plist-get (emacsvox-muggles-status 'org-navigation) :state) 'conflict))
    (global-unset-key (kbd "C-c C-SPC"))
    (define-key org-mode-map (kbd "C-c") #'ignore)
    (emacsvox-muggles-enable 'org-navigation)
    (should (eq (lookup-key org-mode-map (kbd "C-c")) #'ignore))
    (should (eq (plist-get (emacsvox-muggles-status 'org-navigation) :state) 'conflict))))

(ert-deftest emacsvox-muggles-independent-binding-is-not-adopted ()
  (emacsvox-muggles-test--isolated
    (define-key org-mode-map (kbd "C-c C-SPC") 'emacsvox-muggles-org-nav/body)
    (emacsvox-muggles-enable 'org-navigation)
    (should (eq (plist-get (emacsvox-muggles-status 'org-navigation) :state) 'existing))
    (emacsvox-muggles-disable 'org-navigation)
    (should (eq (lookup-key org-mode-map (kbd "C-c C-SPC")) 'emacsvox-muggles-org-nav/body))))

(ert-deftest emacsvox-muggles-explicit-disabled-wins-over-legacy-in-either-order ()
  (emacsvox-muggles-test--isolated
    (setq emacsvox-muggles-preferences '((org-navigation)))
    (emacsvox-muggles--legacy-enable 'org-navigation)
    (should-not (lookup-key org-mode-map (kbd "C-c C-SPC")))
    (setq emacsvox-muggles-preferences nil)
    (emacsvox-muggles--legacy-enable 'org-navigation)
    (should (eq (lookup-key org-mode-map (kbd "C-c C-SPC")) 'emacsvox-muggles-org-nav/body))
    (emacsvox-muggles--set-preferences 'emacsvox-muggles-preferences '((org-navigation)))
    (should-not (lookup-key org-mode-map (kbd "C-c C-SPC")))
    (emacsvox-muggles--legacy-enable 'org-navigation)
    (should-not (lookup-key org-mode-map (kbd "C-c C-SPC")))))

(ert-deftest emacsvox-muggles-enable-disable-before-org-load ()
  (emacsvox-optional-module-test-load
   (concat "emacsvox-muggles-core" emacsvox-muggles-test--suffix)
   '(progn (require 'ert) (require 'package) (package-initialize))
   '(progn
      (emacsvox-muggles-enable 'org-navigation)
      (should (eq (plist-get (emacsvox-muggles-status 'org-navigation) :state) 'waiting))
      (should-not (featurep 'emacsvox-muggle-org-navigation))
      (emacsvox-muggles-disable 'org-navigation)
      (require 'org)
      (should-not (lookup-key org-mode-map (kbd "C-c C-SPC")))
      (should-not (featurep 'emacsvox-muggle-org-navigation)))))

(ert-deftest emacsvox-muggles-missing-dependency-keeps-request-without-installing ()
  (emacsvox-muggles-test--isolated
    (let ((locate (symbol-function 'locate-library)))
      (cl-letf (((symbol-function 'locate-library)
                 (lambda (name &rest args)
                   (unless (equal name "hydra") (apply locate name args))))
                ((symbol-function 'package-install)
                 (lambda (&rest _) (ert-fail "Unexpected dependency installation"))))
        (emacsvox-muggles-enable 'org-navigation)
        (should (plist-get (emacsvox-muggles-status 'org-navigation) :enabled))
        (should (eq (plist-get (emacsvox-muggles-status 'org-navigation) :state) 'missing))
        (should-not emacsvox-muggles--owned)))))

(ert-deftest emacsvox-muggles-enabled-entry-activates-on-org-load-without-collections ()
  (emacsvox-optional-module-test-load
   (concat "emacsvox-muggles-core" emacsvox-muggles-test--suffix)
   '(progn (require 'ert) (require 'package) (package-initialize)
           (require 'emacsvox-preamble) (require 'emacsvox-loaddefs))
   '(progn
      (emacsvox-muggles-enable 'org-navigation)
      (should-not (featurep 'org))
      (require 'org)
      (should (eq (lookup-key org-mode-map (kbd "C-c C-SPC")) 'emacsvox-muggles-org-nav/body))
      (should (featurep 'emacsvox-muggle-org-navigation))
      (dolist (feature '(emacsvox-muggles extra-muggles emacsvox-m-player))
        (should-not (featurep feature))))))

(ert-deftest emacsvox-muggles-save-round-trip-and-explicit-nil ()
  (emacsvox-muggles-test--isolated
    (let* ((directory (make-temp-file "muggles-save-" t))
           (custom-file (expand-file-name "custom.el" directory))
           (user-init-file custom-file))
      (unwind-protect
          (progn
            (emacsvox-muggles-disable 'org-navigation)
            (should-not (file-exists-p custom-file))
            (emacsvox-muggles-save)
            (should (assq 'org-navigation emacsvox-muggles-preferences))
            (should-not emacsvox-muggles--session)
            (emacsvox-optional-module-test-load
             (concat "emacsvox-muggles-core" emacsvox-muggles-test--suffix)
             '(require 'ert)
             `(progn
                (load ,custom-file nil t)
                (emacsvox-muggles--legacy-enable 'org-navigation)
                (should-not (plist-get (emacsvox-muggles-status 'org-navigation) :enabled)))))
        (when (get-file-buffer custom-file) (kill-buffer (get-file-buffer custom-file)))
        (delete-directory directory t)))))

(ert-deftest emacsvox-muggles-failed-save-retains-session-choice ()
  (emacsvox-muggles-test--isolated
    (emacsvox-muggles-enable 'org-navigation)
    (let ((user-init-file "/unused-muggles-test-init"))
      (cl-letf (((symbol-function 'customize-save-variable)
               (lambda (symbol value)
                 (set symbol value)
                 (error "Cannot write settings"))))
        (should-error (emacsvox-muggles-save))))
    (should-not emacsvox-muggles-preferences)
    (should (equal emacsvox-muggles--session '((org-navigation . t))))
    (should (eq (plist-get (emacsvox-muggles-status 'org-navigation) :state) 'active))))

(ert-deftest emacsvox-muggles-enabled-custom-startup-loads-manager-lazily ()
  (emacsvox-muggles-test--isolated
    (let* ((directory (make-temp-file "muggles-startup-" t))
           (custom-file (expand-file-name "custom.el" directory))
           (user-init-file custom-file))
      (unwind-protect
          (progn
            (emacsvox-muggles-enable 'org-navigation)
            (emacsvox-muggles-save)
            (emacsvox-optional-module-test-load
             "emacsvox-loaddefs.el"
             '(progn (require 'ert) (require 'package) (package-initialize)
                     (require 'emacsvox-preamble))
             `(progn
                (should-not (featurep 'emacsvox-muggles-core))
                (load ,custom-file nil t)
                (should (featurep 'emacsvox-muggles-core))
                (require 'org)
                (should (eq (lookup-key org-mode-map (kbd "C-c C-SPC"))
                            'emacsvox-muggles-org-nav/body))
                (should-not (featurep 'extra-muggles)))))
        (when (get-file-buffer custom-file) (kill-buffer (get-file-buffer custom-file)))
        (delete-directory directory t)))))

(ert-deftest emacsvox-muggles-graphical-org-navigation-and-disabled-m-x ()
  (skip-unless (display-graphic-p))
  (emacsvox-muggles-test--isolated
    (save-window-excursion
      (with-temp-buffer
        (switch-to-buffer (current-buffer))
        (org-mode)
        (insert "* First\nFirst body\n* Second\nSecond body\n")
        (goto-char (point-min))
        (emacsvox-muggles-enable 'org-navigation)
        (let (spoken)
          (cl-letf (((symbol-function 'emacsvox-speak-region)
                     (lambda (start end &rest _)
                       (setq spoken (buffer-substring-no-properties start end)))))
            (execute-kbd-macro (kbd "C-c C-SPC n")))
          (should (string-match-p "Second body" spoken)))
        (should (eq hydra-curr-body-fn 'emacsvox-muggles-org-nav/body))
        (should (looking-at "\\* Second"))
        (should-not hydra-is-helpful)
        (execute-kbd-macro (kbd "q"))
        (should hydra-is-helpful)
        (emacsvox-muggles-disable 'org-navigation)
        (execute-kbd-macro (vconcat (kbd "M-x") "emacsvox-muggles-org-nav/body" (kbd "RET")))
        (should (eq hydra-curr-body-fn 'emacsvox-muggles-org-nav/body))
        (emacsvox-muggles-disable 'org-navigation)
        (should-not hydra-curr-map)
        (should hydra-is-helpful)))))

(ert-deftest emacsvox-muggles-wrong-context-preserves-another-hydra ()
  (emacsvox-muggles-test--isolated
    (let ((hydra-curr-body-fn 'another-menu/body)
          (hydra-curr-map (make-sparse-keymap)))
      (with-temp-buffer
        (should-error (call-interactively #'emacsvox-muggles-org-nav/body) :type 'user-error))
      (emacsvox-muggles-disable 'org-navigation)
      (should (eq hydra-curr-body-fn 'another-menu/body))
      (should hydra-curr-map))))

(ert-deftest emacsvox-muggles-hint-restoration-and-failed-entry ()
  (emacsvox-muggles-test--isolated
    (with-temp-buffer
      (org-mode)
      (emacsvox-muggle-org-navigation--begin)
      (should-not hydra-is-helpful)
      (setq hydra-is-helpful t)
      (emacsvox-muggle-org-navigation--restore)
      (should hydra-is-helpful)
      (should-error
       (emacsvox-muggle-org-navigation--enter
        (lambda () (emacsvox-muggle-org-navigation--begin) (error "Entry failed"))))
      (should hydra-is-helpful)
      (should-not emacsvox-muggle-org-navigation--hint-state))))

(ert-deftest emacsvox-muggles-save-refuses-an-unloaded-init ()
  (emacsvox-muggles-test--isolated
    (emacsvox-muggles-enable 'org-navigation)
    (let ((user-init-file nil))
      (should-error (emacsvox-muggles-save) :type 'user-error))
    (should emacsvox-muggles--session)
    (should-not emacsvox-muggles-preferences)))

(ert-deftest emacsvox-muggles-legacy-collection-preserves-personal-and-disabled-choices ()
  (dolist (case '(disabled personal enabled))
    (emacsvox-optional-module-test-load
     (concat "extra-muggles" emacsvox-muggles-test--suffix)
     `(progn
        (require 'ert) (require 'package) (package-initialize)
        (require 'emacsvox-preamble) (require 'emacsvox-loaddefs)
        (require 'info) (require 'org)
        (setq emacsvox-muggles-preferences ,(when (eq case 'disabled) ''((org-navigation))))
        (when (eq ',case 'personal)
          (define-key org-mode-map (kbd "C-c C-SPC") 'my/org-navigation/body)))
     `(progn
        (should (featurep 'extra-muggles))
        (should (equal (lookup-key org-mode-map (kbd "C-c C-SPC"))
                       ',(pcase case ('personal 'my/org-navigation/body)
                                ('enabled 'emacsvox-muggles-org-nav/body))))
        (emacsvox-muggles-disable 'org-navigation)
        (should (equal (lookup-key org-mode-map (kbd "C-c C-SPC"))
                       ',(when (eq case 'personal) 'my/org-navigation/body)))))))


(ert-deftest emacsvox-muggles-new-entries-load-independently-and-passively ()
  (dolist (case '(("emacsvox-muggle-org-table" org-table emacsvox-muggles-org-table/body)
                  ("emacsvox-muggle-navigate" navigate emacsvox-muggles-navigate/body)))
    (emacsvox-optional-module-test-load
     (concat (car case) emacsvox-muggles-test--suffix)
     '(progn (require 'ert) (require 'package) (package-initialize)
             (require 'emacsvox-preamble) (require 'emacsvox-loaddefs)
             (setq muggles-test-global (copy-keymap (current-global-map))))
     `(progn
        (should (commandp ',(nth 2 case)))
        (should (equal muggles-test-global (current-global-map)))
        (should-not (bound-and-true-p hydra-curr-map))
        (dolist (feature '(emacsvox-muggles extra-muggles emacsvox-m-player))
          (should-not (featurep feature)))))))

(ert-deftest emacsvox-muggles-new-entries-toggle-independently ()
  (emacsvox-muggles-test--isolated
    (with-temp-buffer
      (org-mode)
      (insert "| First | Second |\n| A | B |\n")
      (goto-char 3)
      (let ((before (list (point) (buffer-string))))
        (dolist (id '(org-navigation org-table navigate))
          (emacsvox-muggles-enable id)
          (emacsvox-muggles-enable id)
          (should (eq (plist-get (emacsvox-muggles-status id) :state) 'active)))
        (should (equal before (list (point) (buffer-string)))))
      (emacsvox-muggles-disable 'org-table)
      (should-not (lookup-key org-mode-map (kbd "C-c t")))
      (should (eq (key-binding (kbd "s-n")) 'emacsvox-muggles-navigate/body))
      (should (eq (key-binding (kbd "C-c C-SPC")) 'emacsvox-muggles-org-nav/body))
      (emacsvox-muggles-disable 'navigate)
      (should-not (lookup-key (current-global-map) (kbd "s-n"))))))

(ert-deftest emacsvox-muggles-new-bindings-preserve-personal-and-local-overrides ()
  (emacsvox-muggles-test--isolated
    (global-set-key (kbd "s-n") #'ignore)
    (emacsvox-muggles-enable 'navigate)
    (should (eq (plist-get (emacsvox-muggles-status 'navigate) :state) 'conflict))
    (emacsvox-muggles-disable 'navigate)
    (should (eq (lookup-key (current-global-map) (kbd "s-n")) #'ignore))
    (global-unset-key (kbd "s-n"))
    (emacsvox-muggles-enable 'navigate)
    (with-temp-buffer
      (use-local-map (make-sparse-keymap))
      (local-set-key (kbd "s-n") #'forward-char)
      (should (eq (key-binding (kbd "s-n")) #'forward-char)))
    (global-set-key (kbd "s-n") #'backward-char)
    (emacsvox-muggles-disable 'navigate)
    (should (eq (lookup-key (current-global-map) (kbd "s-n")) #'backward-char))
    (define-key org-mode-map (kbd "C-c t") #'ignore)
    (emacsvox-muggles-enable 'org-table)
    (should (eq (plist-get (emacsvox-muggles-status 'org-table) :state) 'conflict))
    (should (eq (lookup-key org-mode-map (kbd "C-c t")) #'ignore))))

(ert-deftest emacsvox-muggles-new-disabled-choices-survive-collection-load ()
  (dolist (order '(before after))
    (emacsvox-optional-module-test-load
     (concat "emacsvox-muggles" emacsvox-muggles-test--suffix)
     `(progn
        (require 'ert) (require 'package) (package-initialize)
        (require 'emacsvox-preamble) (require 'emacsvox-loaddefs)
        (require 'org) (require 'emacsvox-muggles-core)
        (define-key org-mode-map (kbd "C-c t") nil)
        (global-unset-key (kbd "s-n"))
        ,@(when (eq order 'before)
            '((emacsvox-muggles--set-preferences
               'emacsvox-muggles-preferences '((org-table) (navigate))))))
     `(progn
        (should (eq (lookup-key org-mode-map (kbd "C-c t"))
                    ',(unless (eq order 'before) 'emacsvox-muggles-org-table/body)))
        (should (eq (lookup-key (current-global-map) (kbd "s-n"))
                    ',(unless (eq order 'before) 'emacsvox-muggles-navigate/body)))
        (emacsvox-muggles-disable 'org-table)
        (emacsvox-muggles-disable 'navigate)
        (should-not (lookup-key org-mode-map (kbd "C-c t")))
        (should-not (lookup-key (current-global-map) (kbd "s-n")))
        (emacsvox-muggles--legacy-enable 'org-table)
        (emacsvox-muggles--legacy-enable 'navigate)
        (should-not (lookup-key org-mode-map (kbd "C-c t")))
        (should-not (lookup-key (current-global-map) (kbd "s-n")))
        ;; Unconverted collection members remain present.
        (should (eq (lookup-key (current-global-map) (kbd "M-y"))
                    'emacsvox-muggles-yank-pop/yank-pop))))))

(ert-deftest emacsvox-muggles-org-table-deferred-disable-and-direct-entry ()
  (emacsvox-optional-module-test-load
   (concat "emacsvox-muggles-core" emacsvox-muggles-test--suffix)
   '(progn (require 'ert) (require 'cl-lib) (require 'package) (package-initialize)
           (require 'emacsvox-preamble) (require 'emacsvox-loaddefs))
   '(progn
      (should (commandp 'emacsvox-muggles-org-table/body))
      (should (commandp 'emacsvox-muggles-navigate/body))
      (emacsvox-muggles-enable 'org-table)
      (should (eq (plist-get (emacsvox-muggles-status 'org-table) :state) 'waiting))
      (emacsvox-muggles-disable 'org-table)
      (require 'org)
      (should-not (lookup-key org-mode-map (kbd "C-c t")))
      (should-not (featurep 'emacsvox-muggle-org-table))
      (with-temp-buffer
        (org-mode) (insert "| A | B |\n") (goto-char 3)
        (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
                  ((symbol-function 'tts-stop) #'ignore)
                  ((symbol-function 'tts-speak) #'ignore))
          (call-interactively #'emacsvox-muggles-org-table/body)
          (should (eq hydra-curr-body-fn 'emacsvox-muggles-org-table/body))
          (hydra-keyboard-quit)
          (should-not emacsvox-muggles--owned))))))

(ert-deftest emacsvox-muggles-org-table-invalid-context-preserves-active-menu ()
  (emacsvox-muggles-test--isolated
    (with-temp-buffer
      (org-mode) (insert "Not a table\n")
      (let ((hydra-curr-body-fn 'another-menu/body)
            (hydra-curr-map (make-sparse-keymap)))
        (should-error (emacsvox-muggles-org-table/body) :type 'user-error)
        (should (eq hydra-curr-body-fn 'another-menu/body))
        (emacsvox-muggles-disable 'org-table)
        (should hydra-curr-map)))))

(ert-deftest emacsvox-muggles-new-preferences-round-trip ()
  (emacsvox-muggles-test--isolated
    (let* ((directory (make-temp-file "muggles-new-save-" t))
           (custom-file (expand-file-name "custom.el" directory))
           (user-init-file custom-file))
      (unwind-protect
          (progn
            (emacsvox-muggles-enable 'navigate)
            (emacsvox-muggles-disable 'org-table)
            (emacsvox-muggles-save)
            (emacsvox-optional-module-test-load
             (concat "emacsvox-muggles-core" emacsvox-muggles-test--suffix)
             '(progn (require 'ert) (require 'package) (package-initialize)
                     (require 'emacsvox-preamble) (require 'emacsvox-loaddefs))
             `(progn
                (global-unset-key (kbd "s-n"))
                (load ,custom-file nil t)
                (should (eq (lookup-key (current-global-map) (kbd "s-n"))
                            'emacsvox-muggles-navigate/body))
                (require 'org)
                (emacsvox-muggles--legacy-enable 'org-table)
                (should-not (lookup-key org-mode-map (kbd "C-c t")))
                (should-not (featurep 'emacsvox-muggle-org-table)))))
        (when (get-file-buffer custom-file) (kill-buffer (get-file-buffer custom-file)))
        (delete-directory directory t)))))

(ert-deftest emacsvox-muggles-graphical-new-navigation-and-owned-exit ()
  (skip-unless (display-graphic-p))
  (emacsvox-muggles-test--isolated
    (save-window-excursion
      (with-temp-buffer
        (switch-to-buffer (current-buffer))
        (insert "one\ntwo\nthree\n") (goto-char 1)
        (emacsvox-muggles-enable 'navigate)
        (execute-kbd-macro (kbd "s-n n"))
        (should (= (line-number-at-pos) 3))
        (should-not hydra-is-helpful)
        (emacsvox-muggles-disable 'org-table)
        (should (eq hydra-curr-body-fn 'emacsvox-muggles-navigate/body))
        (emacsvox-muggles-disable 'navigate)
        (should-not hydra-curr-map)
        (should hydra-is-helpful)
        ;; Two deliberate toggles still constitute an explicit choice.
        (call-interactively #'emacsvox-muggles-navigate/body)
        (execute-kbd-macro (kbd "s s q"))
        (should-not hydra-is-helpful)
        (setq hydra-is-helpful t)
        (org-mode) (erase-buffer)
        (insert "| A | B |\n| C | D |\n") (goto-char 3)
        (emacsvox-muggles-enable 'org-table)
        (execute-kbd-macro (kbd "C-c t l"))
        (should (= (org-table-current-column) 2))
        (should-not hydra-is-helpful)
        (emacsvox-muggles-disable 'org-table)
        (should-not hydra-curr-map)
        (should hydra-is-helpful)))))


(ert-deftest emacsvox-muggles-navigate-direct-lazy-entry-and-failed-entry ()
  (emacsvox-optional-module-test-load
   (concat "emacsvox-muggles-core" emacsvox-muggles-test--suffix)
   '(progn (require 'ert) (require 'cl-lib) (require 'package) (package-initialize)
           (require 'emacsvox-preamble) (require 'emacsvox-loaddefs)
           (defvar hydra-is-helpful t))
   '(progn
      (should-not (featurep 'emacsvox-muggle-navigate))
      (save-window-excursion
        (with-temp-buffer
          (switch-to-buffer (current-buffer))
          (insert "first\nsecond\nthird\n") (goto-char 1)
          (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
                    ((symbol-function 'tts-stop) #'ignore)
                    ((symbol-function 'tts-speak) #'ignore))
            (let ((hydra-is-helpful t))
              (call-interactively #'emacsvox-muggles-navigate/body)
              (should (= (line-number-at-pos) 2))
              (should-not hydra-is-helpful)
              (hydra-keyboard-quit)
              (should hydra-is-helpful)
              (should-not emacsvox-muggles--owned)
              (should-error
               (emacsvox-muggle-navigate--enter
                (lambda () (emacsvox-muggle-navigate--begin) (error "Failed entry"))))
              (should hydra-is-helpful)
              (should-not emacsvox-muggle-navigate--hint-state))))))))

(provide 'emacsvox-muggles-tests)
;;; emacsvox-muggles-tests.el ends here
