;;; emacsvox-voice-tests.el --- Voice compatibility tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Characterize personality, face, ACSS, pause, and scratch-buffer behavior
;; before these inputs are adapted to semantic aural-presentation plans.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'tts-speak)
(require 'voice-setup)
(require 'emacsvox-speak)
(require 'emacsvox-aural-compatibility-voice)

(defvar emacsvox-pronounce-personality)
(defvar emacsvox-pronounce-table)
(defvar ems--voiceify-overlays)

(defmacro emacsvox-test--with-preserved-voice-lock-state (&rest body)
  "Run BODY and restore global and per-buffer Voice Lock state."
  (declare (indent 0) (debug t))
  `(let ((global-state global-voice-lock-mode)
         (default-state (default-value 'voice-lock-mode))
         (buffer-states
          (mapcar
           (lambda (buffer)
             (with-current-buffer buffer
               (list
                buffer
                (local-variable-p 'voice-lock-mode)
                voice-lock-mode
                (local-variable-p 'voice-lock-mode--set-explicitly)
                voice-lock-mode--set-explicitly)))
           (buffer-list))))
     (unwind-protect
         (progn ,@body)
       (global-voice-lock-mode (if global-state 1 -1))
       (set-default 'voice-lock-mode default-state)
       (dolist (state buffer-states)
         (pcase-let
             ((`(,buffer ,local ,value ,explicit-local ,explicit-value)
               state))
           (when (buffer-live-p buffer)
             (with-current-buffer buffer
               (if local
                   (set (make-local-variable 'voice-lock-mode) value)
                 (kill-local-variable 'voice-lock-mode))
               (if explicit-local
                   (set
                    (make-local-variable
                     'voice-lock-mode--set-explicitly)
                    explicit-value)
                 (kill-local-variable
                  'voice-lock-mode--set-explicitly)))))))))

(define-derived-mode emacsvox-test-voice-derived-mode fundamental-mode
  "Voice-Test"
  "Major mode used to characterize global Voice Lock inheritance.")

(ert-deftest emacsvox-voice-lock-mode-is-owned-by-aural-compatibility ()
  "Legacy mode symbols live outside the ACSS and face provider."
  (should
   (string-match-p
    "emacsvox-aural-compatibility-voice"
    (or (symbol-file 'voice-lock-mode 'defun) "")))
  (should (featurep 'voice-setup))
  (should (featurep 'emacsvox-aural-compatibility-voice)))

(defun emacsvox-test--toggle-local-silence ()
  "Toggle local silence without presenting the command's feedback cue."
  (cl-letf (((symbol-function 'emacsvox-icon) #'ignore))
    (voice-setup-toggle-silence-personality)))

(defmacro emacsvox-test--with-isolated-face-mappings (&rest body)
  "Run BODY with isolated face mappings and provenance."
  (declare (indent 0) (debug t))
  `(let ((voice-setup-face-voice-table
          (make-hash-table :test #'eq))
         (voice-setup-face-voice-provenance-table
          (make-hash-table :test #'eq))
         (voice-setup--face-mapping-sequence 0)
         (voice-setup-local-map nil)
         (emacsvox-aural-suppressed-personalities nil))
     ,@body))

(ert-deftest emacsvox-voice-face-mapping-records-provenance ()
  "Mapping APIs retain module provenance without changing their result."
  (emacsvox-test--with-isolated-face-mappings
    (should
     (eq
      (voice-setup-set-voice-for-face
       'font-lock-warning-face 'voice-brighten 'warning-module)
      'voice-brighten))
    (should
     (eq
      (voice-setup-get-voice-for-face 'font-lock-warning-face)
      'voice-brighten))
    (should
     (equal
      (voice-setup-face-mapping-provenance
       'font-lock-warning-face)
      '((:face font-lock-warning-face
         :voice voice-brighten
         :origin warning-module
         :sequence 1))))))

(ert-deftest emacsvox-voice-face-mapping-infers-file-origin ()
  "Top-level mapping declarations infer a stable module from their file."
  (emacsvox-test--with-isolated-face-mappings
    (let ((load-file-name "/tmp/emacsvox-example.elc"))
      (voice-setup-add-map
       '((font-lock-comment-face voice-monotone))))
    (should
     (eq
      (plist-get
       (car
        (voice-setup-face-mapping-provenance
         'font-lock-comment-face))
       :origin)
      'emacsvox-example))))

(ert-deftest emacsvox-voice-face-mapping-deduplicates-reloads ()
  "Reloading one declaration does not grow its provenance history."
  (emacsvox-test--with-isolated-face-mappings
    (dotimes (_ 2)
      (voice-setup-set-voice-for-face
       'font-lock-keyword-face 'voice-animate 'keyword-module))
    (should
     (= 1
        (length
         (voice-setup-face-mapping-provenance
          'font-lock-keyword-face))))))

(ert-deftest emacsvox-voice-face-mapping-conflicts-are-deterministic ()
  "Conflict diagnostics are sorted and preserve the effective last mapping."
  (emacsvox-test--with-isolated-face-mappings
    (voice-setup-set-voice-for-face
     'font-lock-warning-face 'voice-brighten 'warning-a)
    (voice-setup-set-voice-for-face
     'font-lock-warning-face 'voice-animate 'warning-b)
    (voice-setup-set-voice-for-face
     'font-lock-comment-face 'voice-monotone 'comment-a)
    (voice-setup-set-voice-for-face
     'font-lock-comment-face 'voice-smoothen 'comment-b)
    (voice-setup-set-voice-for-face
     'font-lock-string-face 'voice-lighten 'string-a)
    (voice-setup-set-voice-for-face
     'font-lock-string-face 'voice-lighten 'string-b)
    (let ((conflicts (voice-setup-face-mapping-conflicts)))
      (should
       (equal
        (mapcar
         (lambda (diagnostic) (plist-get diagnostic :face))
         conflicts)
        '(font-lock-comment-face font-lock-warning-face)))
      (should
       (eq
        (plist-get (cadr conflicts) :effective)
        'voice-animate))
      (should
       (equal
        (mapcar
         (lambda (record) (plist-get record :origin))
         (plist-get (cadr conflicts) :declarations))
        '(warning-a warning-b))))))

(ert-deftest emacsvox-voice-personality-precedes-face-mapping ()
  "An explicit personality currently takes precedence over the visual face."
  (with-temp-buffer
    (insert
     (propertize
      "text"
      'personality 'voice-explicit
      'face 'emacsvox-test-face))
    (let ((voice-setup-face-voice-table (make-hash-table :test #'eq)))
      (puthash
       'emacsvox-test-face 'voice-from-face
       voice-setup-face-voice-table)
      (should (eq (tts-get-style (point-min)) 'voice-explicit)))))

(ert-deftest emacsvox-voice-face-mapping-is-style-fallback ()
  "A face supplies the style when no explicit personality is present."
  (with-temp-buffer
    (insert (propertize "text" 'face 'emacsvox-test-face))
    (let ((voice-setup-face-voice-table (make-hash-table :test #'eq)))
      (puthash
       'emacsvox-test-face 'voice-from-face
       voice-setup-face-voice-table)
      (should (eq (tts-get-style (point-min)) 'voice-from-face)))))

(ert-deftest emacsvox-voice-face-silencing-is-buffer-local ()
  "Silencing a mapped face does not mutate its global mapping."
  (let ((voice-setup-face-voice-table (make-hash-table :test #'eq)))
    (puthash
     'font-lock-warning-face 'voice-from-face
     voice-setup-face-voice-table)
    (with-temp-buffer
      (insert (propertize "text" 'face 'font-lock-warning-face))
      (goto-char (point-min))
      (should (eq (tts-get-style) 'voice-from-face))
      (emacsvox-test--toggle-local-silence)
      (should (eq (tts-get-style) 'inaudible))
      (should
       (eq
        (gethash 'font-lock-warning-face voice-setup-face-voice-table)
        'voice-from-face))
      (with-temp-buffer
        (insert (propertize "text" 'face 'font-lock-warning-face))
        (should (eq (tts-get-style (point-min)) 'voice-from-face)))
      (emacsvox-test--toggle-local-silence)
      (should (eq (tts-get-style) 'voice-from-face)))))

(ert-deftest emacsvox-voice-personality-silencing-is-buffer-local ()
  "An explicit personality can be silenced in only the current buffer."
  (with-temp-buffer
    (insert (propertize "text" 'personality 'voice-explicit))
    (goto-char (point-min))
    (should (eq (tts-get-style) 'voice-explicit))
    (emacsvox-test--toggle-local-silence)
    (should (eq (tts-get-style) 'inaudible))
    (with-temp-buffer
      (insert (propertize "text" 'personality 'voice-explicit))
      (should (eq (tts-get-style (point-min)) 'voice-explicit)))
    (emacsvox-test--toggle-local-silence)
    (should (eq (tts-get-style) 'voice-explicit))))

(ert-deftest emacsvox-voice-silencing-sees-overlay-and-font-lock-faces ()
  "Local silencing follows the same source faces captured by aural speech."
  (let ((ems--voiceify-overlays nil)
        (voice-setup-face-voice-table (make-hash-table :test #'eq)))
    (puthash
     'font-lock-warning-face 'voice-overlay
     voice-setup-face-voice-table)
    (puthash
     'font-lock-comment-face 'voice-font-lock
     voice-setup-face-voice-table)
    (with-temp-buffer
      (setq-local default-text-properties nil)
      (setq-local char-property-alias-alist nil)
      (let ((inhibit-modification-hooks t))
        (insert "text")
        (set-text-properties
         (point-min) (point-max)
         '(font-lock-face font-lock-comment-face)))
      (goto-char (point-min))
      (let ((overlay (make-overlay (point-min) (point-max))))
        (overlay-put overlay 'priority 5)
        (overlay-put overlay 'face 'font-lock-warning-face)
        (should-not
         (emacsvox-aural-source-text-property
          (point) 'personality))
        (emacsvox-test--toggle-local-silence)
        (should
         (eq
          (voice-setup-get-voice-for-face
           'font-lock-warning-face)
          'inaudible))
        (should
         (eq
          (voice-setup-get-voice-for-face
           'font-lock-comment-face)
          'voice-font-lock))
        (emacsvox-test--toggle-local-silence)
        (delete-overlay overlay))
      (emacsvox-test--toggle-local-silence)
      (should
       (eq
        (voice-setup-get-voice-for-face
         'font-lock-comment-face)
        'inaudible)))))

(ert-deftest emacsvox-voice-acss-generates-stable-name-and-definition ()
  "An ACSS style is named from its dimensions and defined only when absent."
  (let (defined)
    (cl-letf (((symbol-function 'tts-voice-defined-p) #'ignore)
              ((symbol-function 'tts-define-voice-from-acss)
               (lambda (name style)
                 (setq defined (list name style)))))
      (let* ((style
              (make-acss
               :family 'paul
               :average-pitch 4
               :pitch-range 6
               :stress 7
               :richness 8))
             (name (voice-from-acss style)))
        (should (eq name 'acss-paul-a4-p6-s7-r8))
        (should (eq (car defined) name))
        (should (eq (cadr defined) style))))))

(ert-deftest emacsvox-voice-acss-reuses-existing-definition ()
  "An already defined ACSS name is returned without redefining it."
  (let (defined)
    (cl-letf (((symbol-function 'tts-voice-defined-p) (lambda (_) t))
              ((symbol-function 'tts-define-voice-from-acss)
               (lambda (&rest _) (setq defined t))))
      (should
       (eq
        (voice-from-acss
         (make-acss :average-pitch 4 :richness 6))
        'acss-a4-r6))
      (should-not defined))))

(ert-deftest emacsvox-voice-acss-can-route-only-the-physical-family ()
  "A logical route changes family while retaining every other ACSS value."
  (let (defined)
    (cl-letf
        (((symbol-function 'tts-voice-defined-p) #'ignore)
         ((symbol-function 'emacsvox-aural-routing-static-family)
          (lambda (logical requested)
            (should (eq logical 'voice-test))
            (should (eq requested 'paul))
            'outloud-v2))
         ((symbol-function 'tts-define-voice-from-acss)
          (lambda (name style) (setq defined (list name style)))))
      (should
       (eq
        (voice-from-acss
         (make-acss :family 'paul :average-pitch 4 :stress 7)
         'voice-test)
        'acss-outloud-v2-a4-s7))
      (should (eq (acss-family (cadr defined)) 'outloud-v2))
      (should (= (acss-average-pitch (cadr defined)) 4))
      (should (= (acss-stress (cadr defined)) 7)))))

(ert-deftest emacsvox-voice-static-apply-recompiles-logical-personalities ()
  "Standalone apply atomically republishes every declared personality."
  (let ((voice-setup-defined-voices '(voice-test-route))
        callback)
    (cl-progv '(voice-test-route voice-test-route-settings)
        '(old (paul 4 nil 7 nil))
      (cl-letf
          (((symbol-function 'voice-setup-acss-from-style)
            (lambda (settings logical)
              (should (equal settings '(paul 4 nil 7 nil)))
              (should (eq logical 'voice-test-route))
              'new))
           ((symbol-function 'tts-voice-capabilities)
            (lambda () '(:adapter outloud))))
        (let ((result
               (voice-setup-apply-voice-configuration
                (lambda (value) (setq callback value)))))
          (should (eq (symbol-value 'voice-test-route) 'new))
          (should (eq (plist-get result :status) 'applied))
          (should (= (plist-get result :recompiled-personalities) 1))
          (should (equal result callback)))))))

(ert-deftest emacsvox-voice-audio-format-preserves-style-runs ()
  "Audio formatting speaks each personality run with its selected voice."
  (with-temp-buffer
    (insert
     (concat
      (propertize "one" 'personality 'voice-one)
      (propertize "two" 'personality 'voice-two)))
    (let ((voice-lock-mode t)
          events)
      (cl-letf (((symbol-function 'tts-voice-reset-code)
                 (lambda () "reset"))
                ((symbol-function 'tts--protocol-queue-code)
                 (lambda (code) (push (list 'code code) events)))
                ((symbol-function 'tts-speak-using-voice)
                 (lambda (voice text)
                   (push (list 'voice voice text) events)))
                ((symbol-function 'tts--protocol-queue-text)
                 (lambda (text) (push (list 'text text) events))))
        (tts-audio-format (point-min) (point-max)))
      (should
       (equal
        (nreverse events)
        '((code "reset")
          (voice voice-one "one")
          (voice voice-two "two")))))))

(ert-deftest emacsvox-voice-inaudible-suppresses-content ()
  "The legacy inaudible personality sends neither voice code nor text."
  (let (events)
    (cl-letf (((symbol-function 'tts--protocol-queue-code)
               (lambda (code) (push (list 'code code) events)))
              ((symbol-function 'tts--protocol-queue-text)
               (lambda (text) (push (list 'text text) events))))
      (tts-speak-using-voice 'inaudible "hidden")
      (tts-speak-using-voice '(voice-one inaudible) "also hidden"))
    (should-not events)))

(ert-deftest emacsvox-voice-command-precedes-styled-text ()
  "A personality compiles to an engine command before its text is queued."
  (let ((voice-symbol 'engine-voice)
        (tts-default-voice 'default-voice)
        events)
    (set voice-symbol 'engine-voice-value)
    (unwind-protect
        (cl-letf (((symbol-function 'tts-get-voice-command)
                   (lambda (voice) (format "<%s>" voice)))
                  ((symbol-function 'tts-voice-reset-code)
                   (lambda () "reset"))
                  ((symbol-function 'tts--protocol-queue-code)
                   (lambda (code) (push (list 'code code) events)))
                  ((symbol-function 'tts--protocol-queue-text)
                   (lambda (text) (push (list 'text text) events))))
          (tts-speak-using-voice voice-symbol "styled"))
      (makunbound voice-symbol))
    (should
     (equal
      (nreverse events)
      '((code "<engine-voice-value>")
        (text "styled")
        (code "reset"))))))

(ert-deftest emacsvox-voice-pause-follows-reset-before-content ()
  "A pause at the start of a run is queued after reset and before text."
  (with-temp-buffer
    (insert (propertize "text" 'pause 75))
    (let ((voice-lock-mode nil)
          events)
      (cl-letf (((symbol-function 'tts-voice-reset-code)
                 (lambda () "reset"))
                ((symbol-function 'tts--protocol-queue-code)
                 (lambda (code) (push (list 'code code) events)))
                ((symbol-function 'tts--protocol-silence)
                 (lambda (duration &optional _force)
                   (push (list 'pause duration) events)))
                ((symbol-function 'tts--protocol-queue-text)
                 (lambda (text) (push (list 'text text) events))))
        (tts-audio-format (point-min) (point-max)))
      (should
       (equal
        (nreverse events)
        '((code "reset")
          (pause 75)
          (text "text")))))))

(defun emacsvox-test--capture-tts-scratch-context (text source-mode)
  "Speak TEXT from SOURCE-MODE and capture scratch mode and properties."
  (when-let* ((scratch (get-buffer " *tts-scratch-buffer* ")))
    (kill-buffer scratch))
  (let ((tts-speaker-process 'speaker)
        (tts-stop-immediately nil)
        (tts-quiet nil)
        (emacsvox-pronounce-table nil)
        (emacsvox-pronounce-personality nil)
        captured)
    (unwind-protect
        (with-temp-buffer
          (setq major-mode source-mode)
          (cl-letf (((symbol-function 'process-live-p) (lambda (_) t))
                    ((symbol-function 'tts--protocol-sync) #'ignore)
                    ((symbol-function 'tts--protocol-dispatch) #'ignore)
                    ((symbol-function 'tts-audio-format)
                     (lambda (start _end)
                       (setq
                        captured
                        (list
                         major-mode
                         (get-text-property start 'personality)
                         (get-text-property start 'auditory-icon)))))
                    ((symbol-function 'tts-move-across-a-chunk)
                     (lambda (&rest _)
                       (goto-char (point-max))
                       t)))
            (tts-speak text)))
      (when-let* ((scratch (get-buffer " *tts-scratch-buffer* ")))
        (kill-buffer scratch)))
    captured))

(ert-deftest emacsvox-voice-tts-scratch-preserves-aural-properties ()
  "The TTS scratch copy retains personality and auditory-icon properties."
  (let ((text
         (propertize
          "heading"
          'personality 'voice-bolden
          'auditory-icon 'item)))
    (should
     (equal
      (cdr
       (emacsvox-test--capture-tts-scratch-context
        text 'emacsvox-test-source-mode))
      '(voice-bolden item)))))

(ert-deftest emacsvox-voice-tts-scratch-loses-source-major-mode ()
  "The current TTS scratch path does not install the source major mode."
  (let ((captured
         (emacsvox-test--capture-tts-scratch-context
          "heading" 'emacsvox-test-source-mode)))
    (should (eq (car captured) 'fundamental-mode))
    (should-not (eq (car captured) 'emacsvox-test-source-mode))))

(ert-deftest emacsvox-voice-global-mode-governs-new-buffers ()
  "New buffers follow the disabled or enabled global Voice Lock state."
  (emacsvox-test--with-preserved-voice-lock-state
    (let (disabled-buffer enabled-buffer)
      (unwind-protect
          (progn
            (global-voice-lock-mode -1)
            (setq
             disabled-buffer
             (generate-new-buffer " *voice-lock-disabled*"))
            (with-current-buffer disabled-buffer
              (fundamental-mode)
              (should-not global-voice-lock-mode)
              (should-not voice-lock-mode))
            (global-voice-lock-mode 1)
            (setq
             enabled-buffer
             (generate-new-buffer " *voice-lock-enabled*"))
            (with-current-buffer enabled-buffer
              (fundamental-mode)
              (should global-voice-lock-mode)
              (should voice-lock-mode)))
        (dolist (buffer (list disabled-buffer enabled-buffer))
          (when (buffer-live-p buffer)
            (kill-buffer buffer)))))))

(ert-deftest emacsvox-voice-global-mode-governs-existing-buffers ()
  "Global Voice Lock updates buffers that already exist."
  (emacsvox-test--with-preserved-voice-lock-state
    (with-temp-buffer
      (fundamental-mode)
      (global-voice-lock-mode 1)
      (should voice-lock-mode)
      (global-voice-lock-mode -1)
      (should-not voice-lock-mode)
      (global-voice-lock-mode 1)
      (should voice-lock-mode))))

(ert-deftest emacsvox-voice-local-mode-remains-independent ()
  "A buffer may explicitly enable Voice Lock while its global mode is off."
  (emacsvox-test--with-preserved-voice-lock-state
    (global-voice-lock-mode -1)
    (with-temp-buffer
      (fundamental-mode)
      (should-not voice-lock-mode)
      (voice-lock-mode 1)
      (should voice-lock-mode))
    (with-temp-buffer
      (fundamental-mode)
      (should-not voice-lock-mode))))

(ert-deftest emacsvox-aural-compatibility-voice-control-is-buffer-local ()
  "The aural control changes only the selected Voice Lock adapter."
  (emacsvox-test--with-preserved-voice-lock-state
    (global-voice-lock-mode -1)
    (let ((first (generate-new-buffer " *compatibility-voice-first*"))
          (second (generate-new-buffer " *compatibility-voice-second*"))
          (emacsvox-aural-compatibility-voice-changed-hook nil)
          events)
      (unwind-protect
          (progn
            (add-hook
             'emacsvox-aural-compatibility-voice-changed-hook
             (lambda (buffer enabled)
               (push (list buffer enabled (current-buffer)) events)))
            (should
             (emacsvox-aural-set-compatibility-voice-enabled t first))
            (should
             (emacsvox-aural-compatibility-voice-enabled-p first))
            (should (emacsvox-aural-voice-lock-enabled-p first))
            (should-not
             (emacsvox-aural-compatibility-voice-enabled-p second))
            (should-not
             (emacsvox-aural-toggle-compatibility-voice nil first))
            (with-current-buffer second
              (voice-lock-mode 1))
            (should
             (equal
              (nreverse events)
              (list
               (list first t first)
               (list first nil first)
               (list second t second)))))
        (kill-buffer first)
        (kill-buffer second)))))

(ert-deftest emacsvox-voice-global-mode-follows-derived-modes ()
  "Derived modes inherit global Voice Lock after their hooks run."
  (emacsvox-test--with-preserved-voice-lock-state
    (global-voice-lock-mode 1)
    (with-temp-buffer
      (emacsvox-test-voice-derived-mode)
      (should voice-lock-mode))))

(ert-deftest emacsvox-voice-major-mode-hook-can-opt-out ()
  "A major-mode hook may explicitly disable global Voice Lock locally."
  (emacsvox-test--with-preserved-voice-lock-state
    (global-voice-lock-mode 1)
    (let ((emacsvox-test-voice-derived-mode-hook
           (list (lambda () (voice-lock-mode -1)))))
      (with-temp-buffer
        (emacsvox-test-voice-derived-mode)
        (should voice-lock-mode--set-explicitly)
        (should-not voice-lock-mode)))))

(ert-deftest emacsvox-voice-speak-line-snapshots-overlay-faces ()
  "Normal line speech captures overlay faces before copying source text."
  (with-temp-buffer
    (insert "warning")
    (let ((overlay (make-overlay (point-min) (point-max)))
          captured)
      (overlay-put overlay 'priority 5)
      (overlay-put overlay 'face "font-lock-warning-face")
      (let ((expected
             (emacsvox-aural-capture-source-faces (point-min)))
            (emacsvox-show-point nil)
            (emacsvox-audio-indentation nil))
        (cl-letf
            (((symbol-function 'tts-stop) (lambda (&rest _)))
             ((symbol-function 'tts-speak)
              (lambda (text) (setq captured text)))
             ((symbol-function 'emacsvox-icon) (lambda (&rest _))))
          (goto-char (point-min))
          (emacsvox-speak-line))
        (should
         (equal
          (get-text-property
           0 emacsvox-aural-source-faces-property captured)
          expected))))))

(provide 'emacsvox-voice-tests)
;;; emacsvox-voice-tests.el ends here
