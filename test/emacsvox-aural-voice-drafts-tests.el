;;; emacsvox-aural-voice-drafts-tests.el --- Voice save recovery tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Exercise real temporary files, live publication and independently delayed applies.
;;; Code:
(require 'ert)
(require 'emacsvox-aural-voice-runtime-tests)
(require 'emacsvox-aural-voice-drafts)

(defmacro emacsvox-test--with-voice-save (&rest body)
  "Run BODY with isolated live data and two real temporary stores."
  (declare (indent 0) (debug t))
  `(emacsvox-test--with-owned-runtime
    (let* ((directory (make-temp-file "voice-draft-save-" t))
           (emacsvox-aural-schemes-file (expand-file-name "aural.el" directory))
           (emacsvox-aural-routing-profiles-file (expand-file-name "routing.el" directory))
           (emacsvox-aural-voice-drafts--registry (make-hash-table :test #'equal))
           (emacsvox-aural-voice-drafts--changed-hook nil)
           (emacsvox-aural-routing-profile-registry (make-hash-table :test #'eq))
           (emacsvox-aural-active-routing-profile nil)
           (emacsvox-aural-voice-runtime--last-snapshot (emacsvox-aural-voice-runtime--snapshot))
           (draft (emacsvox-aural-voice-drafts--open '(base reading-owned bolden)
                                                     '(:pitch 0) '(reading-owned)))
           (palette (emacsvox-aural-voice-drafts--palette-data 'reading-owned))
           (new-set '(:id "saved-chain" :palette reading-owned :voice bolden
                          :selectors ((:kind exact :scope local :engine-id "eloquence" :voice-id "Reed"))))
           palettes)
      (unwind-protect
          (progn
            (maphash (lambda (_ record) (push (emacsvox-aural-voice-palette-data-form record) palettes))
                     emacsvox-aural-voice-palette-registry)
            (emacsvox-aural--write-user-data (list :schema-version 9 :voice-palettes palettes))
            (emacsvox-aural-save-routing-profiles)
            (let ((entry (assq 'bolden (plist-get palette :entries))))
              (setcdr entry (plist-put (cdr entry) :local-choices "saved-chain"))
              (setcdr entry (plist-put (cdr entry) :style
                                       (plist-put (plist-get (cdr entry) :style) :average-pitch 8))))
            (emacsvox-aural-voice-drafts--edit draft '(:pitch 8))
            ,@body)
        (delete-directory directory t)))))

(ert-deftest emacsvox-aural-voice-drafts-opening-editing-and-discard-write-nothing ()
  "Draft identity, nil/omission differences, undo and leaving need no persistence."
  (let ((emacsvox-aural-voice-drafts--registry (make-hash-table :test #'equal)))
    (let ((draft (emacsvox-aural-voice-drafts--open '(base test bolden) '(:pitch 0))))
      (should (eq draft (emacsvox-aural-voice-drafts--open '(base test bolden) '(:pitch 7))))
      (emacsvox-aural-voice-drafts--edit draft '(:pitch 0 :echo nil))
      (should (equal (emacsvox-aural-voice-drafts--dirty-fields draft) '(:echo)))
      (emacsvox-aural-voice-drafts--undo draft)
      (should-not (emacsvox-aural-voice-drafts--dirty-fields draft))
      (emacsvox-aural-voice-drafts--edit draft '(:pitch 9))
      (emacsvox-aural-voice-drafts--discard draft)
      (should (equal (emacsvox-aural-voice-draft-working draft) '(:pitch 0))))))

(ert-deftest emacsvox-aural-voice-drafts-partial-write-keeps-old-live-and-saved-chain ()
  "Failure between stores keeps the old reference, and retry reuses the new ID."
  (emacsvox-test--with-voice-save
   (let* ((old-palette (emacsvox-aural-voice-drafts--palette-data 'reading-owned))
          (old-file (emacsvox-aural-read-user-data))
          (old-sets (copy-tree emacsvox-aural-routing--choice-sets))
          (proposal (emacsvox-aural-voice-drafts--prepare draft palette (list new-set)))
          (real-writer (symbol-function 'emacsvox-aural-routing--write-user-data))
          (local-writes 0))
     (cl-letf (((symbol-function 'emacsvox-aural-routing--write-user-data)
                (lambda (&rest args) (cl-incf local-writes) (apply real-writer args))))
       (cl-letf (((symbol-function 'emacsvox-aural--write-user-data)
                  (lambda (&rest _) (error "Injected palette write failure"))))
         (emacsvox-aural-voice-drafts--save proposal))
       (should (eq (emacsvox-aural-voice-save-state proposal) 'partial))
       (should (equal (emacsvox-aural-read-user-data) old-file))
       (should (equal (emacsvox-aural-voice-drafts--palette-data 'reading-owned) old-palette))
       (should (equal emacsvox-aural-routing--choice-sets old-sets))
       (should (member new-set (plist-get (emacsvox-aural-read-routing-profiles) :choice-sets)))
       (emacsvox-aural-voice-drafts--save proposal)
       (should (= local-writes 1))
       (should (eq (emacsvox-aural-voice-save-state proposal) 'saved))
       (should-not (emacsvox-aural-voice-drafts--dirty-fields draft))
       (should (equal (emacsvox-aural-voice-drafts--palette-data 'reading-owned) palette))
       (dolist (old old-sets) (should (member old emacsvox-aural-routing--choice-sets)))))))

(ert-deftest emacsvox-aural-voice-drafts-newer-edits-survive-apply-and-buffer-destruction ()
  "A saved snapshot advances its baseline; late acknowledgement preserves edits."
  (emacsvox-test--with-voice-save
   (let* ((proposal (emacsvox-aural-voice-drafts--prepare draft palette (list new-set) :select t))
          (buffer (generate-new-buffer " *voice-draft-view*")) callback calls)
     (cl-letf (((symbol-function 'tts-apply-voice-configuration)
                (lambda (&optional function) (cl-incf calls) (setq callback function))))
       (setq calls 0)
       (with-current-buffer buffer (emacsvox-aural-voice-drafts--save proposal))
       (should (eq (emacsvox-aural-voice-save-state proposal) 'applying))
       (should-not (emacsvox-aural-voice-drafts--dirty-fields draft))
       (should (equal (emacsvox-aural-voice-draft-original draft) '(:pitch 0)))
       (emacsvox-aural-voice-drafts--save proposal)
       (should (= calls 1))
       (emacsvox-aural-voice-drafts--edit draft '(:pitch 9))
       (kill-buffer buffer)
       (funcall callback '(:status applied :processes ((:role speaker :status applied)
                                                       (:role notification :status applied))))
       (should (eq (emacsvox-aural-voice-save-state proposal) 'applied))
       (should (equal (emacsvox-aural-voice-draft-original draft) '(:pitch 8)))
       (should (equal (emacsvox-aural-voice-draft-working draft) '(:pitch 9)))
       (should (equal (emacsvox-aural-voice-drafts--dirty-fields draft) '(:pitch)))
       (funcall callback '(:status failed))
       (should (eq (emacsvox-aural-voice-save-state proposal) 'applied))))))

(ert-deftest emacsvox-aural-voice-drafts-conflicts-before-and-between-writes ()
  "A changed destination or external file is never overwritten by a frozen save."
  (emacsvox-test--with-voice-save
   (let ((proposal (emacsvox-aural-voice-drafts--prepare draft palette (list new-set)))
         (before-local (emacsvox-aural-voice-drafts--file-id emacsvox-aural-routing-profiles-file)))
     (with-temp-buffer
       (insert "; external change\n")
       (write-region (point-min) (point-max) emacsvox-aural-schemes-file t 'silent))
     (let ((external (emacsvox-aural-voice-drafts--file-id emacsvox-aural-schemes-file)))
       (emacsvox-aural-voice-drafts--save proposal)
       (should (eq (emacsvox-aural-voice-save-state proposal) 'failed))
       (should (equal external (emacsvox-aural-voice-drafts--file-id emacsvox-aural-schemes-file)))
       (should (equal before-local (emacsvox-aural-voice-drafts--file-id emacsvox-aural-routing-profiles-file)))))))

(ert-deftest emacsvox-aural-voice-drafts-detects-parent-change-since-opening ()
  "An open draft cannot silently capture a newly edited source as its baseline."
  (emacsvox-test--with-voice-save
   (puthash 'reading-owned (emacsvox-aural-compile-voice-palette-data palette)
            emacsvox-aural-voice-palette-registry)
   (should-error (emacsvox-aural-voice-drafts--prepare draft palette (list new-set))
                 :type 'emacsvox-aural-voice-draft-conflict)))

(ert-deftest emacsvox-aural-voice-drafts-timeout-retry-and-new-selection ()
  "Retry applies saved data only while its palette is still active; no reselect."
  (emacsvox-test--with-voice-save
   (let ((proposal (emacsvox-aural-voice-drafts--prepare draft palette (list new-set) :select t)) callbacks)
     (cl-letf (((symbol-function 'tts-apply-voice-configuration)
                (lambda (&optional callback) (push callback callbacks))))
       (emacsvox-aural-voice-drafts--save proposal)
       (funcall (car callbacks) '(:status failed :processes ((:role speaker :phase timeout))))
       (should (eq (emacsvox-aural-voice-save-state proposal) 'apply-failed))
       (let ((aural (emacsvox-aural-voice-drafts--file-id emacsvox-aural-schemes-file))
             (old-callback (car callbacks)))
         (emacsvox-aural-voice-drafts--save proposal)
         (should (= (length callbacks) 2))
         (funcall old-callback '(:status applied))
         (should (eq (emacsvox-aural-voice-save-state proposal) 'applying))
         (funcall (car callbacks) '(:status failed))
         (emacsvox-aural-select-voice-palette 'alternative-owned)
         (let ((count (length callbacks)))
           (emacsvox-aural-voice-drafts--save proposal)
           (should (= count (length callbacks)))
           (should (eq emacsvox-aural-voice-palette-override 'alternative-owned)))
         (should (equal aural (emacsvox-aural-voice-drafts--file-id emacsvox-aural-schemes-file))))))))

(ert-deftest emacsvox-aural-voice-drafts-local-failure-publishes-nothing ()
  "Failure of the first writer cannot publish palette references or live data."
  (emacsvox-test--with-voice-save
   (let ((proposal (emacsvox-aural-voice-drafts--prepare draft palette (list new-set) :select t))
         (before (emacsvox-aural-read-user-data)))
     (cl-letf (((symbol-function 'emacsvox-aural-routing--write-user-data)
                (lambda (&rest _) (error "Local storage unavailable")))
               ((symbol-function 'tts-apply-voice-configuration)
                (lambda (&rest _) (ert-fail "Cannot apply before both files succeed"))))
       (emacsvox-aural-voice-drafts--save proposal))
     (should (eq (emacsvox-aural-voice-save-state proposal) 'failed))
     (should-not (emacsvox-aural-voice-save-completed proposal))
     (should (equal (emacsvox-aural-read-user-data) before))
     (should (equal (emacsvox-aural-voice-draft-baseline draft) '(:pitch 0))))))

(ert-deftest emacsvox-aural-voice-drafts-recognizes-write-completed-before-error ()
  "A writer that publishes then signals can be retried without another rename."
  (emacsvox-test--with-voice-save
   (let ((proposal (emacsvox-aural-voice-drafts--prepare draft palette (list new-set)))
         (real-writer (symbol-function 'emacsvox-aural--write-user-data))
         (calls 0))
     (cl-letf (((symbol-function 'emacsvox-aural--write-user-data)
                (lambda (&rest args) (cl-incf calls) (apply real-writer args) (error "After rename"))))
       (emacsvox-aural-voice-drafts--save proposal)
       (should (eq (emacsvox-aural-voice-save-state proposal) 'partial))
       (emacsvox-aural-voice-drafts--save proposal)
       (should (= calls 1))
       (should (eq (emacsvox-aural-voice-save-state proposal) 'saved))))))

(ert-deftest emacsvox-aural-voice-drafts-inactive-save-does-not-apply-or-invalidate-current ()
  "Saving an inactive palette preserves current selection and apply ownership."
  (emacsvox-test--with-voice-save
   (let* ((emacsvox-aural-voice-palette-override 'alternative-owned)
          (emacsvox-aural-voice-runtime--last-snapshot (emacsvox-aural-voice-runtime--snapshot))
          (operation emacsvox-aural-routing--apply-operation)
          (proposal (emacsvox-aural-voice-drafts--prepare draft palette (list new-set))))
     (cl-letf (((symbol-function 'tts-apply-voice-configuration)
                (lambda (&rest _) (ert-fail "Collection save must not apply"))))
       (emacsvox-aural-voice-drafts--save proposal))
     (should (eq (emacsvox-aural-voice-save-state proposal) 'saved))
     (should (= operation emacsvox-aural-routing--apply-operation))
     (should (eq emacsvox-aural-voice-palette-override 'alternative-owned)))))

(ert-deftest emacsvox-aural-voice-drafts-temporary-alias-conflict-rejected-before-save ()
  "New conflicting temporary choices are checked again before either writer."
  (emacsvox-test--with-voice-save
   (let ((proposal (emacsvox-aural-voice-drafts--prepare draft palette (list new-set) :select t))
         (before (emacsvox-aural-voice-drafts--file-id emacsvox-aural-routing-profiles-file)))
     (setq emacsvox-aural-session-routing-bindings
           '((bolden (:kind exact :scope session :engine-id "dectalk" :voice-id "Paul"))
             (voice-bolden (:kind exact :scope session :engine-id "eloquence" :voice-id "Reed"))))
     (emacsvox-aural-voice-drafts--save proposal)
     (should (eq (emacsvox-aural-voice-save-state proposal) 'failed))
     (should (equal before (emacsvox-aural-voice-drafts--file-id emacsvox-aural-routing-profiles-file))))))

(ert-deftest emacsvox-aural-voice-drafts-does-not-claim-old-save-is-current-after-switch ()
  "A callback for the saved palette remains attached but cannot claim current apply."
  (emacsvox-test--with-voice-save
   (let ((proposal (emacsvox-aural-voice-drafts--prepare draft palette (list new-set) :select t)) callbacks)
     (cl-letf (((symbol-function 'tts-apply-voice-configuration)
                (lambda (&optional callback) (push callback callbacks))))
       (emacsvox-aural-voice-drafts--save proposal)
       (let ((saved-callback (car callbacks)))
         (emacsvox-aural-select-voice-palette 'alternative-owned)
         (funcall saved-callback '(:status applied))
         (should (eq (emacsvox-aural-voice-save-state proposal) 'superseded))
         (should (equal (emacsvox-aural-voice-draft-original draft) '(:pitch 0)))
         (should (eq (plist-get emacsvox-aural-routing-apply-status :palette) 'alternative-owned)))))))

(ert-deftest emacsvox-aural-voice-drafts-discard-prepared-save-cannot-later-write ()
  "Discarding an unstarted proposal cancels it even if an old view retained it."
  (emacsvox-test--with-voice-save
    (let ((proposal (emacsvox-aural-voice-drafts--prepare draft palette (list new-set)))
          (before (emacsvox-aural-voice-drafts--file-id emacsvox-aural-routing-profiles-file)))
      (emacsvox-aural-voice-drafts--discard draft)
      (emacsvox-aural-voice-drafts--save proposal)
      (should-not (emacsvox-aural-voice-draft-proposal draft))
      (should (equal before (emacsvox-aural-voice-drafts--file-id emacsvox-aural-routing-profiles-file))))))

(ert-deftest emacsvox-aural-voice-drafts-file-change-after-first-write-blocks-publication ()
  "An external palette edit during the local write survives the second preflight."
  (emacsvox-test--with-voice-save
    (let ((proposal (emacsvox-aural-voice-drafts--prepare draft palette (list new-set)))
          (real-writer (symbol-function 'emacsvox-aural-routing--write-user-data)) external)
      (cl-letf (((symbol-function 'emacsvox-aural-routing--write-user-data)
                 (lambda (&rest args)
                   (apply real-writer args)
                   (with-temp-buffer
                     (insert "; changed between saves\n")
                     (write-region (point-min) (point-max) emacsvox-aural-schemes-file t 'silent))
                   (setq external (emacsvox-aural-voice-drafts--file-id emacsvox-aural-schemes-file)))))
        (emacsvox-aural-voice-drafts--save proposal))
      (should (eq (emacsvox-aural-voice-save-state proposal) 'partial))
      (should (equal external (emacsvox-aural-voice-drafts--file-id emacsvox-aural-schemes-file)))
      (should-not (equal palette (emacsvox-aural-voice-drafts--palette-data 'reading-owned))))))

(provide 'emacsvox-aural-voice-drafts-tests)
;;; emacsvox-aural-voice-drafts-tests.el ends here
