;;; emacsvox-aural-voice-palettes-tests.el --- Voice palette manager tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Test accessible voice-palette management, activation, and preview.

;;; Code:

(require 'ert)
(require 'emacsvox-aural-voice-palettes)

(defmacro emacsvox-test--with-voice-palettes (&rest body)
  "Run BODY with isolated voice-palette and presentation state."
  (declare (indent 0) (debug t))
  `(let ((emacsvox-aural-voice-palette-registry
          (copy-hash-table emacsvox-aural-voice-palette-registry))
         (emacsvox-aural-scheme-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-profile-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-voice-palette-override nil)
         (emacsvox-aural-voice-palette-changed-hook nil)
         (emacsvox-aural-active-scheme 'default))
     (emacsvox-aural--register-default-scheme)
     ,@body))

(defconst emacsvox-test--voice-palette-data
  '(:schema-version 1
    :id reading
    :summary "Reading voices"
    :parent acss-default
    :entries
    ((heading :personality voice-bolden)
     (aside
      :style
      (:family nil :average-pitch 4 :pitch-range 3
       :stress nil :richness 6))))
  "Personal palette used by manager tests.")

(ert-deftest emacsvox-aural-voice-palettes-rows-and-bindings-are-complete ()
  "The manager reports provider state and exposes accessible operations."
  (emacsvox-test--with-voice-palettes
    (emacsvox-aural-register-voice-palette-data
     emacsvox-test--voice-palette-data)
    (with-temp-buffer
      (emacsvox-aural-voice-palettes-mode)
      (emacsvox-aural-voice-palettes-refresh 'reading)
      (let ((row (cadr (assq 'reading tabulated-list-entries))))
        (should (equal (aref row 0) "reading"))
        (should (equal (aref row 2) "personal"))
        (should (equal (aref row 3) "acss-default"))
        (should (equal (aref row 4) "2"))
        (should (equal (aref row 5) "27")))
      (dolist
          (binding
           '(("RET" . emacsvox-aural-voice-palettes-describe)
             ("SPC" . emacsvox-aural-voice-palettes-speak-current)
             ("." . emacsvox-aural-voice-palettes-speak-current-cell)
             ("n" . emacsvox-aural-voice-palettes-next)
             ("p" . emacsvox-aural-voice-palettes-previous)
             ("<right>" . emacsvox-aural-voice-palettes-next-column)
             ("<left>" . emacsvox-aural-voice-palettes-previous-column)
             ("a" . emacsvox-aural-voice-palettes-activate)
             ("f" . emacsvox-aural-voice-palettes-follow-scheme)
             ("N" . emacsvox-aural-voice-palettes-create)
             ("c" . emacsvox-aural-voice-palettes-copy)
             ("e" . emacsvox-aural-voice-palettes-edit-entry)
             ("E" . emacsvox-aural-voice-palettes-edit-metadata)
             ("D" . emacsvox-aural-voice-palettes-delete-entry)
             ("d" . emacsvox-aural-voice-palettes-delete)
             ("P" . emacsvox-aural-voice-palettes-preview)
             ("x" . emacsvox-aural-voice-palettes-explain)
             ("v" . emacsvox-aural-voice-palettes-describe)
             ("h" . emacsvox-aural)
             ("q" . emacsvox-aural-quit)
             ("?" . emacsvox-aural-voice-palettes-help)))
        (should
         (eq
          (lookup-key
           emacsvox-aural-voice-palettes-mode-map
           (kbd (car binding)))
          (cdr binding)))))))

(ert-deftest emacsvox-aural-voice-palettes-install-data-is-atomic ()
  "Palette replacement saves a complete temporary registry before publishing."
  (emacsvox-test--with-voice-palettes
    (let (saved)
      (cl-letf
          (((symbol-function 'emacsvox-aural-save-user-data)
            (lambda (&optional _)
              (setq
               saved
               (emacsvox-aural-voice-palette 'reading))
              "saved"))
           ((symbol-function 'emacsvox-aural-home-refresh-if-live)
            #'ignore))
        (emacsvox-aural-voice-palettes--install-data
         emacsvox-test--voice-palette-data)
        (should saved)
        (should (emacsvox-aural-voice-palette 'reading))
        (let ((before emacsvox-aural-voice-palette-registry))
          (should-error
           (emacsvox-aural-voice-palettes--install-data
            (plist-put
             (copy-tree emacsvox-test--voice-palette-data)
             :parent 'missing)
            'reading)
           :type 'emacsvox-aural-resource-error)
          (should (eq emacsvox-aural-voice-palette-registry before))
          (should
           (eq
            (emacsvox-aural-voice-palette-parent
             (emacsvox-aural-voice-palette 'reading))
            'acss-default)))))))

(ert-deftest emacsvox-aural-voice-palettes-activate-and-follow-scheme ()
  "The manager can select an override and return control to the scheme."
  (emacsvox-test--with-voice-palettes
    (emacsvox-aural-register-voice-palette-data
     emacsvox-test--voice-palette-data)
    (with-temp-buffer
      (emacsvox-aural-voice-palettes-mode)
      (emacsvox-aural-voice-palettes-refresh 'reading)
      (cl-letf
          (((symbol-function 'tts-speak) #'ignore)
           ((symbol-function 'emacsvox-aural-home-refresh-if-live)
            #'ignore))
        (emacsvox-aural-voice-palettes-activate)
        (should (eq emacsvox-aural-voice-palette-override 'reading))
        (emacsvox-aural-voice-palettes-follow-scheme)
        (should-not emacsvox-aural-voice-palette-override)
        (should
         (eq
          (emacsvox-aural-voice-palettes--active-id)
          'acss-default))))))

(ert-deftest emacsvox-aural-voice-palettes-preview-queues-concrete-command ()
  "Preview compiles before queueing and brackets sample text with resets."
  (emacsvox-test--with-voice-palettes
    (emacsvox-aural-register-voice-palette-data
     emacsvox-test--voice-palette-data)
    (let (events)
      (cl-letf
          (((symbol-function 'completing-read)
            (lambda (&rest _) "heading"))
           ((symbol-function 'read-string)
            (lambda (&rest _) "Sample"))
           ((symbol-function 'emacsvox-aural--ensure-speaker) #'ignore)
           ((symbol-function 'tts-get-voice-command)
            (lambda (voice) (format "<%s>" voice)))
           ((symbol-function 'tts-voice-reset-code)
            (lambda () "RESET"))
           ((symbol-function 'tts--protocol-queue-code)
            (lambda (code) (push (list 'code code) events)))
           ((symbol-function 'tts--protocol-queue-text)
            (lambda (text) (push (list 'text text) events)))
           ((symbol-function 'tts--protocol-dispatch)
            (lambda () (push 'dispatch events))))
        (with-temp-buffer
          (emacsvox-aural-voice-palettes-mode)
          (emacsvox-aural-voice-palettes-refresh 'reading)
          (emacsvox-aural-voice-palettes-preview)))
      (should
       (equal
        (nreverse events)
        '((code "RESET")
          (code "<voice-bolden>")
          (text "Sample")
          (code "RESET")
          dispatch))))))

(provide 'emacsvox-aural-voice-palettes-tests)
;;; emacsvox-aural-voice-palettes-tests.el ends here
