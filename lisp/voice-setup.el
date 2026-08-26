;;; voice-setup.el --- Setup voices for voice-lock  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Voice lock mode for Emacsvox
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4672 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; All Rights Reserved.
;; 
;; This file is not part of GNU Emacs, but the same permissions apply.
;; 
;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;; 
;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; A voice is to audio as a font is to a visual display.
;; A personality is to audio as a face is to a visual display.
;; 
;; Voice-lock-mode is a minor mode that causes your comments to be
;; spoken in one personality, strings in another, reserved words in another,
;; documentation strings in another, and so on.
;; 
;; Comments will be spoken in `voice-comment-personality'.
;; Strings will be spoken in `voice-string-personality'.
;; Function  (in their defining forms) will be
;;  spoken in `voice-function-name-personality'.
;; Reserved words will be spoken in `voice-keyword-personality'.
;; 
;; Legacy Voice Lock modes are provided by
;; `emacsvox-aural-compatibility-voice'.  This module retains ACSS, face
;; mapping, and local compatibility-provider machinery.
;; When this minor mode is on, the voices of the current line are
;; updated with every insertion or deletion.
;; 
;; @subsection Voice-Lock And Aural CSS
;; The CSS Speech Style Sheet specification defines a number of
;; abstract device independent voice properties.
;; A setting conforming to the CSS speech specification can be
;; represented in elisp as a structure.
;; 
;; We will refer to this structure as a "speech style".  This
;; structure needs to be mapped to device dependent codes to produce
;; the desired effect.  This module forms a bridge between emacs
;; packages    that wish to implement audio formatting
;; and Emacsvox's TTS module.  Emacsvox produces voice
;; change effects by examining the value of text-property
;; 'personality', as well as the face/font at point.
;; 
;; Think of a buffer of formatted text along with the text-property
;; 'personality appropriately set as a "aural display list".  Module
;; voice-setup.el help applications like EWW produce audio-formatted
;; output by calling function voice-from-acss with
;; a "speech-style" --a structure as defined in this module and get
;; back a symbol that they assign to the value of property
;; 'personality.  Emacsvox's rendering engine then does the needful
;; at the time speech is produced.  Function
;; voice-from-acss does the following: Takes as
;; input a "speech style" (1) Computes a symbol that will be used to
;; refer to this specific speech style.  (2) Examines emacsvox's
;; internal voice table to see if this speech style has a voice
;; already defined.  If so it returns immediately.  Otherwise, it
;; does the additional work of defining a -voice for future use.  See
;; its use in this module to see how voices are defined independent
;; of a given TTS engine.  How faces map to voices: TTS engine
;; specific modules e.g., dectalk-voices.el and outloud-voices.el map
;; ACSS dimensions to engine-specific codes.  Emacsvox modules use
;; voice-setup-add-map when defining face->personality mappings.  For
;; use from other modules.

;;; Code:

;;  Required modules: 

(eval-when-compile (require 'cl-lib))
(require 'tts-speak)
(eval-when-compile (require 'easy-mmode))

(declare-function omnivox-configure-tts "omnivox-voices" ())
(declare-function
 emacsvox-aural-routing-static-family
 "emacsvox-aural-routing-profiles" (logical-voice requested-family
                                    &optional capabilities inventory))

(declare-function
 emacsvox-aural-capture-source-faces
 "emacsvox-aural-source" (&optional position buffer))
(declare-function
 emacsvox-aural-source-text-property
 "emacsvox-aural-source" (position property &optional object))

(defvar emacsvox-aural-suppressed-personalities)

(defvar voice-setup-defined-voices nil
  "Logical personality variables declared through `defvoice'.")

;;;  customization group

