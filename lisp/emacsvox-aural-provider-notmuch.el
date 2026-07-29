;;; emacsvox-aural-provider-notmuch.el --- Data-only Notmuch aural provider -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Register Notmuch-specific preview metadata without loading Notmuch.
;; Shared mail semantics and presentation options come from the workflow
;; provider.  Live fact capture remains in emacsvox-notmuch.el.

;;; Code:

(require 'emacsvox-aural-provider-workflows)

(defconst emacsvox-notmuch-aural-feature-fragment-examples
  '((mail-message-status-cues notmuch-unread-message
     :rule workflow-mail-unread
     :summary "Unread Notmuch search result"
     :facts
     (:role message :states (unread)
      :content "Alice, project update")
     :context
     (:module notmuch :mode notmuch-search-mode :occasion navigation))
    (mail-message-status-cues notmuch-message-with-attachment
     :rule workflow-mail-attachments
     :summary "Notmuch message containing an attachment"
     :facts
     (:role message :states (has-attachments)
      :content "Bob, meeting notes")
     :context
     (:module notmuch :mode notmuch-show-mode :occasion navigation))
    (mail-message-status-cues notmuch-forwarded-message
     :rule workflow-mail-forwarded
     :summary "Forwarded Notmuch message"
     :facts
     (:role message :states (forwarded)
      :content "Carol, project handoff")
     :context
     (:module notmuch :mode notmuch-search-mode :occasion navigation))
    (mail-message-status-cues notmuch-replied-message
     :rule workflow-mail-replied
     :summary "Replied-to Notmuch message"
     :facts
     (:role message :states (replied)
      :content "David, meeting follow-up")
     :context
     (:module notmuch :mode notmuch-search-mode :occasion navigation)))
  "Curated data-only Notmuch previews for optional mail presentation.")

(defun emacsvox-notmuch-register-aural-preview-examples ()
  "Register curated Notmuch presentation-option preview examples."
  (dolist (definition emacsvox-notmuch-aural-feature-fragment-examples)
    (apply
     #'emacsvox-aural-register-feature-fragment-example
     (car definition)
     (cadr definition)
     :source "emacsvox-aural-provider-notmuch"
     (cddr definition))))

(emacsvox-notmuch-register-aural-preview-examples)

(provide 'emacsvox-aural-provider-notmuch)
;;; emacsvox-aural-provider-notmuch.el ends here
