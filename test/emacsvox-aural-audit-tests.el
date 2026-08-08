;;; emacsvox-aural-audit-tests.el --- Aural contract audit tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Verify safe cue and tone source scanning, generated-reference determinism,
;; and the repository-wide registry/documentation contract.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-aural-audit)

(defvar emacsvox-test--aural-read-evaluated nil)

(defconst emacsvox-test--aural-audit-root
  (file-name-as-directory
   (expand-file-name
    ".."
    (file-name-directory (or load-file-name buffer-file-name))))
  "Repository root used by the aural audit tests.")

(cl-defmacro emacsvox-test--with-aural-audit-root ((root) &rest body)
  "Create temporary audit ROOT and evaluate BODY."
  (declare (indent 1) (debug (sexp body)))
  `(let ((,root (make-temp-file "emacsvox-aural-audit-" t)))
     (unwind-protect
         (progn
           (make-directory (expand-file-name "lisp" ,root))
           (make-directory (expand-file-name "etc" ,root))
           ,@body)
       (delete-directory ,root t))))

(defun emacsvox-test--write-aural-audit-source (root text &optional basename)
  "Write TEXT to BASENAME below the Lisp directory in audit ROOT."
  (let ((file
         (expand-file-name
          (concat "lisp/" (or basename "example.el")) root)))
    (with-temp-buffer
      (insert text)
      (write-region (point-min) (point-max) file nil 'silent))
    file))

(ert-deftest emacsvox-aural-audit-parses-code-without-evaluation ()
  "The cue audit should ignore comments, strings, and quoted data."
  (emacsvox-test--with-aural-audit-root (root)
    (emacsvox-test--write-aural-audit-source
     root
     (concat
      "(emacsvox-icon 'item)\n"
      "(emacsvox-icon icon-variable)\n"
      "(emacsvox-queue-icon 'warn-user)\n"
      ";; (emacsvox-icon 'alarm)\n"
      "\"(emacsvox-icon 'alarm)\"\n"
      "'(emacsvox-icon 'unregistered-quoted-data)\n"))
    (let* ((report (emacsvox-aural-audit-source-cues root))
           (usage (plist-get report :usage)))
      (should (= (plist-get report :literal-count) 2))
      (should (= (plist-get report :dynamic-count) 1))
      (should-not (plist-get report :parse-errors))
      (should (equal (mapcar #'car usage) '(item warn-user))))))

(ert-deftest emacsvox-aural-audit-inventories-legacy-tone-calls ()
  "Tone inventory separates literal raw tones from dynamic and helper calls."
  (emacsvox-test--with-aural-audit-root (root)
    (emacsvox-test--write-aural-audit-source
     root
     (concat
      "(tts-tone 440 100 'force)\n"
      "(tts-tone pitch 75)\n"
      "(tts-tone-deletion)\n"
      "(tts-tone-upcase)\n"
      "(tts-tone-downcase)\n"
      ";; (tts-tone 220 50)\n"
      "\"(tts-tone 220 50)\"\n"
      "'(tts-tone 220 50)\n"))
    (let* ((report (emacsvox-aural-audit-source-tones root))
           (usage (plist-get report :usage))
           (signature (car (plist-get report :signatures))))
      (should (= (plist-get report :raw-literal-count) 1))
      (should (= (plist-get report :raw-dynamic-count) 1))
      (should (= (length (plist-get report :unmigrated-calls)) 5))
      (should-not (plist-get report :parse-errors))
      (should
       (equal
        (mapcar #'car usage)
        '(tts-tone tts-tone-deletion tts-tone-downcase tts-tone-upcase)))
      (should (equal (car signature) '(440 100 force)))
      (should (= (plist-get (cdr signature) :count) 1))
      (should
       (equal
        (plist-get (cdr signature) :files)
        '("lisp/example.el"))))))

(ert-deftest emacsvox-aural-audit-does-not-count-definition-names-as-calls ()
  "Function names in definitions are not executable cue or tone calls."
  (emacsvox-test--with-aural-audit-root (root)
    (emacsvox-test--write-aural-audit-source
     root
     (concat
      "(defun emacsvox-icon (icon) icon)\n"
      "(defun emacsvox-queue-icon (icon) icon)\n"
      "(defsubst tts-tone-upcase () nil)\n"
      "(defsubst tts-tone-downcase () nil)\n"
      "(defsubst tts-tone-deletion () nil)\n"
      "(defun tts-tone (pitch duration &optional force)\n"
      "  (list pitch duration force))\n"))
    (let ((cues (emacsvox-aural-audit-source-cues root))
          (tones (emacsvox-aural-audit-source-tones root)))
      (should-not (plist-get cues :usage))
      (should (zerop (plist-get cues :dynamic-count)))
      (should-not (plist-get tones :usage))
      (should (zerop (plist-get tones :raw-literal-count)))
      (should (zerop (plist-get tones :raw-dynamic-count))))))

(ert-deftest emacsvox-aural-audit-rejects-context-free-migrated-icons ()
  "Migrated modules may emit icons only below their semantic boundary."
  (emacsvox-test--with-aural-audit-root (root)
    (emacsvox-test--write-aural-audit-source
     root
     (concat
      "(defun unsafe-feedback () (emacsvox-icon 'item))\n"
      "(defun safe-feedback ()\n"
      "  (emacsvox-notmuch--call-with-aural-presentation\n"
      "   '(:role message) 'navigation\n"
      "   (lambda () (emacsvox-icon 'item))))\n"
      "(defun old-feedback-compatibility ()\n"
      "  (emacsvox-icon 'item))\n"
      "(defun leaked-compatibility-feedback ()\n"
      "  (old-feedback-compatibility))\n")
     "emacsvox-notmuch.el")
    (should
     (equal
      (emacsvox-aural-audit-context-free-icons root)
      '((:file "lisp/emacsvox-notmuch.el"
         :function leaked-compatibility-feedback
         :icon-function emacsvox-icon
         :compatibility-function old-feedback-compatibility)
        (:file "lisp/emacsvox-notmuch.el"
         :function unsafe-feedback
         :icon-function emacsvox-icon))))))

(ert-deftest emacsvox-aural-audit-rejects-nested-submission-resolvers ()
  "A native transaction cannot contain another complete presentation path."
  (emacsvox-test--with-aural-audit-root (root)
    (emacsvox-test--write-aural-audit-source
     root
     (concat
      "(defun safe-feedback (text)\n"
      "  (emacsvox-aural-submit\n"
      "   text :facts '(:role message)\n"
      "   :compatibility-actions\n"
      "   (list (emacsvox-aural-compatibility-icon 'item))))\n"
      "(defun duplicate-feedback (text)\n"
      "  (emacsvox-aural-submit\n"
      "   (progn (emacsvox-icon 'item) (tts-speak text))\n"
      "   :facts '(:role message)))\n"
      "(defun duplicate-action-feedback ()\n"
      "  (emacsvox-aural-submit-actions\n"
      "   :facts\n"
      "   (progn (emacsvox-aural-present '(:event boundary))\n"
      "          '(:event boundary))))\n")
     "emacsvox-notmuch.el")
    (should
     (equal
      (emacsvox-aural-audit-nested-submission-resolutions root)
      '((:file "lisp/emacsvox-notmuch.el"
         :function duplicate-action-feedback
         :resolver emacsvox-aural-present)
        (:file "lisp/emacsvox-notmuch.el"
         :function duplicate-feedback
         :resolver emacsvox-icon)
        (:file "lisp/emacsvox-notmuch.el"
         :function duplicate-feedback
         :resolver tts-speak))))))

(ert-deftest emacsvox-aural-audit-never-evaluates-reader-forms ()
  "The source audit should reject `#.' without evaluating its payload."
  (emacsvox-test--with-aural-audit-root (root)
    (emacsvox-test--write-aural-audit-source
     root
     (concat
      "#.(progn\n"
      "    (setq emacsvox-test--aural-read-evaluated t)\n"
      "    '(emacsvox-icon 'alarm))\n"))
    (setq emacsvox-test--aural-read-evaluated nil)
    (let ((report (emacsvox-aural-audit-source-cues root))
          (tones (emacsvox-aural-audit-source-tones root)))
      (should-not emacsvox-test--aural-read-evaluated)
      (should (plist-get report :parse-errors))
      (should (plist-get tones :parse-errors)))))

