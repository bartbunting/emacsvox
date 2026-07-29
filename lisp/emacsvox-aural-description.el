;;; emacsvox-aural-description.el --- Natural aural descriptions -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Pure, reusable descriptions of aural values, selectors, rules, and
;; concrete actions for spoken managers, editors, and explanation buffers.

;;; Code:

(require 'subr-x)
(require 'emacsvox-aural-transport)

(defun emacsvox-aural-humanize (value)
  "Return VALUE in a form suitable for visual and spoken help."
  (cond
   ((symbolp value)
    (replace-regexp-in-string "-" " " (symbol-name value)))
   ((stringp value) value)
   (t (format "%s" value))))

(defun emacsvox-aural-describe-selector (selector)
  "Return a concise natural description of compiled SELECTOR."
  (let (parts)
    (when-let* ((role (emacsvox-aural-selector-role selector)))
      (push
       (format "role %s" (emacsvox-aural-humanize role))
       parts))
    (dolist (event (emacsvox-aural-selector-events selector))
      (push
       (format "event %s" (emacsvox-aural-humanize event))
       parts))
    (dolist (state (emacsvox-aural-selector-states selector))
      (push
       (format "state %s" (emacsvox-aural-humanize state))
       parts))
    (dolist (attribute (emacsvox-aural-selector-attributes selector))
      (push
       (format
        "%s %s"
        (emacsvox-aural-humanize (car attribute))
        (emacsvox-aural-humanize (cdr attribute)))
       parts))
    (dolist
        (attribute
         (emacsvox-aural-selector-required-attributes selector))
      (push
       (format
        "%s present"
        (emacsvox-aural-humanize attribute))
       parts))
    (when-let* ((module (emacsvox-aural-selector-module selector)))
      (push
       (format "module %s" (emacsvox-aural-humanize module))
       parts))
    (when-let* ((mode (emacsvox-aural-selector-mode selector)))
      (push
       (format "mode %s" (emacsvox-aural-humanize mode))
       parts))
    (when-let* ((occasion (emacsvox-aural-selector-occasion selector)))
      (push
       (format
        "occasion %s"
        (emacsvox-aural-humanize occasion))
       parts))
    (when-let* ((cue (emacsvox-aural-selector-legacy-cue selector)))
      (push
       (format "legacy cue %s" (emacsvox-aural-humanize cue))
       parts))
    (when-let* ((face (emacsvox-aural-selector-legacy-face selector)))
      (push
       (format "visual face %s" (emacsvox-aural-humanize face))
       parts))
    (when (emacsvox-aural-selector-legacy-personality selector)
      (push "legacy voice property" parts))
    (if parts
        (string-join (nreverse parts) ", ")
      "all content")))

(defun emacsvox-aural-print-rules (rules)
  "Print natural descriptions of compiled presentation RULES."
  (if (null rules)
      (princ "None.\n")
    (dolist (rule rules)
      (princ
       (format
        "%s%s - applies to %s\n"
        (emacsvox-aural-rule-id rule)
        (if (emacsvox-aural-rule-enabled rule) "" " (disabled)")
        (emacsvox-aural-describe-selector
         (emacsvox-aural-rule-selector rule)))))))

(defun emacsvox-aural-describe-concrete-action (action)
  "Return a concise description of concrete ACTION."
  (let* ((balance (emacsvox-aural-concrete-action-balance action))
         (anchor
          (or (emacsvox-aural-concrete-action-anchor action) 'undivided))
         (spatial
          (if (numberp balance)
              (format
               ", balance %.3f (%s)"
               balance
               (emacsvox-aural-concrete-action-spatial-capability action))
            ""))
         (volume
          (when-let* ((requested
                       (emacsvox-aural-concrete-action-requested-volume
                        action)))
            (format
             ", volume %S (%s)"
             requested
             (emacsvox-aural-concrete-action-volume-capability action)))))
    (concat
     (pcase (emacsvox-aural-concrete-action-kind action)
       ('cue
        (format
         "%s: cue %s -> %s"
         (emacsvox-aural-concrete-action-id action)
         (emacsvox-aural-concrete-action-cue action)
         (emacsvox-aural-concrete-action-resource action)))
       ('speech
        (format
         "%s: speak %S%s"
         (emacsvox-aural-concrete-action-id action)
         (emacsvox-aural-concrete-action-text action)
         (if-let* ((voice
                    (emacsvox-aural-concrete-action-voice-command action)))
             (format " using %S" voice)
           "")))
       ('pause
        (format
         "%s: pause %s"
         (emacsvox-aural-concrete-action-id action)
         (emacsvox-aural-concrete-action-duration action))))
     spatial
     volume
     (format ", %s anchored" anchor))))

(provide 'emacsvox-aural-description)
;;; emacsvox-aural-description.el ends here
