;;; emacsvox-aural-provider-notmuch.el --- Data-only Notmuch aural provider -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: Emacsvox contributors
;; Maintainer: Emacsvox contributors
;; Keywords: accessibility, multimedia
;; URL: https://github.com/bartbunting/emacsvox

;; This file is part of Emacsvox.
;;
;; Emacsvox is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; Emacsvox is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Emacsvox.  If not, see <https://www.gnu.org/licenses/>.

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
