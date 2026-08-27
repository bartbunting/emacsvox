;;; emacsvox-flyspell-tests.el --- Flyspell advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'package)
(package-initialize)
(require 'flyspell)
(load
 (expand-file-name "../lisp/emacsvox-flyspell.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-flyspell-defaults-to-native-completion ()
  "Flyspell correction uses the active standard completion frontend by default."
  (should (eq emacsvox-flyspell-correct 'flyspell-correct))
  (should (featurep 'flyspell-correct))
  (should
   (eq flyspell-correct-interface
       #'emacsvox-flyspell-correct-completing-read)))

(ert-deftest emacsvox-flyspell-native-interface-publishes-suggestion-count ()
  "The native correction interface exposes its bounded candidate context."
  (let (observed)
    (cl-letf (((symbol-function 'flyspell-correct-completing-read)
               (lambda (candidates word)
                 (setq observed
                       (list candidates word
                             emacsvox-flyspell--suggestion-count))
                 "corrected")))
      (should
       (equal
        (emacsvox-flyspell-correct-completing-read
         '("first" "second") "incorect") ; codespell:ignore incorect
        "corrected")))
    (should
     (equal observed '(("first" "second") "incorect" 2))))) ; codespell:ignore incorect

(ert-deftest emacsvox-flyspell-advice-is-directly-registered ()
  (dolist
      (entry
       '((flyspell-buffer :around emacsvox--advice-flyspell-buffer-around)
         (flyspell-region :around emacsvox--advice-flyspell-region-around)
         (flyspell-auto-correct-word
          :around emacsvox--advice-flyspell-auto-correct-word-around)
         (flyspell-unhighlight-at
          :before emacsvox--advice-flyspell-unhighlight-at-before)
         (flyspell-goto-next-error
          :after emacsvox--advice-flyspell-goto-next-error-after)))
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-flyspell-silences-icons-once ()
  (let ((calls 0))
    (should
     (eq 'result
         (emacsvox--advice-flyspell-region-around
          (lambda (&rest args)
            (setq calls (1+ calls))
            (should (equal args '(2 9)))
            (should-not emacsvox-use-icons)
            'result)
          2 9)))
    (should (= calls 1))))

(ert-deftest emacsvox-flyspell-auto-correct-runs-once ()
  (let ((ems--interactive-fn-name 'flyspell-auto-correct-word)
        (flyspell-correct-interface #'flyspell-correct-ido)
        (vertico-mode t)
        (calls 0) events)
    (cl-letf (((symbol-function 'flyspell-get-word)
               (lambda (&rest _) '("corrected")))
              ((symbol-function 'sit-for) (lambda (&rest _) nil))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (should
       (eq 'result
           (emacsvox--advice-flyspell-auto-correct-word-around
            (lambda () (setq calls (1+ calls)) 'result)))))
    (should (= calls 1))
    (should
     (equal (nreverse events)
            '((speak "corrected") (icon select-object))))))

(ert-deftest emacsvox-flyspell-native-completion-does-not-repeat-acceptance ()
  "Vertico-owned correction acceptance is not spoken again by Flyspell."
  (let ((ems--interactive-fn-name 'flyspell-correct-at-point)
        (flyspell-correct-interface
         #'emacsvox-flyspell-correct-completing-read)
        (vertico-mode t)
        events)
    (cl-letf (((symbol-function 'flyspell-get-word)
               (lambda (&rest _) '("corrected")))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-flyspell-correct-at-point-after))
    (should-not events)))

(ert-deftest emacsvox-flyspell-alternate-interface-keeps-fallback-feedback ()
  "An explicitly selected alternate correction interface retains feedback."
  (let ((ems--interactive-fn-name 'flyspell-correct-at-point)
        (flyspell-correct-interface #'flyspell-correct-ido)
        (vertico-mode t)
        events)
    (cl-letf (((symbol-function 'flyspell-get-word)
               (lambda (&rest _) '("corrected")))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-flyspell-correct-at-point-after))
    (should (equal events '((speak "corrected"))))))

(ert-deftest emacsvox-flyspell-programmatic-auto-correct-runs-once-quietly ()
  (let ((calls 0) events)
    (cl-letf (((symbol-function 'tts-speak)
               (lambda (&rest args) (push args events))))
      (should
       (eq 'result
           (emacsvox--advice-flyspell-auto-correct-word-around
            (lambda () (setq calls (1+ calls)) 'result)))))
    (should (= calls 1))
    (should-not events)))

(ert-deftest emacsvox-flyspell-unhighlight-uses-native-position ()
  (with-temp-buffer
    (insert "word")
    (put-text-property 1 5 'personality 'voice-bolden)
    (let ((overlay (make-overlay 1 5)))
      (cl-letf (((symbol-function 'flyspell-overlay-p)
                 (lambda (candidate) (eq candidate overlay))))
        (emacsvox--advice-flyspell-unhighlight-at-before 2))
      (should-not (text-property-any 1 5 'personality 'voice-bolden)))))

(ert-deftest emacsvox-flyspell-defers-optional-correction-advice ()
  (dolist (target emacsvox-flyspell--correct-targets)
    (should
     (fboundp (intern (format "emacsvox--advice-%s-after" target))))
    (when
        (and
         (featurep 'flyspell-correct)
         (fboundp target))
      (should
       (advice-member-p
        (intern (format "emacsvox--advice-%s-after" target))
        target)))))

(ert-deftest emacsvox-flyspell-correction-targets-cover-public-workflows ()
  "Direct, directional, DWIM, and region correction paths receive feedback."
  (should
   (equal
    emacsvox-flyspell--correct-targets
    '(flyspell-correct-next
      flyspell-correct-previous
      flyspell-correct-at-point
      flyspell-correct-wrapper
      flyspell-correct-region))))

(ert-deftest emacsvox-flyspell-hunspell-en-au-detects-known-error ()
  "The configured real spell checker marks a known Australian English error."
  (skip-unless (executable-find "hunspell"))
  (skip-unless
   (or (file-exists-p "/usr/share/hunspell/en_AU.dic")
       (file-exists-p "/usr/share/myspell/en_AU.dic")))
  (let ((ispell-program-name "hunspell")
        (ispell-dictionary "en_AU")
        (ispell-process nil))
    (unwind-protect
        (with-temp-buffer
          (text-mode)
          (insert "This is mispeled text.")
          (cl-letf (((symbol-function 'emacsvox-icon) #'ignore))
            (flyspell-mode 1)
            (flyspell-buffer))
          (should
           (seq-some
            (lambda (overlay)
              (and
               (flyspell-overlay-p overlay)
               (equal
                (buffer-substring-no-properties
                 (overlay-start overlay) (overlay-end overlay))
                "mispeled")))
            (overlays-in (point-min) (point-max)))))
      (when (process-live-p ispell-process)
        (delete-process ispell-process)))))

(provide 'emacsvox-flyspell-tests)