(ert-deftest emacsvox-aural-audit-reports-unregistered-literal-cues ()
  "An unregistered cue in executable source should fail the audit."
  (emacsvox-test--with-aural-audit-root (root)
    (emacsvox-test--write-aural-audit-source
     root "(emacsvox-icon 'not-a-registered-cue)\n")
    (emacsvox-aural-write-reference root)
    (let ((audit (emacsvox-aural-audit-directory root)))
      (should-not (emacsvox-aural-audit-clean-p audit))
      (should
       (equal
        (mapcar #'car (plist-get audit :unknown-cues))
        '(not-a-registered-cue))))))

(ert-deftest emacsvox-aural-audit-rejects-unmigrated-tone-calls ()
  "Application-level legacy tones fail the repository contract."
  (emacsvox-test--with-aural-audit-root (root)
    (emacsvox-test--write-aural-audit-source
     root
     "(defun application-feedback () (tts-tone 440 100))\n")
    (emacsvox-aural-write-reference root)
    (let* ((audit (emacsvox-aural-audit-directory root))
           (failure (car (plist-get audit :unmigrated-tone-calls))))
      (should-not (emacsvox-aural-audit-clean-p audit))
      (should (equal (plist-get failure :file) "lisp/example.el"))
      (should (eq (plist-get failure :function) 'application-feedback))
      (should (eq (plist-get failure :tone-function) 'tts-tone))
      (should (equal (plist-get failure :signature) '(440 100 nil))))))

(ert-deftest emacsvox-aural-reference-is-deterministic-and-complete ()
  "The generated reference should expose each author contract and registry."
  (let ((first
         (emacsvox-aural-reference-string
          emacsvox-test--aural-audit-root))
        (second
         (emacsvox-aural-reference-string
          emacsvox-test--aural-audit-root)))
    (should (string= first second))
    (dolist
        (heading
         '("* Presentation Rule Author Reference"
           "* Module Author Reference"
           "* Semantic Registry"
           "** Built-in Feature Fragments"
           "* Sound Pack Author Reference"
           "* Voice Palette Author Reference"
           "* Compatibility, Migration, and Rollout"))
      (should (string-match-p (regexp-quote heading) first)))
    (should (string-match-p "| =heading= | =role= | =core= |" first))
    (should
     (string-match-p
      "| =org-heading-level-labels= | =org= | =1= | =1= | emacsvox-aural-provider-org |"
      first))
    (should
     (string-match-p
      "| =mail-message-status-cues= | =mail= | =5= | =4= | emacsvox-aural-provider-workflows |"
      first))
    (should (string-match-p "| =chimes= | =sound= |" first))
    (should (string-match-p "| =bolden= | =voice-bolden= |" first))))

(ert-deftest emacsvox-aural-reference-detects-stale-output ()
  "Reference comparison should reject content not produced by the generator."
  (emacsvox-test--with-aural-audit-root (root)
    (let ((file (expand-file-name "etc/reference.org" root)))
      (with-temp-buffer
        (insert "stale\n")
        (write-region (point-min) (point-max) file nil 'silent))
      (should-not
       (emacsvox-aural-reference-current-p root file))
      (emacsvox-aural-write-reference root file)
      (should (emacsvox-aural-reference-current-p root file)))))

(ert-deftest emacsvox-aural-audit-current-tree-is-clean ()
  "Registries, literal source cues, packs, schemes, and docs should agree."
  (let ((audit
         (emacsvox-aural-audit-directory
          emacsvox-test--aural-audit-root)))
    (unless (emacsvox-aural-audit-clean-p audit)
      (ert-fail (emacsvox-aural-audit-format audit)))))

(provide 'emacsvox-aural-audit-tests)
;;; emacsvox-aural-audit-tests.el ends here
