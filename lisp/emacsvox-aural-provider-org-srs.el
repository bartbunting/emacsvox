;;; emacsvox-aural-provider-org-srs.el --- Org-srs aural provider -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Register Org-srs review semantics without loading Org-srs.  Live review
;; feedback is implemented by emacsvox-org-srs.el after Org-srs is loaded.

;;; Code:

(require 'emacsvox-aural-provider-workflows)

(defconst emacsvox-org-srs-aural-semantic-definitions
  '((learning-session
     :kind role
     :summary "A spaced-repetition review session"
     :owner org-srs
     :occasions (state-change notification inspection)
     :phases (before content after))
    (learning-item
     :kind role
     :summary "A question and answer reviewed through spaced repetition"
     :owner org-srs
     :occasions (navigation state-change notification inspection edit)
     :phases (before content after))
    (learning-phase
     :kind attribute
     :summary "The current stage of a spaced-repetition review"
     :owner org-srs
     :roles (learning-session learning-item)
     :value-type symbol
     :allowed-values (question answer result))
    (learning-item-kind
     :kind attribute
     :summary "The presentation form of a spaced-repetition item"
     :owner org-srs
     :roles (learning-item)
     :value-type symbol
     :allowed-values (card cloze))
    (learning-rating
     :kind attribute
     :summary "The recalled difficulty assigned to a learning item"
     :owner org-srs
     :roles (learning-session learning-item)
     :value-type symbol
     :allowed-values (again hard good easy))
    (learning-next-interval
     :kind attribute
     :summary "Seconds until the learning item is next due"
     :owner org-srs
     :roles (learning-session learning-item)
     :value-type integer)
    (learning-pending-count
     :kind attribute
     :summary "Number of learning items remaining in the review session"
     :owner org-srs
     :roles (learning-session learning-item)
     :value-type integer)
    (learning-session-started
     :kind event
     :summary "A spaced-repetition review session started"
     :owner org-srs
     :roles (learning-session learning-item)
     :occasions (state-change notification)
     :phases (before content after))
    (learning-question-presented
     :kind event
     :summary "A learning item's question was presented"
     :owner org-srs
     :roles (learning-item)
     :occasions (navigation state-change notification)
     :phases (before content after))
    (learning-answer-revealed
     :kind event
     :summary "A learning item's answer was revealed"
     :owner org-srs
     :roles (learning-item)
     :occasions (state-change notification)
     :phases (before content after))
    (learning-item-rated
     :kind event
     :summary "A learning item was rated and rescheduled"
     :owner org-srs
     :roles (learning-item)
     :occasions (state-change notification)
     :phases (before content after))
    (learning-session-finished
     :kind event
     :summary "A spaced-repetition review session finished"
     :owner org-srs
     :roles (learning-session)
     :occasions (state-change notification)
     :phases (before content after))
    (learning-session-stopped
     :kind event
     :summary "A spaced-repetition review session was stopped early"
     :owner org-srs
     :roles (learning-session)
     :occasions (state-change notification)
     :phases (before content after))
    (learning-item-postponed
     :kind event
     :summary "A learning item was postponed"
     :owner org-srs
     :roles (learning-item)
     :occasions (state-change notification)
     :phases (before content after))
    (learning-item-suspended
     :kind event
     :summary "A learning item was suspended"
     :owner org-srs
     :roles (learning-item)
     :occasions (state-change notification)
     :phases (before content after))
    (learning-rating-undone
     :kind event
     :summary "The most recent learning-item rating was undone"
     :owner org-srs
     :roles (learning-item)
     :occasions (state-change notification)
     :phases (before content after))
    (learning-rating-redone
     :kind event
     :summary "A previously undone learning-item rating was restored"
     :owner org-srs
     :roles (learning-item)
     :occasions (state-change notification)
     :phases (before content after))
    (learning-item-created
     :kind event
     :summary "A spaced-repetition item was created"
     :owner org-srs
     :roles (learning-item)
     :occasions (edit state-change notification)
     :phases (before content after))
    (learning-cloze-updated
     :kind event
     :summary "The cloze items in an Org entry were updated"
     :owner org-srs
     :roles (learning-item)
     :occasions (edit state-change notification)
     :phases (before content after)))
  "Semantic definitions owned by the Org-srs integration.")

(defun emacsvox-org-srs-register-aural-presentation ()
  "Register Org-srs semantics and default review cues."
  (dolist (definition emacsvox-org-srs-aural-semantic-definitions)
    (let ((id (car definition))
          (metadata (cdr definition)))
      (unless (emacsvox-aural-semantic id)
        (apply #'emacsvox-aural-register-semantic id metadata))))
  (emacsvox-aural-validate-registry)
  (unless (gethash 'org-srs-review-feedback
                   emacsvox-aural-module-fragment-registry)
    (emacsvox-aural-register-module-fragment
     'org-srs
     '(:schema-version 1
       :id org-srs-review-feedback
       :summary "Present the question, reveal, and completion stages of Org-srs reviews"
       :rules
       ((:id org-srs-question-cue
         :match
         (:role learning-item :module org-srs
          :event learning-question-presented)
         :render
         (:before
          ((:id org-srs-question-cue-action
            :kind cue :cue ask-question))))
        (:id org-srs-answer-cue
         :match
         (:role learning-item :module org-srs
          :event learning-answer-revealed)
         :render
         (:before
          ((:id org-srs-answer-cue-action
            :kind cue :cue open-object))))
        (:id org-srs-finished-cue
         :match
         (:role learning-session :module org-srs
          :event learning-session-finished)
         :render
         (:after
          ((:id org-srs-finished-cue-action
            :kind cue :cue task-done))))
        (:id org-srs-stopped-cue
         :match
         (:role learning-session :module org-srs
          :event learning-session-stopped)
         :render
         (:after
          ((:id org-srs-stopped-cue-action
            :kind cue :cue close-object))))))
     :source "emacsvox-aural-provider-org-srs")))

(emacsvox-org-srs-register-aural-presentation)

(provide 'emacsvox-aural-provider-org-srs)
;;; emacsvox-aural-provider-org-srs.el ends here
