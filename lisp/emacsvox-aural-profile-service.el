;;; emacsvox-aural-profile-service.el --- Aural profile service -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Stable non-UI operations over presentation-profile state.  Profile
;; managers and diagnostics depend on this service rather than each other's
;; private functions.

;;; Code:

(require 'emacsvox-aural-schemes)

(defun emacsvox-aural-current-profile-id ()
  "Return the selected presentation-profile identifier, or nil."
  (and
   (emacsvox-aural-profile-entry emacsvox-aural-active-profile)
   emacsvox-aural-active-profile))

(provide 'emacsvox-aural-profile-service)
;;; emacsvox-aural-profile-service.el ends here
