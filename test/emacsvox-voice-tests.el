;;; emacsvox-voice-tests.el --- Voice compatibility tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Characterize personality, face, ACSS, pause, and scratch-buffer behavior
;; before these inputs are adapted to semantic aural-presentation plans.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'tts-speak)
(require 'voice-setup)

(defvar emacsvox-pronounce-personality)
(defvar emacsvox-pronounce-table)

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

(provide 'emacsvox-voice-tests)
;;; emacsvox-voice-tests.el ends here
