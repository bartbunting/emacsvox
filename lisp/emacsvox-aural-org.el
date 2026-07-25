;;; emacsvox-aural-org.el --- Data-only Org aural schemes -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Register the lightweight Org compatibility fragment and selectable example
;; schemes before personal aural data is loaded.  This file deliberately does
;; not load Org itself; live semantic fact capture remains in emacsvox-org.el.

;;; Code:

(require 'emacsvox-aural-schemes)

(defconst emacsvox-org-aural-semantics
  '(heading level folded focus-entered state-changed object-changed)
  "Core semantic identifiers interpreted by the Org integration.")

(defconst emacsvox-org-aural-level-voices
  '((1 . bolden)
    (2 . brighten)
    (3 . animate)
    (4 . lighten)
    (5 . smoothen)
    (6 . monotone)
    (7 . lighten-medium)
    (8 . lighten-extra))
  "Voice-palette entries used by the Org voice-only example scheme.")

(defun emacsvox-org--require-aural-semantics ()
  "Verify that every semantic interpreted by Org is registered."
  (dolist (semantic emacsvox-org-aural-semantics)
    (unless (emacsvox-aural-semantic semantic)
      (error "Org requires unregistered aural semantic %S" semantic))))

(defun emacsvox-org--voice-only-rules ()
  "Return declarative level rules for the voice-only Org example."
  (mapcar
   (lambda (entry)
     (let ((level (car entry))
           (voice (cdr entry)))
       (list
        :id (intern (format "org-voice-heading-level-%d" level))
        :match (list :role 'heading :module 'org :level level)
        :render (list :content (list :voice voice)))))
   emacsvox-org-aural-level-voices))

(defun emacsvox-org--spoken-label-rules ()
  "Return declarative level rules for the spoken-label Org example."
  (mapcar
   (lambda (entry)
     (let ((level (car entry)))
       (list
        :id (intern (format "org-spoken-heading-level-%d" level))
        :match
        (list
         :role 'heading :module 'org :level level
         :occasion 'navigation)
        :render
        (list
         :before
         (list
          (list
           :id (intern (format "org-heading-level-%d-label" level))
           :kind 'speech
           :text (format "Heading %d" level)))
         :after
         '(:remove (org-heading-navigation-movement))))))
   emacsvox-org-aural-level-voices))

(defun emacsvox-org-aural-example-scheme-data ()
  "Return the built-in data-only Org example schemes."
  (list
   (list
    :schema-version 1
    :id 'org-voice-only
    :summary "Org heading levels presented only through distinct voices"
    :parent 'default
    :rules
    (append
     (emacsvox-org--voice-only-rules)
     '((:id org-voice-only-remove-navigation-cue
        :match (:role heading :module org :occasion navigation)
        :render
        (:after (:remove (org-heading-navigation-movement)))))))
   (list
    :schema-version 1
    :id 'org-spoken-label
    :summary "Org heading levels spoken before heading contents"
    :parent 'default
    :rules (emacsvox-org--spoken-label-rules))
   '(:schema-version 1
     :id org-cue-only
     :summary "Org headings introduced by one semantic section cue"
     :parent default
     :rules
     ((:id org-cue-only-heading
       :match (:role heading :module org :occasion navigation)
       :render
       (:before
        ((:id org-heading-section-cue :kind cue :cue section))
        :after (:remove (org-heading-navigation-movement))))))
   '(:schema-version 1
     :id org-combined
     :summary "Org headings combine a label, cue, and content voice"
     :parent default
     :rules
     ((:id org-combined-heading
       :match (:role heading :module org :occasion navigation)
       :render
       (:before
        ((:id org-combined-label :kind speech :text "Heading")
         (:id org-combined-cue :kind cue :cue section))
        :content (:voice bolden)
        :after (:remove (org-heading-navigation-movement))))))
   '(:schema-version 1
     :id org-before-after
     :summary "Org headings use explicit speech before and after contents"
     :parent default
     :rules
     ((:id org-before-after-heading
       :match (:role heading :module org :occasion navigation)
       :render
       (:before
        ((:id org-before-label :kind speech :text "Heading"))
        :after
        (:replace
         ((:id org-after-label :kind speech :text "end heading")))))))
   '(:schema-version 1
     :id org-folded-state
     :summary "Folded Org headings announce their state after contents"
     :parent default
     :rules
     ((:id org-folded-heading-state
       :match (:role heading :module org :state folded)
       :render
       (:after
        ((:id org-folded-label :kind speech :text "folded"))))))))

(defun emacsvox-org-register-aural-presentation ()
  "Register Org compatibility rules and selectable example schemes."
  (emacsvox-org--require-aural-semantics)
  (unless (gethash 'org-compatibility
                   emacsvox-aural-module-fragment-registry)
    (emacsvox-aural-register-module-fragment
     'org
     '(:schema-version 1
       :id org-compatibility
       :summary "Compatibility presentation for semantic Org headings"
       :rules
       ((:id org-heading-navigation-compatibility
         :match (:role heading :module org :occasion navigation)
         :render
         (:after
          ((:id org-heading-navigation-movement
            :kind cue
            :cue large-movement))))
        (:id org-heading-edit-compatibility
         :match (:role heading :module org :occasion edit)
         :render
         (:after
          ((:id org-heading-edit-open
            :kind cue
            :cue open-object))))))
     :source "emacsvox-aural-org"))
  (dolist (data (emacsvox-org-aural-example-scheme-data))
    (unless (emacsvox-aural-scheme-entry (plist-get data :id))
      (emacsvox-aural-register-scheme
       data :built-in t :source "emacsvox-aural-org"))))

(emacsvox-org-register-aural-presentation)

(provide 'emacsvox-aural-org)
;;; emacsvox-aural-org.el ends here