(defgroup voice-fonts nil
  "Voices"
  :group 'emacsvox)

;;; Configure:

;; This configures Emacsvox for the TTS engine used at start.
;; Subsequent switches to other engines  causes that engine to get
;; configured --- see the various tts-engine startup  commands, e.g.,
;; outloud, dectalk, espeak.
;; Whenever we switch engines, we load voice-definitions for that
;; engine by reloading module voice-defs.
(cl-declaim (special tts-program))

(cl-defstruct (acss
               (:predicate nil) ;; Don't make a predicate we don't need.
               (:copier nil))   ;; Don't make a copier we don't need.
  family average-pitch pitch-range stress richness)

(defun voice-setup ()
  "Setup voices for selected TTS engine."
  (setq tts-voice-inventory-function #'tts-default-voice-inventory)
  (setq tts-voice-inventory-refresh-function
        #'tts-default-refresh-voice-inventory)
  (setq tts-engine-recovery-probe-function nil)
  (setq tts-voice-configuration-apply-function
        #'tts-default-apply-voice-configuration)
  (setq tts-last-realized-voice-function
        #'tts-default-last-realized-voice)
  (setq tts-voice-preview-function #'tts-default-voice-preview-sequence)
  (setq tts-voice-preview-code-function #'tts-default-voice-preview-code)
  (cond
   ((string-match "outloud" tts-program)
    (require 'outloud-voices)
    (outloud-configure-tts))
   ((string-match "dtk" tts-program)
    (require 'dectalk-voices)
    (dectalk-configure-tts))
   ((string-match "swiftmac" tts-program)
    (require 'swiftmac-voices)
    (swiftmac-configure-tts))
   ((string-match "mac\\'" tts-program)
    (require 'mac-voices)
    (mac-configure-tts))
   ((string-match "espeak\\'" tts-program)
    (require 'espeak-voices)
    (espeak-configure-tts))
   ((tts--omnivox-program-p)
    (require 'omnivox-voices)
    (omnivox-configure-tts))
   (t
    (require 'plain-voices)
    (plain-configure-tts)))
  (when (eq tts-voice-configuration-apply-function
            #'tts-default-apply-voice-configuration)
    (setq tts-voice-configuration-apply-function
          #'voice-setup-apply-voice-configuration))
  (ems--fastload "voice-defs"))

(defun voice-from-acss (style &optional logical-voice)
  "Compute a  name for this STYLE.
Define a voice for it if needed, then return the symbol.

When LOGICAL-VOICE is supplied, a standalone adapter may replace only the
physical family through the active routing profile.  Every other ACSS
dimension remains portable and unchanged."
  (let* ((requested-family (acss-family style))
         (f
          (if (and logical-voice
                   (fboundp 'emacsvox-aural-routing-static-family))
              (emacsvox-aural-routing-static-family
               logical-voice requested-family)
            requested-family))
        (a (acss-average-pitch style))
        (p (acss-pitch-range style))
        (s (acss-stress style))
        (r (acss-richness style))
        (effective-style
         (if (eq f requested-family)
             style
           (make-acss :family f :average-pitch a :pitch-range p
                      :stress s :richness r)))
        (name nil))
    (setq name
          (intern
           (format "acss%s%s%s%s%s"
                   (if f (format "-%s" f) "")
                   (if a (format "-a%s" a) "")
                   (if p (format "-p%s" p) "")
                   (if s (format "-s%s" s) "")
                   (if r (format "-r%s" r) ""))))
    (unless (tts-voice-defined-p name)
      (tts-define-voice-from-acss name effective-style))
    name))

(defun voice-setup-recompile-defined-voices ()
  "Recompile every `defvoice' personality against current static routing."
  (dolist (voice voice-setup-defined-voices)
    (let ((settings (intern-soft (format "%s-settings" voice))))
      (when (and settings (boundp settings))
        (set voice
             (voice-setup-acss-from-style (symbol-value settings) voice)))))
  (length voice-setup-defined-voices))

(defun voice-setup-apply-voice-configuration (&optional callback)
  "Apply routing locally by recompiling all declared personalities.
CALLBACK receives a synchronous terminal result."
  (let ((count (voice-setup-recompile-defined-voices))
        (adapter (plist-get (tts-voice-capabilities) :adapter)))
    (let ((result
           (list :status 'applied :adapter adapter
                 :completion-guarantee 'local :processes nil
                 :recompiled-personalities count :time (current-time))))
      (when (functionp callback) (funcall callback (copy-tree result)))
      result)))

;;;  map faces to voices

(defvar voice-setup-face-voice-table (make-hash-table :test #'eq)
  "Face to voice mapping.")

(defvar voice-setup-face-voice-provenance-table
  (make-hash-table :test #'eq)
  "Face mapping declaration history keyed by face.")

(defvar voice-setup--face-mapping-sequence 0
  "Monotonic sequence for face mapping declarations.")

(defconst voice-setup--missing-voice (make-symbol "missing-voice"))

(defvar-local voice-setup-local-map nil
  "Buffer-local face-to-personality overrides.

Entries shadow `voice-setup-face-voice-table' without mutating its global
compatibility mappings.")

(defun voice-setup--ensure-local-map ()
  "Return the current buffer's writable local face override table."
  (or
   voice-setup-local-map
   (setq voice-setup-local-map (make-hash-table :test #'eq))))

(defun voice-setup--ensure-local-personality-map ()
  "Return the current buffer's writable personality suppression table."
  (or
   emacsvox-aural-suppressed-personalities
   (setq emacsvox-aural-suppressed-personalities
         (make-hash-table :test #'equal))))

(defun voice-setup--face-mapping-origin (&optional origin)
  "Return a stable module symbol for mapping ORIGIN."
  (let ((origin
         (or
          origin
          load-file-name
          (and
           (boundp 'byte-compile-current-file)
           (symbol-value 'byte-compile-current-file))
          buffer-file-name
          'runtime)))
    (cond
     ((symbolp origin) origin)
     ((stringp origin)
      (intern (file-name-base (file-name-sans-extension origin))))
     (t
      (error "Face mapping origin must be a symbol or file name: %S"
             origin)))))

(defun voice-setup--record-face-mapping (face voice origin)
  "Record the declaration mapping FACE to VOICE from ORIGIN."
  (let ((history
         (gethash face voice-setup-face-voice-provenance-table)))
    (unless
        (cl-find-if
         (lambda (record)
           (and
            (equal (plist-get record :voice) voice)
            (eq (plist-get record :origin) origin)))
         history)
      (let ((record
             (list
              :face face
              :voice voice
              :origin origin
              :sequence (cl-incf voice-setup--face-mapping-sequence))))
        (puthash
         face
         (append history (list record))
         voice-setup-face-voice-provenance-table)))))

(defun voice-setup-set-voice-for-face (face voice &optional origin)
  "Map FACE to VOICE and record its declaration ORIGIN.

ORIGIN may be a module symbol or file name.  It defaults to the currently
loaded source file and falls back to `runtime'.  Existing callers retain
last-registration-wins behavior."
  (voice-setup--record-face-mapping
   face voice (voice-setup--face-mapping-origin origin))
  (setf (gethash face voice-setup-face-voice-table) voice))

(defsubst voice-setup-get-voice-for-face (face)
  "Return face to  voice."

  (let ((local
         (if voice-setup-local-map
             (gethash
              face voice-setup-local-map voice-setup--missing-voice)
           voice-setup--missing-voice)))
    (if (eq local voice-setup--missing-voice)
        (gethash face voice-setup-face-voice-table)
      local)))

(defun voice-setup-add-map (fv-alist &optional origin)
  "Set face-to-voice mappings from FV-ALIST with declaration ORIGIN."
  (let ((origin (voice-setup--face-mapping-origin origin)))
    (cl-loop
     for fv in fv-alist
     do
     (voice-setup-set-voice-for-face
      (cl-first fv) (cl-second fv) origin))))

(defun voice-setup-face-mapping-provenance (face)
  "Return data-only declaration history for FACE."
  (copy-tree
   (gethash face voice-setup-face-voice-provenance-table)))

(defun voice-setup-face-mapping-diagnostic (face)
  "Return the effective mapping and declaration provenance for FACE."
  (let* ((declarations
          (voice-setup-face-mapping-provenance face))
         (voices
          (delete-dups
           (mapcar
            (lambda (record) (plist-get record :voice))
            declarations))))
    (list
     :face face
     :effective (gethash face voice-setup-face-voice-table)
     :conflict (> (length voices) 1)
     :declarations declarations)))

(defun voice-setup-face-mapping-conflicts ()
  "Return deterministic diagnostics for loaded conflicting face mappings."
  (let (conflicts)
    (maphash
     (lambda (face _)
       (let ((diagnostic
              (voice-setup-face-mapping-diagnostic face)))
         (when (plist-get diagnostic :conflict)
           (push diagnostic conflicts))))
     voice-setup-face-voice-provenance-table)
    (sort
     conflicts
     (lambda (left right)
       (string-lessp
        (symbol-name (plist-get left :face))
        (symbol-name (plist-get right :face)))))))

;;;   special form defvoice

(defun voice-setup-acss-from-style (style-list &optional logical-voice)
  "Define an ACSS-voice  from   speech style."
  (let ((voice
         (voice-from-acss
          (make-acss
           :family (nth 0 style-list)
           :average-pitch (nth 1 style-list)
           :pitch-range (nth 2 style-list)
           :stress (nth 3 style-list)
           :richness (nth 4  style-list))
          logical-voice)))
    voice))

(defmacro defvoice (voice settings)
  "Define voice using ACSS setting.  Setting is a list ---
(list paul 5 5 5 5) for  the standard male voice.  It can
 be customized by  \\[customize-variable] on
 <voice>-settings. "
  (declare (indent 1) (debug t))
  `(progn
     (cl-pushnew ',voice voice-setup-defined-voices)
     (defvar  ,voice
       (voice-setup-acss-from-style ,settings ',voice)
       ,(format "Customize  via %s-settings." voice))
     (defcustom ,(intern (format "%s-settings"  voice))
       ,settings
       ,(format "Settings for %s" voice)
       :type
       '(list
         (const :tag "Unspecified" nil)
         (choice :tag "Average Pitch"
                 (const :tag "Unspecified" nil)
                 (integer :tag "Number"))
         (choice :tag "Pitch Range"
                 (const :tag "Unspecified" nil)
                 (integer :tag "Number"))
         (choice :tag "Stress"
                 (const :tag "Unspecified" nil)
                 (integer :tag "Number"))
         (choice :tag "Richness"
                 (const :tag "Unspecified" nil)
                 (integer :tag "Number")))
       :group 'voice-fonts
       :set
       #'(lambda  (sym val)
           (setq ,voice (voice-setup-acss-from-style val ',voice))
           (set-default sym val)))))

(require 'emacsvox-aural-compatibility-voice)

(declare-function emacsvox-icon "emacsvox-sounds" (icon))

;;;  interactively silence personalities

(defun voice-setup--mapped-face-at-point ()
  "Return the strongest mapped source face at point."
  (cl-loop
   for record in (emacsvox-aural-capture-source-faces)
   for face = (plist-get record :face)
   when (voice-setup-get-voice-for-face face)
   return face))

(defun voice-setup--report-local-suppression (silenced kind value)
  "Report that VALUE of KIND was SILENCED or restored."
  (if silenced
      (progn
        (message "Silenced %s %s in this buffer" kind value)
        (emacsvox-icon 'close-object))
    (message "Made %s %s audible in this buffer." kind value)
    (emacsvox-icon 'item)))

(defun voice-setup-toggle-silence-personality ()
  "Toggle local audibility of the personality or mapped face at point."
  (interactive)

  (let* ((personality
          (emacsvox-aural-source-text-property
           (point) 'personality))
         (face (unless personality (voice-setup--mapped-face-at-point))))
    (cond
     (personality
      (cond
       ((and
         emacsvox-aural-suppressed-personalities
         (gethash personality emacsvox-aural-suppressed-personalities))
        (remhash personality emacsvox-aural-suppressed-personalities)
        (voice-setup--report-local-suppression
         nil "personality" personality))
       ((emacsvox-aural-voice-inaudible-p personality)
        (message "Personality %s is already inaudible." personality))
       (t
        (puthash
         personality t (voice-setup--ensure-local-personality-map))
        (voice-setup--report-local-suppression
         t "personality" personality))))
     (face
      (if
          (and
           voice-setup-local-map
           (not
            (eq
             (gethash
              face voice-setup-local-map voice-setup--missing-voice)
             voice-setup--missing-voice)))
          (progn
            (remhash face voice-setup-local-map)
            (voice-setup--report-local-suppression nil "face" face))
        (let ((mapped (gethash face voice-setup-face-voice-table)))
          (if (emacsvox-aural-voice-inaudible-p mapped)
              (message "Face %s is already inaudible." face)
            (puthash face 'inaudible (voice-setup--ensure-local-map))
            (voice-setup--report-local-suppression t "face" face)))))
     (t (message "No personality or mapped face here.")))))

(provide 'voice-setup)
;;;  end of file
