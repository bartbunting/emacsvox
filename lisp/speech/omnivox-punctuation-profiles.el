;;; omnivox-punctuation-profiles.el --- Negotiated punctuation profiles -*- lexical-binding: t; -*-

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
;; Named mode values retain a built-in fallback.  Each live worker supplies its
;; immutable catalogue; IDs alone never establish cross-worker agreement.
;;; Code:
(require 'cl-lib)
(require 'seq)
(defvar tts-speaker-process)
(defvar tts-notify-process)
(declare-function omnivox--send-control-request "omnivox-voices" (process request callback))

(defun omnivox-punctuation-profiles--mode-p (mode)
  "Whether MODE is a valid saved named selection with a built-in fallback."
  (and (listp mode) (= (length mode) 3) (eq (car mode) 'profile)
       (stringp (cadr mode))
       (string-match-p "\\`[a-z][a-z0-9_-]\\{0,31\\}\\'" (cadr mode))
       (not (member (cadr mode) '("none" "some" "all")))
       (memq (nth 2 mode) '(none some all))))

(defun omnivox-punctuation-profiles--fallback (mode)
  "Return the built-in wire level for MODE, rejecting malformed preferences."
  (cond ((memq mode '(none some all)) mode)
        ((member mode '("none" "some" "all")) (intern mode))
        ((omnivox-punctuation-profiles--mode-p mode) (nth 2 mode))
        (t (user-error "Invalid punctuation selection"))))

(defun omnivox-punctuation-profiles--workers ()
  "Return the current pair, preserving identity during notification rebinding."
  (let* ((main (if (eq tts-speaker-process tts-notify-process)
                   (and (processp tts-notify-process)
                        (process-get tts-notify-process 'omnivox-punctuation-main))
                 tts-speaker-process))
         (notify tts-notify-process))
    (when (and (processp main) (processp notify)
               (not (eq main notify))
               (not (eq (process-get main 'tts--speech-process-role) 'notification)))
      (process-put notify 'omnivox-punctuation-main main))
    (if notify (list main notify) (list main))))

(defun omnivox-punctuation-profiles--agreed ()
  "Return immutable descriptors shared by all current speech workers."
  (let ((workers (omnivox-punctuation-profiles--workers)))
    (when (and workers (cl-every (lambda (process) (and (processp process) (process-live-p process))) workers))
      (seq-filter
       (lambda (entry)
         (cl-every (lambda (process)
                     (equal entry (seq-find (lambda (other) (equal (plist-get entry :id) (plist-get other :id)))
                                            (process-get process 'omnivox-punctuation-profiles))))
                   (cdr workers)))
       (process-get (car workers) 'omnivox-punctuation-profiles)))))

(defun omnivox-punctuation-profiles--receive (process response)
  "Validate and retain PROCESS's frozen profile catalogue RESPONSE."
  (let ((profiles (plist-get response :profiles)) ids)
    (when (and (equal (plist-get response :type) "punctuation_profiles_v1")
               (sequencep profiles) (<= (length profiles) 32)
               (cl-every
                (lambda (entry)
                  (let ((id (plist-get entry :id)) (fallback (plist-get entry :fallback))
                        (hash (plist-get entry :sha256)))
                    (and (stringp fallback)
                         (omnivox-punctuation-profiles--mode-p (list 'profile id (intern fallback)))
                         (not (member id ids)) (push id ids)
                         (stringp hash) (string-match-p "\\`[a-f0-9]\\{64\\}\\'" hash)))) profiles))
      (process-put process 'omnivox-punctuation-profiles (append profiles nil))
      (omnivox-punctuation-profiles--workers))))

(defun omnivox-punctuation-profiles--negotiate (process capabilities)
  "Request PROCESS's catalogue only when CAPABILITIES advertise support."
  (process-put process 'omnivox-punctuation-profiles nil)
  (when (member "punctuation_profiles_v1" (plist-get capabilities :features))
    (omnivox--send-control-request process '(:type "get_punctuation_profiles_v1")
                                   #'omnivox-punctuation-profiles--receive)))

(defun omnivox-punctuation-profiles--command (mode process)
  "Return an optional negotiated profile command for MODE on PROCESS."
  (when (omnivox-punctuation-profiles--mode-p mode)
    (let* ((entry (seq-find (lambda (entry) (equal (cadr mode) (plist-get entry :id)))
                            (omnivox-punctuation-profiles--agreed)))
           (local (and (processp process)
                       (seq-find (lambda (entry) (equal (cadr mode) (plist-get entry :id)))
                                 (process-get process 'omnivox-punctuation-profiles)))))
      (when (and entry (equal entry local)
                 (equal (symbol-name (nth 2 mode)) (plist-get entry :fallback)))
        (format "tts_set_punctuation_profile %s\n" (cadr mode))))))

(defun omnivox-punctuation-profiles--describe (mode)
  "Describe MODE and any fallback caused by missing or disagreeing workers."
  (if (omnivox-punctuation-profiles--mode-p mode)
      (format "%s (%s)" (cadr mode)
              (if (omnivox-punctuation-profiles--command mode tts-speaker-process)
                  "named profile" (format "using %s fallback; profile unavailable or workers differ" (nth 2 mode))))
    (symbol-name (omnivox-punctuation-profiles--fallback mode))))

(defun omnivox-punctuation-profiles--read ()
  "Read a built-in level or an agreed named profile with its saved fallback."
  (let* ((profiles (omnivox-punctuation-profiles--agreed))
         (choice (completing-read "Punctuation: "
                                  (append '("none" "some" "all")
                                          (mapcar (lambda (entry) (plist-get entry :id)) profiles)) nil t))
         (profile (seq-find (lambda (entry) (equal choice (plist-get entry :id))) profiles)))
    (if profile (list 'profile choice (intern (plist-get profile :fallback))) (intern choice))))

(provide 'omnivox-punctuation-profiles)
;;; omnivox-punctuation-profiles.el ends here
