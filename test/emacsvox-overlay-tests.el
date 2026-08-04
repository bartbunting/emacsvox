;;; emacsvox-overlay-tests.el --- Overlay advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated overlay advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--overlay-direct-advice
  '((remove-overlays :around emacsvox--advice-remove-overlays-around)
    (delete-overlay :before emacsvox--advice-delete-overlay-before)
    (overlay-put :after emacsvox--advice-overlay-put-after)
    (move-overlay :before emacsvox--advice-move-overlay-before))
  "Overlay functions using individually defined native advice.")

(ert-deftest emacsvox-overlay-advice-is-directly-registered ()
  "Migrated overlay advice uses native advice directly."
  (dolist (entry emacsvox-test--overlay-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-remove-overlays-cleans-mirrored-properties ()
  "Removing overlays clears mirrored properties and calls the original once."
  (with-temp-buffer
    (insert "abcdef")
    (put-text-property 2 5 'personality 'voice-bolden)
    (put-text-property 5 7 'personality 'voice-smoothen)
    (let ((ems--voiceify-overlays t)
          (calls 0)
          observed)
      (should
       (eq
        (emacsvox--advice-remove-overlays-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (setq observed
                 (list arguments ems--voiceify-overlays))
           'remove-result)
         2 5 'personality 'voice-bolden)
        'remove-result))
      (should (= calls 1))
      (should
       (equal observed
              '((2 5 personality voice-bolden) nil)))
      (should-not (get-text-property 2 'personality))
      (should (eq (get-text-property 5 'personality)
                  'voice-smoothen))
      (should ems--voiceify-overlays))))

(ert-deftest emacsvox-remove-overlays-clamps-mirrored-property-cleanup ()
  "Overlay bounds outside a narrowing remain valid for the original call."
  (with-temp-buffer
    (insert "abcdef")
    (put-text-property 2 7 'personality 'voice-bolden)
    (narrow-to-region 2 6)
    (let (observed)
      (should
       (eq
        (emacsvox--advice-remove-overlays-around
         (lambda (&rest arguments)
           (setq observed arguments)
           'remove-result)
         2 7 'personality 'voice-bolden)
        'remove-result))
      (should (equal observed '(2 7 personality voice-bolden))))
    (widen)
    (should-not (get-text-property 2 'personality))
    (should (eq (get-text-property 6 'personality) 'voice-bolden))))

(ert-deftest emacsvox-overlay-put-mirrors-face-and-invisibility ()
  "Overlay face and invisibility properties are mirrored into buffer text."
  (with-temp-buffer
    (insert "abcdef")
    (let ((overlay (make-overlay 2 5))
          (ems--voiceify-overlays t))
      (cl-letf (((symbol-function 'tts-get-voice-for-face)
                 (lambda (face)
                   (and (eq face 'highlight) 'voice-bolden))))
        (emacsvox--advice-overlay-put-after
         overlay 'face 'highlight)
        (emacsvox--advice-overlay-put-after
         overlay 'invisible t))
      (should (eq (get-text-property 2 'personality)
                  'voice-bolden))
      (should (eq (get-text-property 2 'invisible) t)))))

(ert-deftest emacsvox-delete-overlay-cleans-mirrored-properties ()
  "Deleting an overlay removes its mirrored voice and invisibility."
  (with-temp-buffer
    (insert "abcdef")
    (let ((overlay (make-overlay 2 5))
          (ems--voiceify-overlays nil))
      (overlay-put overlay 'face 'highlight)
      (overlay-put overlay 'invisible t)
      (put-text-property 2 5 'personality 'voice-bolden)
      (put-text-property 2 5 'invisible t)
      (let ((ems--voiceify-overlays t))
        (cl-letf (((symbol-function 'tts-get-voice-for-face)
                   (lambda (face)
                     (and (eq face 'highlight) 'voice-bolden))))
          (emacsvox--advice-delete-overlay-before overlay)))
      (should-not (get-text-property 2 'personality))
      (should-not (get-text-property 2 'invisible)))))

(ert-deftest emacsvox-move-overlay-moves-mirrored-properties ()
  "Moving an overlay transfers its mirrored properties between buffers."
  (let ((source (generate-new-buffer " *emacsvox-overlay-source*"))
        (target (generate-new-buffer " *emacsvox-overlay-target*")))
    (unwind-protect
        (with-current-buffer source
          (insert "abcdef")
          (with-current-buffer target
            (insert "uvwxyz"))
          (let ((overlay (make-overlay 2 4 source))
                (ems--voiceify-overlays nil))
            (overlay-put overlay 'face 'highlight)
            (overlay-put overlay 'invisible t)
            (with-current-buffer source
              (put-text-property 2 4 'personality 'voice-bolden)
              (put-text-property 2 4 'invisible t))
            (let ((ems--voiceify-overlays t))
              (cl-letf (((symbol-function 'tts-get-voice-for-face)
                         (lambda (face)
                           (and (eq face 'highlight)
                                'voice-bolden))))
                (emacsvox--advice-move-overlay-before
                 overlay 3 6 target)))
            (with-current-buffer source
              (should-not (get-text-property 2 'personality))
              (should-not (get-text-property 2 'invisible)))
            (with-current-buffer target
              (should (eq (get-text-property 3 'personality)
                          'voice-bolden))
              (should (eq (get-text-property 3 'invisible) t)))))
      (when (buffer-live-p source)
        (kill-buffer source))
      (when (buffer-live-p target)
        (kill-buffer target)))))

(provide 'emacsvox-overlay-tests)
;;; emacsvox-overlay-tests.el ends here
