;;; emacsvox-aural-spatial.el --- Portable aural spatialization -*- lexical-binding: t; -*-

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

;; Define the portable spatial contract and user policy independently of
;; speech and cue transports.  Declarative presentation rules request normalized
;; stereo balance or listener-relative azimuth; transport compilation reduces
;; that request to the capability of the selected backend.

;;; Code:

(require 'cl-lib)

(defgroup emacsvox-aural-spatial nil
  "Portable spatial presentation of Emacsvox speech and cues."
  :group 'emacsvox)

(defcustom emacsvox-aural-spatial-enabled t
  "Non-nil enables spatial presentation globally.

Disabling this option preserves every speech and cue action but centers it."
  :type 'boolean
  :group 'emacsvox-aural-spatial)

(defcustom emacsvox-aural-spatial-speech-enabled t
  "Non-nil permits spatial presentation of speech."
  :type 'boolean
  :group 'emacsvox-aural-spatial)

(defcustom emacsvox-aural-spatial-cue-enabled t
  "Non-nil permits spatial presentation of auditory cues."
  :type 'boolean
  :group 'emacsvox-aural-spatial)

(defcustom emacsvox-aural-spatial-output 'auto
  "Declared spatial capability of the final audio output.

`auto' uses each transport adapter's reported capability.  `mono' forces
portable centered compilation even when an adapter can produce stereo."
  :type
  '(choice
    (const :tag "Use backend capability" auto)
    (const :tag "Mono output" mono))
  :group 'emacsvox-aural-spatial)

(defcustom emacsvox-aural-spatial-maximum-separation 1.0
  "Maximum absolute stereo balance after user remapping.

The value is between 0.0 for centered output and 1.0 for full separation."
  :type '(float :tag "Maximum absolute balance")
  :safe (lambda (value)
          (and (numberp value) (<= 0.0 value) (<= value 1.0)))
  :group 'emacsvox-aural-spatial)

(defcustom emacsvox-aural-spatial-remapping 'normal
  "User remapping applied to normalized balance requests.

`normal' preserves direction, `reverse' swaps left and right,
`collapse-left' centers positions requested on the left, `collapse-right'
centers positions requested on the right, and `center' centers everything.
A function value receives and returns a balance in the range -1.0 to 1.0."
  :type
  '(choice
    (const :tag "Normal" normal)
    (const :tag "Reverse left and right" reverse)
    (const :tag "Center left-side requests" collapse-left)
    (const :tag "Center right-side requests" collapse-right)
    (const :tag "Center all requests" center)
    (function :tag "Custom remapping function"))
  :group 'emacsvox-aural-spatial)

(defvar emacsvox-aural-speech-balance-function nil
  "Optional speech-adapter function for queueing a normalized BALANCE.

When non-nil, the function is called before spatial speech and again with
0.0 after it.  Its presence reports stereo speech capability.")

(defvar emacsvox-aural-queued-cue-balance-function nil
  "Optional ordered-cue adapter accepting RESOURCE and normalized BALANCE.

When non-nil, it replaces the ordinary speech-server resource queue call and
reports stereo capability for ordered cues.")

(defun emacsvox-aural-spatial-clamp (value)
  "Clamp numeric VALUE to normalized stereo balance."
  (max -1.0 (min 1.0 (float value))))

(defun emacsvox-aural-spatial-validate-space (space label)
  "Validate declarative SPACE and return a copy, reporting errors with LABEL.

The stable contract accepts exactly one of `:balance' in -1.0..1.0 or
listener-relative `:azimuth' in -180..180 degrees.  Positive values are right,
negative values are left, zero azimuth is front, and +/-180 is rear."
  (unless
      (and
       (listp space)
       (proper-list-p space)
       (zerop (% (length space) 2))
       (cl-loop for (key _) on space by #'cddr always (keywordp key)))
    (error "%s must be a keyword plist: %S" label space))
  (let* ((allowed '(:balance :azimuth))
         (unknown
          (cl-loop
           for (key _) on space by #'cddr
           unless (memq key allowed)
           collect key))
         (balance-p (plist-member space :balance))
         (azimuth-p (plist-member space :azimuth))
         (balance (plist-get space :balance))
         (azimuth (plist-get space :azimuth)))
    (when unknown
      (error "%s contains unknown spatial properties: %S" label unknown))
    (unless (or balance-p azimuth-p)
      (error "%s requires :balance or :azimuth" label))
    (when (and balance-p azimuth-p)
      (error "%s cannot combine :balance and :azimuth" label))
    (when
        (and
         balance-p
         (not (and (numberp balance) (<= -1.0 balance) (<= balance 1.0))))
      (error "%s :balance must be between -1.0 and 1.0: %S" label balance))
    (when
        (and
         azimuth-p
         (not
          (and (numberp azimuth) (<= -180.0 azimuth) (<= azimuth 180.0))))
      (error "%s :azimuth must be between -180 and 180 degrees: %S"
             label azimuth))
    (copy-tree space)))

(defun emacsvox-aural-spatial-requested-balance (space)
  "Reduce declarative SPACE to normalized stereo balance."
  (cond
   ((null space) 0.0)
   ((plist-member space :balance)
    (float (plist-get space :balance)))
   (t
    (sin (* float-pi (/ (float (plist-get space :azimuth)) 180.0))))))

(defun emacsvox-aural-spatial--remap (balance)
  "Apply the configured user remapping to BALANCE."
  (emacsvox-aural-spatial-clamp
   (pcase emacsvox-aural-spatial-remapping
     ('normal balance)
     ('reverse (- balance))
     ('collapse-left (if (< balance 0.0) 0.0 balance))
     ('collapse-right (if (> balance 0.0) 0.0 balance))
     ('center 0.0)
     ((pred functionp)
      (funcall emacsvox-aural-spatial-remapping balance))
     (_ balance))))

(defun emacsvox-aural-spatial-apply-user-policy (balance kind)
  "Apply spatial user policy to BALANCE for speech or cue KIND.

Return a plist containing `:balance' and zero or more `:reasons'."
  (let (reasons)
    (cond
     ((not emacsvox-aural-spatial-enabled)
      (setq balance 0.0)
      (push 'spatialization-disabled reasons))
     ((and (eq kind 'speech)
           (not emacsvox-aural-spatial-speech-enabled))
      (setq balance 0.0)
      (push 'speech-spatialization-disabled reasons))
     ((and (eq kind 'cue)
           (not emacsvox-aural-spatial-cue-enabled))
      (setq balance 0.0)
      (push 'cue-spatialization-disabled reasons))
     (t
      (let ((remapped (emacsvox-aural-spatial--remap balance)))
        (unless (= remapped balance)
          (push 'user-remapping reasons))
        (setq balance remapped))
      (let* ((maximum
              (emacsvox-aural-spatial-clamp
               emacsvox-aural-spatial-maximum-separation))
             (limited (max (- maximum) (min maximum balance))))
        (unless (= limited balance)
          (push 'maximum-separation reasons))
        (setq balance limited))))
    (list :balance balance :reasons (nreverse reasons))))

(defun emacsvox-aural-spatial-capability (target)
  "Return spatial capability for transport TARGET.

TARGET is one of `speech', `queued-cue', or `local-cue'.  Capability values
are `stereo' and `centered'; local-player support is supplied by the sound
module without creating a dependency from this policy module."
  (if (eq emacsvox-aural-spatial-output 'mono)
      'mono
    (pcase target
      ('speech
       (if (functionp emacsvox-aural-speech-balance-function)
           'stereo
         'centered))
      ('queued-cue
       (if (functionp emacsvox-aural-queued-cue-balance-function)
           'stereo
         'centered))
      ('local-cue
       (if (fboundp 'emacsvox-sounds-spatial-capability)
           (let ((capability (emacsvox-sounds-spatial-capability)))
             (if (memq capability '(stereo mono centered))
                 capability
               'centered))
         'centered))
      (_ 'centered))))

(defun emacsvox-aural-spatial-capabilities ()
  "Report current portable spatial capabilities as a plist."
  (list
   :speech (emacsvox-aural-spatial-capability 'speech)
   :queued-cue (emacsvox-aural-spatial-capability 'queued-cue)
   :local-cue (emacsvox-aural-spatial-capability 'local-cue)))

(provide 'emacsvox-aural-spatial)

;;; emacsvox-aural-spatial.el ends here
