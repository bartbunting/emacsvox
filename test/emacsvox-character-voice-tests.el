;;; emacsvox-character-voice-tests.el --- Character palette regressions -*- lexical-binding: t; -*-
;;; Commentary:
;; Exercise actual character commands, frozen registrations and transport.
;;; Code:
(require 'omnivox-choice-playback-tests)
(require 'emacsvox-aural-voice-runtime-tests)
(require 'emacsvox-speak)

(defmacro emacsvox-character-test--with-runtime (&rest body)
  (declare (indent 0) (debug t))
  `(omnivox-choice-playback-test--with-runtime
    (let ((tts-program "omnivox") (tts-quiet nil)
          (tts-unicode-untouched-charsets '(ascii unicode))
          (emacsvox-delayed-phonetic-mode nil)
          (emacsvox-aural-presentation-history nil)
          (emacsvox-aural-session-rules nil)
          (emacsvox-aural-history-record-interface-presentations t))
      (emacsvox-test--set-palette-default 'reading "espeak:gmw/en+max" 2)
      (setq requests nil)
      (cl-letf (((symbol-function 'omnivox--logical-voice-ids)
                 (lambda () '("default" "bolden" "voice-bolden" "unrelated"))))
        (omnivox-register-logical-voices))
      (dolist (write requests)
        (omnivox--dispatch-control-response (car write) (omnivox-test--choice-registration-ack write)))
      (dolist (process (list speaker notification))
        (process-put process omnivox--control-capabilities-property
                     (list :features (cons "palette_letter_v1" omnivox-test--choice-features))))
      (cl-letf (((symbol-function 'voice-from-acss) (lambda (_) 'character-test-style))
                ((symbol-function 'tts-get-voice-command) (lambda (_) ""))
                ((symbol-function 'tts-voice-reset-code) (lambda () "")))
        ,@body))))

(defun emacsvox-character-test--capture (function)
  "Call FUNCTION and decode its actual character or ordinary timeline."
  (let (writes)
    (cl-letf (((symbol-function 'process-send-string)
               (lambda (_ command) (push command writes))))
      (funcall function))
    (let ((line (cl-find-if (lambda (line) (string-match-p "\\`emacsvox_\\(?:letter\\|timeline\\) " line))
                            (split-string (apply #'concat (reverse writes)) "\n" t))))
      (ert-info ((format "Captured writes: %S" writes)) (should line))
      (should (string-match "\\`\\([^ ]+\\) {\\([^}]+\\)}" line))
      (list (match-string 1 line)
            (json-parse-string
             (decode-coding-string (base64-decode-string (match-string 2 line)) 'utf-8 t)
             :object-type 'plist :array-type 'list)
            writes))))

(ert-deftest emacsvox-character-voice-letters-use-palette-on-each-lane ()
  (emacsvox-character-test--with-runtime
   (dolist (process (list speaker notification))
     (let ((tts-speaker-process process))
       (dolist (char '(?q ?Q ?é ?İ ?7))
         (pcase-let* ((`(,command ,envelope ,_)
                       (emacsvox-character-test--capture (lambda () (emacsvox-speak-this-char char))))
                      (span (car (plist-get envelope :spans)))
                      (snapshot (process-get process omnivox--choice-registration-property))
                      (voice (omnivox--choice-provenance snapshot "default")))
           (should (equal command "emacsvox_letter"))
           (should (equal (plist-get envelope :delivery_policy) "ordered"))
           (should (equal (plist-get span :mode) "layered"))
           (should (equal (plist-get (plist-get span :span) :logical_voice_id) "default"))
           (should (equal (plist-get (plist-get span :span) :text) (char-to-string char)))
           (should (equal (plist-get (plist-get (car (plist-get voice :choices)) :selector) :voice-id)
                          "espeak:gmw/en+max"))))))))

(ert-deftest emacsvox-character-voice-phonetics-and-punctuation-use-default ()
  (emacsvox-character-test--with-runtime
   (dolist (case '(("q" "quebec") ("'" "apostrophe") ("?" "question")))
     (with-temp-buffer
       (insert (car case)) (goto-char (point-min))
       (pcase-let* ((`(,command ,envelope ,_)
                     (emacsvox-character-test--capture #'emacsvox-speak-char))
                    (span (plist-get (car (plist-get envelope :spans)) :span)))
         (should (equal command "emacsvox_timeline"))
         (should (equal (plist-get span :logical_voice_id) "default"))
         (should (string-match-p (cadr case) (plist-get span :text))))))))

(ert-deftest emacsvox-character-voice-navigation-speaks-clean-symbol-names ()
  "Character navigation must not speak punctuation from generated names."
  (require 'emacsvox-advice)
  (emacsvox-character-test--with-runtime
   (dolist (process (list speaker notification))
     (let ((tts-speaker-process process))
       (dolist (mode '(none some all))
         (dolist (case '((28 . "control backslash")
                         (29 . "control right bracket")
                         (30 . "control caret")
                         (31 . "control underscore")
                         (?\( . "left paren") (?\) . "right paren")
                         (?< . "less than") (?> . "greater than")
                         (?? . "question mark")
                         (?\[ . "left bracket") (?\] . "right bracket")
                         (?{ . "left brace") (?} . "right brace")
                         (?* . "star")))
           (with-temp-buffer
             (insert "x" (char-to-string (car case)) "x")
             (let ((tts-punctuation-mode mode))
               (dolist (command '(forward-char backward-char))
                 (goto-char (if (eq command 'forward-char) 1 3))
                 (pcase-let* ((`(,wire-command ,envelope ,_)
                               (emacsvox-character-test--capture
                                (lambda ()
                                  ;; Exclude the delayed matching-delimiter cue.
                                  (cl-letf (((symbol-function 'sit-for) #'ignore))
                                    (call-interactively command)))))
                              (text (mapconcat
                                     (lambda (span)
                                       (plist-get (plist-get span :span) :text))
                                     (plist-get envelope :spans) "")))
                   (ert-info ((format "character=%S mode=%S command=%S"
                                      (car case) mode command))
                     (should (equal wire-command "emacsvox_timeline"))
                     (should (equal (string-trim text) (cdr case))))))))))))))

(ert-deftest emacsvox-character-voice-typing-and-arrow-navigation-use-default ()
  (require 'emacsvox-advice)
  (emacsvox-character-test--with-runtime
   (with-temp-buffer
     (let ((emacsvox-character-echo t) (emacsvox-word-echo nil)
           (post-self-insert-hook '(emacsvox-post-self-insert-hook)))
       (cl-letf (((symbol-function 'emacsvox-icon) #'ignore))
         (dolist (action (list
                         (lambda ()
                           (let ((noninteractive nil) (executing-kbd-macro nil)
                                 (last-command-event ?q))
                             (call-interactively #'self-insert-command)))
                         (lambda () (call-interactively #'backward-char))
                         (lambda () (emacsvox-speak-char t))))
           (pcase-let* ((`(,command ,envelope ,_)
                         (emacsvox-character-test--capture action))
                        (span (plist-get (car (plist-get envelope :spans)) :span)))
             (should (equal command "emacsvox_letter"))
             (should (equal (plist-get span :logical_voice_id) "default"))
             (should (equal (plist-get span :text) "q")))))))))

(ert-deftest emacsvox-character-voice-old-server-keeps-legacy-letter ()
  (emacsvox-character-test--with-runtime
   (process-put speaker omnivox--control-capabilities-property
                (list :features omnivox-test--choice-features))
   (let (writes)
     (cl-letf (((symbol-function 'process-send-string)
                (lambda (_ command) (push command writes))))
       (tts-letter "Q"))
     (should (member "l {Q}\n" writes))
     (should-not (cl-some (lambda (s) (string-prefix-p "emacsvox_letter" s)) writes)))))

(ert-deftest emacsvox-character-voice-negotiation-is-per-process ()
  (emacsvox-character-test--with-runtime
   (process-put notification omnivox--control-capabilities-property
                (list :features omnivox-test--choice-features))
   (let ((tts-speaker-process notification) writes)
     (cl-letf (((symbol-function 'process-send-string)
                (lambda (_ command) (push command writes))))
       (tts-letter "q"))
     (should (member "l {q}\n" writes)))
   (should (equal (car (emacsvox-character-test--capture (lambda () (tts-letter "q"))))
                  "emacsvox_letter"))))

(ert-deftest emacsvox-character-voice-legacy-inputs-retain-old-contract ()
  (emacsvox-character-test--with-runtime
   (dolist (text '(" " "\t" "two letters"))
     (let (writes)
       (cl-letf (((symbol-function 'process-send-string)
                  (lambda (_ command) (push command writes))))
         (tts-letter text))
       (should (member (format "l {%s}\n" text) writes))))))

(provide 'emacsvox-character-voice-tests)
;;; emacsvox-character-voice-tests.el ends here
