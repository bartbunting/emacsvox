;;; emacsvox-aural-simple-editor.el --- Simple spoken aural scheme editor -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Present personal aural schemes as natural-language fields.  The existing
;; rule editor remains available for selectors and render operations that need
;; full declarative control.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'emacsvox-aural-editor)

(declare-function emacsvox-speak-help "emacsvox-speak" ())
(declare-function emacsvox-speak-line "emacsvox-speak" ())
(declare-function tts-speak "tts-speak" (text))

(defconst emacsvox-aural-simple-editor--field-property
  'emacsvox-aural-simple-editor-field
  "Text property identifying one editable simple-editor field.")

(defun emacsvox-aural-simple-editor--humanize (value)
  "Return VALUE as natural words."
  (emacsvox-aural-tools--humanize value))

(defun emacsvox-aural-simple-editor--plist-delete (plist property)
  "Return a copy of PLIST without PROPERTY."
  (let (result)
    (while plist
      (unless (eq (car plist) property)
        (setq result (append result (list (car plist) (cadr plist)))))
      (setq plist (cddr plist)))
    result))

(defun emacsvox-aural-simple-editor--field-at-point ()
  "Return the simple field at point, or nil."
  (or
   (get-text-property
    (or (emacsvox-aural-inspection-point-position) (point-min))
    emacsvox-aural-simple-editor--field-property)
   (and
    (> (point) (point-min))
    (get-text-property
     (1- (point))
     emacsvox-aural-simple-editor--field-property))))

(defun emacsvox-aural-simple-editor--field-positions ()
  "Return buffer positions that begin editable simple fields."
  (let ((position (point-min))
        (limit (point-max))
        positions)
    (while (< position limit)
      (let ((field
             (get-text-property
              position emacsvox-aural-simple-editor--field-property))
            (next
             (next-single-property-change
              position emacsvox-aural-simple-editor--field-property
              nil limit)))
        (when field (push position positions))
        (setq position next)))
    (nreverse positions)))

(defun emacsvox-aural-simple-editor--goto-field (field)
  "Move to the first displayed field equal to FIELD."
  (let ((position (point-min))
        (limit (point-max))
        found)
    (while (and (< position limit) (not found))
      (if
          (equal
           field
           (get-text-property
            position emacsvox-aural-simple-editor--field-property))
          (setq found position)
        (setq
         position
         (next-single-property-change
          position emacsvox-aural-simple-editor--field-property
          nil limit))))
    (when found (goto-char found))
    found))

(defun emacsvox-aural-simple-editor--speak-current-field ()
  "Speak the current simple-editor field."
  (cond
   ((fboundp 'emacsvox-speak-line)
    (emacsvox-speak-line))
   ((fboundp 'tts-speak)
    (tts-speak
     (buffer-substring
      (line-beginning-position) (line-end-position))))))

(defun emacsvox-aural-simple-editor-next-field (&optional previous)
  "Move to the next editable field and speak it.

With PREVIOUS non-nil, move backward.  Movement wraps at either end."
  (interactive)
  (let* ((positions (emacsvox-aural-simple-editor--field-positions))
         (current (point))
         (destination
          (if previous
              (or
               (car (last (cl-remove-if-not
                           (lambda (position) (< position current))
                           positions)))
               (car (last positions)))
            (or
             (cl-find-if
              (lambda (position) (> position current))
              positions)
             (car positions)))))
    (unless destination
      (user-error "This editor has no editable fields"))
    (goto-char destination)
    (emacsvox-aural-simple-editor--speak-current-field)))

(defun emacsvox-aural-simple-editor-previous-field ()
  "Move to the previous editable field and speak it."
  (interactive)
  (emacsvox-aural-simple-editor-next-field t))

(defun emacsvox-aural-simple-editor--insert-field
    (label value field &optional rule-index)
  "Insert an editable FIELD showing LABEL and VALUE.

RULE-INDEX associates the line with a working declarative rule."
  (let ((start (point)))
    (insert (format "  %-18s %s\n" label value))
    (add-text-properties
     start (point)
     (append
      (list
       emacsvox-aural-simple-editor--field-property field
       'face 'link
       'mouse-face 'highlight
       'help-echo "Press RET to edit this field")
      (when (numberp rule-index)
        (list emacsvox-aural-editor--rule-index-property rule-index))))))

(defun emacsvox-aural-simple-editor--semantic-candidates (kind)
  "Return completion candidates for semantic KIND."
  (cl-loop
   for record in (emacsvox-aural-semantics)
   when (eq (emacsvox-aural-semantic-kind record) kind)
   collect (symbol-name (emacsvox-aural-semantic-id record))))

(defun emacsvox-aural-simple-editor--module-candidates ()
  "Return known module identifiers as completion candidates."
  (let (modules)
    (maphash
     (lambda (_ fragment)
       (push
        (symbol-name
         (emacsvox-aural-module-fragment-module fragment))
        modules))
     emacsvox-aural-module-fragment-registry)
    (dolist (record (emacsvox-aural-semantics))
      (let ((owner (emacsvox-aural-semantic-owner record)))
        (unless (eq owner 'core)
          (push (symbol-name owner) modules))))
    (sort (delete-dups modules) #'string-lessp)))

(defun emacsvox-aural-simple-editor--voice-palette-candidates ()
  "Return registered voice palette identifiers."
  (let (values)
    (maphash
     (lambda (id _) (push (symbol-name id) values))
     emacsvox-aural-voice-palette-registry)
    (sort values #'string-lessp)))

(defun emacsvox-aural-simple-editor--symbol-list-description (values)
  "Describe symbol VALUES, using `any' when empty."
  (if values
      (mapconcat
       #'emacsvox-aural-simple-editor--humanize values ", ")
    "any"))

(defun emacsvox-aural-simple-editor--attribute-description (match)
  "Describe registered attribute conditions in MATCH."
  (let (parts)
    (dolist (record (emacsvox-aural-semantics))
      (when (eq (emacsvox-aural-semantic-kind record) 'attribute)
        (let* ((id (emacsvox-aural-semantic-id record))
               (key (intern (format ":%s" id))))
          (when (plist-member match key)
            (push
             (format
              "%s %s"
              (emacsvox-aural-simple-editor--humanize id)
              (emacsvox-aural-simple-editor--humanize
               (plist-get match key)))
             parts)))))
    (dolist (id (plist-get match :requires))
      (push
       (format
        "%s present"
        (emacsvox-aural-simple-editor--humanize id))
       parts))
    (if parts (string-join (nreverse parts) ", ") "any")))

(defun emacsvox-aural-simple-editor--match-description (match)
  "Return a natural description of declarative MATCH."
  (let (parts)
    (when-let* ((role (plist-get match :role)))
      (push
       (format
        "object %s"
        (emacsvox-aural-simple-editor--humanize role))
       parts))
    (when-let* ((face (plist-get match :legacy-face)))
      (push
       (format
        "visual face %s"
        (emacsvox-aural-simple-editor--humanize face))
       parts))
    (unless (or (plist-get match :role) (plist-get match :legacy-face))
      (push "object any" parts))
    (when-let* ((states
                 (append
                  (when-let* ((state (plist-get match :state)))
                    (list state))
                  (plist-get match :states))))
      (push
       (format
        "state %s"
        (emacsvox-aural-simple-editor--symbol-list-description states))
       parts))
    (when-let* ((events
                 (append
                  (when-let* ((event (plist-get match :event)))
                    (list event))
                  (plist-get match :events))))
      (push
       (format
        "event %s"
        (emacsvox-aural-simple-editor--symbol-list-description events))
       parts))
    (let ((attributes
           (emacsvox-aural-simple-editor--attribute-description match)))
      (unless (string= attributes "any")
        (push attributes parts)))
    (when-let* ((module (plist-get match :module)))
      (push
       (format
        "module %s"
        (emacsvox-aural-simple-editor--humanize module))
       parts))
    (when-let* ((mode (plist-get match :mode)))
      (push
       (format
        "mode %s"
        (emacsvox-aural-simple-editor--humanize mode))
       parts))
    (when-let* ((occasion (plist-get match :occasion)))
      (push
       (format
        "during %s"
        (emacsvox-aural-simple-editor--humanize occasion))
       parts))
    (when-let* ((cue (plist-get match :legacy-cue)))
      (push
       (format
        "legacy cue %s"
        (emacsvox-aural-simple-editor--humanize cue))
       parts))
    (when-let* ((voice (plist-get match :legacy-personality)))
      (push (format "legacy voice %s" voice) parts))
    (string-join (nreverse parts) "; ")))

(defun emacsvox-aural-simple-editor--space-description (space)
  "Describe portable SPACE."
  (cond
   ((null space) "center or inherited")
   ((plist-member space :balance)
    (let ((balance (plist-get space :balance)))
      (cond
       ((< balance -0.1) "left")
       ((> balance 0.1) "right")
       (t "center"))))
   ((plist-member space :azimuth)
    (format "azimuth %s degrees" (plist-get space :azimuth)))
   (t "advanced position")))

(defun emacsvox-aural-simple-editor--action-description (action)
  "Describe declarative ACTION naturally."
  (let ((placement
         (when-let* ((space (plist-get action :space)))
           (format
            " on the %s"
            (emacsvox-aural-simple-editor--space-description space))))
        (lifetime
         (pcase (plist-get action :anchor)
           ('object " once per object")
           ('run " for each formatting run")
           ('transition " when entering or leaving the presentation")
           (_ ""))))
    (concat
     (pcase (plist-get action :kind)
       ('speech
        (if-let* ((template (plist-get action :text-template)))
            (format "say template %S" template)
          (format "say %S" (plist-get action :text))))
       ('cue
        (format
         "play the %s cue"
         (emacsvox-aural-simple-editor--humanize
          (plist-get action :cue))))
       ('pause
        (format "pause %s milliseconds" (plist-get action :duration)))
       (_ "advanced action"))
     placement
     lifetime)))

(defun emacsvox-aural-simple-editor--action-list-description (actions)
  "Describe ordered ACTIONS."
  (if actions
      (mapconcat
       #'emacsvox-aural-simple-editor--action-description
       actions
       ", then ")
    "nothing"))

(defun emacsvox-aural-simple-editor--phase-description (phase)
  "Describe declarative PHASE in user-facing terms."
  (cond
   ((null phase) "inherit existing feedback")
   ((and (listp phase) (listp (car phase)))
    (emacsvox-aural-simple-editor--action-list-description phase))
   (t
    (string-join
     (delq
      nil
      (list
       (when (plist-get phase :suppress)
         "suppress all inherited feedback")
       (when (plist-member phase :replace)
         (format
          "replace with %s"
          (emacsvox-aural-simple-editor--action-list-description
           (plist-get phase :replace))))
       (when-let* ((actions (plist-get phase :prepend)))
         (format
          "first %s"
          (emacsvox-aural-simple-editor--action-list-description actions)))
       (when-let* ((actions (plist-get phase :append)))
         (format
          "then %s"
          (emacsvox-aural-simple-editor--action-list-description actions)))
       (when-let* ((ids (plist-get phase :remove)))
         (format "remove inherited actions %s" ids))
       (pcase (plist-get phase :anchor)
         ('object "operate once per object")
         ('run "operate on each formatting run")
         ('transition "operate on presentation transitions")
         (_ nil))))
     "; "))))

(defun emacsvox-aural-simple-editor--content-description (content)
  "Describe declarative CONTENT styling naturally."
  (if (null content)
      "speak using the existing voice and position"
    (let (parts)
      (push
       (cond
        ((plist-get content :suppress) "suppress the content")
        ((and
          (plist-member content :speak)
          (not (plist-get content :speak)))
         "do not speak the content")
        (t "speak the content"))
       parts)
      (when (plist-member content :voice)
        (push
         (if-let* ((voice (plist-get content :voice)))
             (format
              "use the %s voice"
              (emacsvox-aural-simple-editor--humanize voice))
           "use the default voice")
         parts))
      (when-let* ((space (plist-get content :space)))
        (push
         (format
          "place it %s"
          (emacsvox-aural-simple-editor--space-description space))
         parts))
      (when (plist-member content :volume)
        (push (format "advanced volume %s" (plist-get content :volume)) parts))
      (string-join (nreverse parts) "; "))))

(defun emacsvox-aural-simple-editor--advanced-action-p (action)
  "Return non-nil when ACTION needs advanced editing."
  (or
   (eq (plist-get action :kind) 'pause)
   (plist-member action :text-template)
   (plist-member action :voice)
   (plist-member action :volume)))

(defun emacsvox-aural-simple-editor--advanced-phase-p (phase)
  "Return non-nil when PHASE contains advanced operations or actions."
  (or
   (and
    phase
    (not (and (listp phase) (listp (car phase))))
    (or
     (plist-member phase :remove)
     (plist-member phase :prepend)
     (plist-member phase :append)))
   (cl-some
    #'emacsvox-aural-simple-editor--advanced-action-p
    (cond
     ((and (listp phase) (listp (car phase))) phase)
     ((plist-member phase :replace) (plist-get phase :replace))
     (t
      (append
       (plist-get phase :prepend)
       (plist-get phase :append)))))))

(defun emacsvox-aural-simple-editor--advanced-reasons (rule)
  "Return natural reasons why RULE may need the advanced editor."
  (let* ((match (plist-get rule :match))
         (render (plist-get rule :render))
         (content (plist-get render :content))
         reasons)
    (when
        (or
         (plist-member match :legacy-cue)
         (plist-member match :legacy-personality))
      (push "legacy matching" reasons))
    (when
        (emacsvox-aural-simple-editor--advanced-phase-p
         (plist-get render :before))
      (push "advanced before-content operations" reasons))
    (when
        (emacsvox-aural-simple-editor--advanced-phase-p
         (plist-get render :after))
      (push "advanced after-content operations" reasons))
    (when
        (or
         (plist-member content :volume)
         (plist-get content :suppress))
      (push "advanced content styling" reasons))
    (nreverse reasons)))

(defun emacsvox-aural-simple-editor-refresh ()
  "Render the current personal scheme as natural-language fields."
  (interactive)
  (let ((inhibit-read-only t)
        (field (emacsvox-aural-simple-editor--field-at-point)))
    (erase-buffer)
    (insert
     (format
      "Simple Aural Scheme Editor: %s%s\n\n"
      emacsvox-aural-editor-target
      (if (eq emacsvox-aural-editor-target
              emacsvox-aural-active-scheme)
          " (active)"
        "")))
    (insert
     "TAB and Shift-TAB move through fields.  RET edits one field.\n"
     "Keys: n new presentation, p preview, s save, a activate,\n"
     "A advanced editor, d delete rule, t enable rule, ? help, q quit.\n\n")
    (insert "Scheme\n")
    (emacsvox-aural-simple-editor--insert-field
     "Summary:"
     (or (plist-get emacsvox-aural-editor-scheme-data :summary) "")
     '(:kind summary))
    (emacsvox-aural-simple-editor--insert-field
     "Based on:"
     (format
      "%s"
      (or (plist-get emacsvox-aural-editor-scheme-data :parent)
          "no parent"))
     '(:kind parent))
    (emacsvox-aural-simple-editor--insert-field
     "Sound pack:"
     (format
      "%s"
      (or (plist-get emacsvox-aural-editor-scheme-data :resource-pack)
          "inherited"))
     '(:kind resource-pack))
    (emacsvox-aural-simple-editor--insert-field
     "Voice palette:"
     (format
      "%s"
      (or (plist-get emacsvox-aural-editor-scheme-data :voice-palette)
          "inherited"))
     '(:kind voice-palette))
    (insert "\nPresentations\n\n")
    (if emacsvox-aural-editor-rules
        (cl-loop
         for rule in emacsvox-aural-editor-rules
         for index from 0
         for render = (plist-get rule :render)
         do
         (insert
          (format
           "Presentation %d: %s\n"
           (1+ index)
           (emacsvox-aural-simple-editor--humanize
            (plist-get rule :id))))
         (emacsvox-aural-simple-editor--insert-field
          "Status:"
          (if (emacsvox-aural-editor--rule-enabled-p rule)
              "enabled"
            "disabled")
          (list :kind 'enabled :rule index)
          index)
         (emacsvox-aural-simple-editor--insert-field
          "Applies to:"
          (emacsvox-aural-simple-editor--match-description
           (plist-get rule :match))
          (list :kind 'match :rule index)
          index)
         (emacsvox-aural-simple-editor--insert-field
          "Before content:"
          (emacsvox-aural-simple-editor--phase-description
           (plist-get render :before))
          (list :kind 'before :rule index)
          index)
         (emacsvox-aural-simple-editor--insert-field
          "Content:"
          (emacsvox-aural-simple-editor--content-description
           (plist-get render :content))
          (list :kind 'content :rule index)
          index)
         (emacsvox-aural-simple-editor--insert-field
          "After content:"
          (emacsvox-aural-simple-editor--phase-description
           (plist-get render :after))
          (list :kind 'after :rule index)
          index)
         (when-let* ((reasons
                      (emacsvox-aural-simple-editor--advanced-reasons
                       rule)))
           (emacsvox-aural-simple-editor--insert-field
            "Advanced details:"
            (format
             "%s; press RET or A for the advanced editor"
             (string-join reasons ", "))
            (list :kind 'advanced :rule index)
            index))
         (insert "\n"))
      (insert
       "No presentations are defined here.  Press n to create one.\n"))
    (goto-char (point-min))
    (unless
        (and field (emacsvox-aural-simple-editor--goto-field field))
      (when-let* ((first
                   (car
                    (emacsvox-aural-simple-editor--field-positions))))
        (goto-char first)))))

(defun emacsvox-aural-simple-editor--mark-and-refresh (&optional field)
  "Mark working data dirty, refresh, and return to FIELD."
  (emacsvox-aural-editor--mark-dirty)
  (emacsvox-aural-simple-editor-refresh)
  (when field
    (emacsvox-aural-simple-editor--goto-field field))
  (emacsvox-aural-simple-editor--speak-current-field))

(defun emacsvox-aural-simple-editor--read-symbol-list-change
    (label kind values)
  "Apply one natural edit to semantic VALUES of KIND named LABEL."
  (let* ((action
          (intern
           (completing-read
            (format "%s condition: " label)
            '("add" "remove" "clear" "keep")
            nil 'must-match nil nil
            (if values "keep" "add"))))
         (candidates
          (emacsvox-aural-simple-editor--semantic-candidates kind)))
    (pcase action
      ('add
       (let ((value
              (intern
               (completing-read
                (format "Add %s: " (downcase label))
                (cl-set-difference candidates
                                   (mapcar #'symbol-name values)
                                   :test #'equal)
                nil 'must-match))))
         (delete-dups (append values (list value)))))
      ('remove
       (unless values
         (user-error "There are no %s conditions to remove" (downcase label)))
       (let ((value
              (intern
               (completing-read
                (format "Remove %s: " (downcase label))
                (mapcar #'symbol-name values)
                nil 'must-match))))
         (delq value (copy-sequence values))))
      ('clear nil)
      ('keep (copy-sequence values)))))

(defun emacsvox-aural-simple-editor--edit-attribute (match)
  "Return MATCH after editing one registered semantic attribute."
  (let* ((candidates
          (emacsvox-aural-simple-editor--semantic-candidates 'attribute))
         (choice
          (completing-read
           "Detail to edit: "
           (append '("(clear all details)") candidates)
           nil 'must-match)))
    (if (string= choice "(clear all details)")
        (progn
          (dolist (candidate candidates)
            (setq
             match
             (emacsvox-aural-simple-editor--plist-delete
              match (intern (format ":%s" candidate)))))
          (setq
           match
           (emacsvox-aural-simple-editor--plist-delete
            match :requires))
          match)
      (let* ((id (intern choice))
             (key (intern (format ":%s" id)))
             (record (emacsvox-aural-semantic id))
             (action
              (completing-read
               (format "%s detail: " choice)
               '("set value" "require presence" "remove" "keep")
               nil 'must-match nil nil "set value")))
        (pcase action
          ("set value"
           (setq
            match
            (plist-put
             match key
             (emacsvox-aural-editor--read-attribute-value
              record (plist-get match key))))
           (let ((required
                  (delq id (copy-sequence (plist-get match :requires)))))
             (setq
              match
              (emacsvox-aural-simple-editor--plist-delete
               match :requires))
             (when required
               (setq match (plist-put match :requires required))))
           match)
          ("require presence"
           (setq
            match
            (emacsvox-aural-simple-editor--plist-delete match key))
           (plist-put
            match :requires
            (delete-dups
             (append (plist-get match :requires) (list id)))))
          ("remove"
           (setq
            match
            (emacsvox-aural-simple-editor--plist-delete match key))
           (let ((required
                  (delq id (copy-sequence (plist-get match :requires)))))
             (setq
              match
              (emacsvox-aural-simple-editor--plist-delete
               match :requires))
             (when required
               (setq match (plist-put match :requires required))))
           match)
          (_ match))))))

(defun emacsvox-aural-simple-editor--edit-match (match)
  "Return declarative MATCH after editing one understandable condition."
  (let* ((match (copy-tree match))
         (choice
          (intern
           (completing-read
            "Change which condition? "
            '("object" "states" "events" "details" "module"
              "major-mode" "occasion" "visual-face" "advanced")
            nil 'must-match))))
    (pcase choice
      ('object
       (let ((role
              (emacsvox-aural-editor--read-symbol-or-nil
               "Object (none means any): "
               (plist-get match :role)
               (emacsvox-aural-simple-editor--semantic-candidates 'role)
               'must-match)))
         (setq match
               (emacsvox-aural-simple-editor--plist-delete match :role))
         (when role (setq match (plist-put match :role role)))))
      ('states
       (let ((values
              (append
               (when-let* ((state (plist-get match :state))) (list state))
               (plist-get match :states))))
         (setq match
               (emacsvox-aural-simple-editor--plist-delete match :state))
         (setq match
               (emacsvox-aural-simple-editor--plist-delete match :states))
         (when-let* ((updated
                      (emacsvox-aural-simple-editor--read-symbol-list-change
                       "State" 'state values)))
           (setq match (plist-put match :states updated)))))
      ('events
       (let ((values
              (append
               (when-let* ((event (plist-get match :event))) (list event))
               (plist-get match :events))))
         (setq match
               (emacsvox-aural-simple-editor--plist-delete match :event))
         (setq match
               (emacsvox-aural-simple-editor--plist-delete match :events))
         (when-let* ((updated
                      (emacsvox-aural-simple-editor--read-symbol-list-change
                       "Event" 'event values)))
           (setq match (plist-put match :events updated)))))
      ('details
       (setq match
             (emacsvox-aural-simple-editor--edit-attribute match)))
      ('module
       (let ((module
              (emacsvox-aural-editor--read-symbol-or-nil
               "Module (none means any): "
               (plist-get match :module)
               (emacsvox-aural-simple-editor--module-candidates))))
         (setq match
               (emacsvox-aural-simple-editor--plist-delete match :module))
         (when module (setq match (plist-put match :module module)))))
      ('major-mode
       (let ((mode
              (emacsvox-aural-editor--read-symbol-or-nil
               "Major mode (none means any): "
               (plist-get match :mode)
               (emacsvox-aural-editor--mode-candidates))))
         (setq match
               (emacsvox-aural-simple-editor--plist-delete match :mode))
         (when mode (setq match (plist-put match :mode mode)))))
      ('occasion
       (let ((occasion
              (emacsvox-aural-editor--read-symbol-or-nil
               "Occasion (none means any): "
               (plist-get match :occasion)
               (emacsvox-aural-occasion-candidates)
               'must-match)))
         (setq match
               (emacsvox-aural-simple-editor--plist-delete match :occasion))
         (when occasion
           (setq match (plist-put match :occasion occasion)))))
      ('visual-face
       (let ((face
              (emacsvox-aural-editor--read-symbol-or-nil
               "Visual face (none means any): "
               (plist-get match :legacy-face)
               (emacsvox-aural-editor--face-candidates))))
         (setq
          match
          (emacsvox-aural-simple-editor--plist-delete
           match :legacy-face))
         (when face
           (setq match (plist-put match :legacy-face face)))))
      ('advanced
       (user-error "Press A to use the advanced rule editor")))
    match))

(defun emacsvox-aural-simple-editor--read-space (old label)
  "Read simple spatial placement for LABEL, preserving OLD when requested."
  (let ((choice
         (completing-read
          (format "%s position: " label)
          '("keep current" "inherit" "center" "left" "right" "custom")
          nil 'must-match nil nil "keep current")))
    (pcase choice
      ("keep current" (copy-tree old))
      ("inherit" nil)
      ("center" '(:balance 0.0))
      ("left" '(:balance -0.65))
      ("right" '(:balance 0.65))
      ("custom"
       (let ((balance
              (read-number
               "Stereo position (-1 fully left, +1 fully right): "
               (or (plist-get old :balance) 0.0))))
         (unless (<= -1.0 balance 1.0)
           (user-error "Position must be between -1 and +1"))
         (list :balance (float balance))))
      (_ (copy-tree old)))))

(defun emacsvox-aural-simple-editor--make-speech-action
    (rule-id phase)
  "Read and return a speech action for RULE-ID and PHASE."
  (list
   :id (intern (format "%s-%s-label" rule-id phase))
   :kind 'speech
   :text (read-string "Words to say: ")))

(defun emacsvox-aural-simple-editor--make-cue-action (rule-id phase)
  "Read and return a cue action for RULE-ID and PHASE."
  (list
   :id (intern (format "%s-%s-cue" rule-id phase))
   :kind 'cue
   :cue
   (intern
    (completing-read
     "Sound cue: "
     (emacsvox-aural-editor--cue-candidates)
     nil 'must-match))))

(defun emacsvox-aural-simple-editor--edit-phase
    (rule-id phase old &optional append-p)
  "Return simple feedback for RULE-ID and PHASE based on OLD.

When APPEND-P is non-nil, newly chosen actions add to inherited feedback
instead of replacing it."
  (let* ((choice
          (completing-read
           (format "%s content feedback: "
                   (if (eq phase 'before) "Before" "After"))
           '("keep current" "inherit existing feedback"
             "no feedback, including inherited"
             "say a label" "play a cue"
             "say a label then play a cue"
             "play a cue then say a label")
           nil 'must-match nil nil "keep current"))
         actions)
    (pcase choice
      ("say a label"
       (setq actions
             (list
              (emacsvox-aural-simple-editor--make-speech-action
               rule-id phase))))
      ("play a cue"
       (setq actions
             (list
              (emacsvox-aural-simple-editor--make-cue-action
               rule-id phase))))
      ("inherit existing feedback" (setq actions 'inherit))
      ("no feedback, including inherited" (setq actions 'suppress))
      ("say a label then play a cue"
       (setq
        actions
        (list
         (emacsvox-aural-simple-editor--make-speech-action rule-id phase)
         (emacsvox-aural-simple-editor--make-cue-action rule-id phase))))
      ("play a cue then say a label"
       (setq
        actions
        (list
         (emacsvox-aural-simple-editor--make-cue-action rule-id phase)
         (emacsvox-aural-simple-editor--make-speech-action rule-id phase)))))
    (cond
     ((string= choice "keep current") (copy-tree old))
     ((eq actions 'inherit) nil)
     ((eq actions 'suppress) '(:suppress t))
     (actions
      (let ((space
             (emacsvox-aural-simple-editor--read-space
              nil "Feedback")))
        (when space
          (setq
           actions
           (mapcar
            (lambda (action)
              (plist-put action :space (copy-tree space)))
            actions))))
      (list (if append-p :append :replace) actions))
     (t (copy-tree old)))))

(defun emacsvox-aural-simple-editor--edit-content (old)
  "Return simple content styling based on OLD."
  (let* ((content (copy-tree old))
         (speech
          (completing-read
           "Speak the content: "
           '("keep current" "inherit" "yes" "no")
           nil 'must-match nil nil "keep current"))
         (voice-answer
          (completing-read
           "Content voice: "
           (append
            '("keep current" "inherit" "default")
            (emacsvox-aural-editor--voice-candidates))
           nil 'must-match nil nil "keep current"))
         (space
          (emacsvox-aural-simple-editor--read-space
           (plist-get content :space) "Content")))
    (pcase speech
      ("inherit"
       (setq content
             (emacsvox-aural-simple-editor--plist-delete
              content :speak)))
      ("yes" (setq content (plist-put content :speak t)))
      ("no" (setq content (plist-put content :speak nil))))
    (pcase voice-answer
      ("inherit"
       (setq content
             (emacsvox-aural-simple-editor--plist-delete
              content :voice)))
      ("default" (setq content (plist-put content :voice nil)))
      ("keep current")
      (_ (setq content
               (plist-put content :voice (intern voice-answer)))))
    (if space
        (setq content (plist-put content :space space))
      (setq content
            (emacsvox-aural-simple-editor--plist-delete
             content :space)))
    content))

(defun emacsvox-aural-simple-editor--rule (index)
  "Return working rule INDEX."
  (or
   (nth index emacsvox-aural-editor-rules)
   (user-error "Unknown presentation %s" (1+ index))))

(defun emacsvox-aural-simple-editor-edit-field ()
  "Edit the one natural-language field at point."
  (interactive)
  (let* ((field
          (or
           (emacsvox-aural-simple-editor--field-at-point)
           (user-error "Move to an editable field first")))
         (kind (plist-get field :kind))
         (index (plist-get field :rule)))
    (if (eq kind 'advanced)
        (emacsvox-aural-simple-editor-use-advanced)
      (pcase kind
      ('summary
       (setq
        emacsvox-aural-editor-scheme-data
        (plist-put
         (copy-tree emacsvox-aural-editor-scheme-data)
         :summary
         (read-string
          "Scheme summary: "
          (plist-get emacsvox-aural-editor-scheme-data :summary)))))
      ('parent
       (let ((parent
              (emacsvox-aural-editor--read-symbol-or-nil
               "Based on scheme (none for no parent): "
               (plist-get emacsvox-aural-editor-scheme-data :parent)
               (remove
                (symbol-name emacsvox-aural-editor-target)
                (emacsvox-aural-scheme-candidates))
               'must-match)))
         (setq
          emacsvox-aural-editor-scheme-data
          (plist-put
           (copy-tree emacsvox-aural-editor-scheme-data)
           :parent parent))))
      ('resource-pack
       (let ((pack
              (emacsvox-aural-editor--read-symbol-or-nil
               "Sound pack (none means inherit): "
               (plist-get
                emacsvox-aural-editor-scheme-data :resource-pack)
               (emacsvox-aural-resource-pack-candidates 'sound)
               'must-match)))
         (setq
          emacsvox-aural-editor-scheme-data
          (plist-put
           (copy-tree emacsvox-aural-editor-scheme-data)
           :resource-pack pack))))
      ('voice-palette
       (let ((palette
              (emacsvox-aural-editor--read-symbol-or-nil
               "Voice palette (none means inherit): "
               (plist-get
                emacsvox-aural-editor-scheme-data :voice-palette)
               (emacsvox-aural-simple-editor--voice-palette-candidates)
               'must-match)))
         (setq
          emacsvox-aural-editor-scheme-data
          (plist-put
           (copy-tree emacsvox-aural-editor-scheme-data)
           :voice-palette palette))))
      ('enabled
       (let ((rule
              (copy-tree
               (emacsvox-aural-simple-editor--rule index))))
         (setf
          (nth index emacsvox-aural-editor-rules)
          (plist-put
           rule :enabled
           (not (emacsvox-aural-editor--rule-enabled-p rule))))))
      ('match
       (let* ((rule
               (copy-tree
                (emacsvox-aural-simple-editor--rule index)))
              (match
               (emacsvox-aural-simple-editor--edit-match
                (plist-get rule :match))))
         (setq rule (plist-put rule :match match))
         (emacsvox-aural-compile-rule rule 'user)
         (setf (nth index emacsvox-aural-editor-rules) rule)))
      ((or 'before 'after)
       (let* ((rule
               (copy-tree
                (emacsvox-aural-simple-editor--rule index)))
              (render (copy-tree (plist-get rule :render)))
              (phase (plist-get render (intern (format ":%s" kind))))
              (updated
               (emacsvox-aural-simple-editor--edit-phase
                (plist-get rule :id)
                kind
                phase
                (plist-get (plist-get rule :match) :legacy-face))))
         (setq
          render
          (plist-put render (intern (format ":%s" kind)) updated))
         (setq rule (plist-put rule :render render))
         (emacsvox-aural-compile-rule rule 'user)
         (setf (nth index emacsvox-aural-editor-rules) rule)))
      ('content
       (let* ((rule
               (copy-tree
                (emacsvox-aural-simple-editor--rule index)))
              (render (copy-tree (plist-get rule :render)))
              (content
               (emacsvox-aural-simple-editor--edit-content
                (plist-get render :content))))
         (setq render (plist-put render :content content))
         (setq rule (plist-put rule :render render))
         (emacsvox-aural-compile-rule rule 'user)
         (setf (nth index emacsvox-aural-editor-rules) rule))))
      (emacsvox-aural-simple-editor--mark-and-refresh field))))

(defun emacsvox-aural-simple-editor--slug (text)
  "Return a stable identifier fragment for TEXT."
  (let ((slug
         (replace-regexp-in-string
          "\\`-\\|-$" ""
          (replace-regexp-in-string
           "[^[:alnum:]]+" "-" (downcase text)))))
    (if (string-empty-p slug) "presentation" slug)))

(defun emacsvox-aural-simple-editor--unique-rule-id (name)
  "Return a unique rule identifier based on NAME."
  (let* ((base
          (format
           "%s-%s"
           emacsvox-aural-editor-target
           (emacsvox-aural-simple-editor--slug name)))
         (candidate base)
         (suffix 2)
         (ids
          (mapcar
           (lambda (rule) (plist-get rule :id))
           emacsvox-aural-editor-rules)))
    (while (memq (intern candidate) ids)
      (setq candidate (format "%s-%d" base suffix)
            suffix (1+ suffix)))
    (intern candidate)))

(defun emacsvox-aural-simple-editor-add-rule ()
  "Create a new presentation through natural prompts."
  (interactive)
  (let* ((target-kind
          (completing-read
           "Presentation target: "
           '("semantic object" "visual face")
           nil 'must-match nil nil "semantic object"))
         (face
          (when (string= target-kind "visual face")
            (intern
             (completing-read
              "Visual face: "
              (emacsvox-aural-editor--face-candidates)
              nil 'must-match))))
         (role
          (when (string= target-kind "semantic object")
            (intern
             (completing-read
              "Object: "
              (emacsvox-aural-simple-editor--semantic-candidates 'role)
              nil 'must-match nil nil "heading"))))
         (name
          (read-string
           "Presentation name: "
           (format
            "%s presentation"
            (emacsvox-aural-simple-editor--humanize
             (or face role)))))
         (id (emacsvox-aural-simple-editor--unique-rule-id name))
         (module
          (emacsvox-aural-editor--read-symbol-or-nil
           "Module (none means any): "
           (and (eq role 'heading) 'org)
           (emacsvox-aural-simple-editor--module-candidates)))
         (occasion
          (emacsvox-aural-editor--read-symbol-or-nil
           "Occasion (none means any): "
           'navigation
           (emacsvox-aural-occasion-candidates)
           'must-match))
         (match
          (if role
              (list :role role)
            (list :legacy-face face)))
         render)
    (when module (setq match (plist-put match :module module)))
    (when occasion (setq match (plist-put match :occasion occasion)))
    (when (eq role 'heading)
      (let ((level (read-number "Heading level (0 means every level): " 0)))
        (when (> level 0)
          (setq match (plist-put match :level level)))))
    (when role
      (let ((state
             (emacsvox-aural-editor--read-symbol-or-nil
              "Required state (none means any): "
              nil
              (emacsvox-aural-simple-editor--semantic-candidates 'state)
              'must-match)))
        (when state (setq match (plist-put match :states (list state))))))
    (let ((before
           (emacsvox-aural-simple-editor--edit-phase
            id 'before nil face))
          (content
           (emacsvox-aural-simple-editor--edit-content nil))
          (after
           (emacsvox-aural-simple-editor--edit-phase
            id 'after nil face)))
      (when before (setq render (plist-put render :before before)))
      (when content (setq render (plist-put render :content content)))
      (when after (setq render (plist-put render :after after))))
    (let ((rule
           (list :id id :enabled t :match match :render render)))
      (emacsvox-aural-compile-rule rule 'user)
      (setq
       emacsvox-aural-editor-rules
       (append emacsvox-aural-editor-rules (list rule))))
    (emacsvox-aural-simple-editor--mark-and-refresh
     (list :kind 'enabled
           :rule (1- (length emacsvox-aural-editor-rules))))))

(defun emacsvox-aural-simple-editor-delete-rule ()
  "Delete the presentation containing the current field."
  (interactive)
  (let* ((field
          (or
           (emacsvox-aural-simple-editor--field-at-point)
           (user-error "Move to a presentation field first")))
         (index
          (or (plist-get field :rule)
              (user-error "The current field belongs to the scheme"))))
    (when
        (yes-or-no-p
         (format
          "Delete presentation %s? "
          (emacsvox-aural-simple-editor--humanize
           (plist-get
            (emacsvox-aural-simple-editor--rule index)
            :id))))
      (setq
       emacsvox-aural-editor-rules
       (append
        (cl-subseq emacsvox-aural-editor-rules 0 index)
        (nthcdr (1+ index) emacsvox-aural-editor-rules)))
      (emacsvox-aural-simple-editor--mark-and-refresh))))

(defun emacsvox-aural-simple-editor-toggle-rule ()
  "Enable or disable the presentation containing the current field."
  (interactive)
  (let* ((field
          (or
           (emacsvox-aural-simple-editor--field-at-point)
           (user-error "Move to a presentation field first")))
         (index
          (or (plist-get field :rule)
              (user-error "The current field belongs to the scheme")))
         (rule
          (copy-tree
           (emacsvox-aural-simple-editor--rule index))))
    (setf
     (nth index emacsvox-aural-editor-rules)
     (plist-put
      rule :enabled
      (not (emacsvox-aural-editor--rule-enabled-p rule))))
    (emacsvox-aural-simple-editor--mark-and-refresh
     (list :kind 'enabled :rule index))))

(defun emacsvox-aural-simple-editor-save ()
  "Validate and save the current personal scheme."
  (interactive)
  (let* ((rules (emacsvox-aural-editor--normalized-rules))
         (report (emacsvox-aural-editor--validation-report)))
    (unless (emacsvox-aural-validation-report-valid report)
      (user-error
       "Cannot save scheme: %s"
       (string-join
        (emacsvox-aural-validation-report-errors report) "; ")))
    (emacsvox-aural-editor--commit-scheme rules)
    (setq
     emacsvox-aural-editor-rules (copy-tree rules)
     emacsvox-aural-editor-dirty nil)
    (force-mode-line-update)
    (emacsvox-aural-simple-editor-refresh)
    (message "Saved aural scheme %s" emacsvox-aural-editor-target)))

(defun emacsvox-aural-simple-editor-activate ()
  "Activate the scheme being edited."
  (interactive)
  (when emacsvox-aural-editor-dirty
    (if (yes-or-no-p "Save changes before activating this scheme? ")
        (emacsvox-aural-simple-editor-save)
      (user-error "Save or discard the working changes before activation")))
  (emacsvox-set-aural-scheme emacsvox-aural-editor-target)
  (emacsvox-aural-simple-editor-refresh)
  (message "Activated aural scheme %s" emacsvox-aural-editor-target))

(defun emacsvox-aural-simple-editor-preview ()
  "Preview the presentation containing the current field."
  (interactive)
  (emacsvox-aural-editor-preview-rule))

(defun emacsvox-aural-simple-editor-explain ()
  "Explain the presentation containing the current field."
  (interactive)
  (emacsvox-aural-editor-explain-rule))

(defun emacsvox-aural-simple-editor-validate ()
  "Validate the working personal scheme."
  (interactive)
  (emacsvox-aural-editor-validate))

(defun emacsvox-aural-simple-editor--switch-to (mode refresh)
  "Switch the current working editor to MODE and call REFRESH."
  (let ((scope emacsvox-aural-editor-scope)
        (target emacsvox-aural-editor-target)
        (data emacsvox-aural-editor-scheme-data)
        (rules emacsvox-aural-editor-rules)
        (dirty emacsvox-aural-editor-dirty))
    (funcall mode)
    (setq
     emacsvox-aural-editor-scope scope
     emacsvox-aural-editor-target target
     emacsvox-aural-editor-scheme-data data
     emacsvox-aural-editor-rules rules
     emacsvox-aural-editor-dirty dirty)
    (funcall refresh)))

(defun emacsvox-aural-simple-editor-use-advanced ()
  "Switch this working buffer to the advanced rule editor."
  (interactive)
  (emacsvox-aural-simple-editor--switch-to
   #'emacsvox-aural-scheme-editor-mode
   #'emacsvox-aural-editor-refresh)
  (message "Advanced aural rule editor"))

(defun emacsvox-aural-editor-use-simple-editor ()
  "Switch an advanced personal-scheme buffer to the simple editor."
  (interactive)
  (unless (eq emacsvox-aural-editor-scope 'scheme)
    (user-error "Simple editing is available for personal schemes"))
  (emacsvox-aural-simple-editor--switch-to
   #'emacsvox-aural-simple-editor-mode
   #'emacsvox-aural-simple-editor-refresh)
  (when (called-interactively-p 'interactive)
    (emacsvox-aural-simple-editor--speak-current-field)))

(defun emacsvox-aural-simple-editor-help ()
  "Display and speak simple editor help."
  (interactive)
  (with-help-window (help-buffer)
    (princ
     (concat
      "Simple Aural Scheme Editor\n\n"
      "The buffer is a spoken form.  TAB and Shift-TAB move between fields,\n"
      "and RET changes only the current field.  Each presentation says what\n"
      "it applies to and what happens before, during, and after its content.\n"
      "A new presentation can target registered meaning or a visual face.\n\n"
      "TAB next field       Shift-TAB previous field\n"
      "RET edit field       n new presentation\n"
      "p preview            x explain\n"
      "d delete             t enable or disable\n"
      "v validate           s save\n"
      "a activate scheme    A advanced editor\n"
      "g refresh            h aural home\n"
      "q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(defvar emacsvox-aural-simple-editor-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map emacsvox-aural-interface-mode-map)
    (define-key map (kbd "TAB") #'emacsvox-aural-simple-editor-next-field)
    (define-key map (kbd "<backtab>")
                #'emacsvox-aural-simple-editor-previous-field)
    (define-key map (kbd "S-TAB")
                #'emacsvox-aural-simple-editor-previous-field)
    (define-key map (kbd "RET") #'emacsvox-aural-simple-editor-edit-field)
    (define-key map (kbd "e") #'emacsvox-aural-simple-editor-edit-field)
    (define-key map (kbd "n") #'emacsvox-aural-simple-editor-add-rule)
    (define-key map (kbd "d") #'emacsvox-aural-simple-editor-delete-rule)
    (define-key map (kbd "t") #'emacsvox-aural-simple-editor-toggle-rule)
    (define-key map (kbd "p") #'emacsvox-aural-simple-editor-preview)
    (define-key map (kbd "x") #'emacsvox-aural-simple-editor-explain)
    (define-key map (kbd "v") #'emacsvox-aural-simple-editor-validate)
    (define-key map (kbd "s") #'emacsvox-aural-simple-editor-save)
    (define-key map (kbd "a") #'emacsvox-aural-simple-editor-activate)
    (define-key map (kbd "A") #'emacsvox-aural-simple-editor-use-advanced)
    (define-key map (kbd "g") #'emacsvox-aural-simple-editor-refresh)
    (define-key map (kbd "h") #'emacsvox-aural)
    (define-key map (kbd "?") #'emacsvox-aural-simple-editor-help)
    (define-key map (kbd "q") #'emacsvox-aural-editor-quit)
    map)
  "Keymap for `emacsvox-aural-simple-editor-mode'.")

(define-derived-mode emacsvox-aural-simple-editor-mode
    emacsvox-aural-interface-mode
  "Simple-Aural-Editor"
  "Spoken field editor for one personal aural presentation scheme."
  (setq-local
   mode-line-process
   '(:eval (when emacsvox-aural-editor-dirty " [modified]"))))

(defun emacsvox-aural-simple-editor--built-in-scheme-candidates ()
  "Return built-in scheme identifiers."
  (let (ids)
    (maphash
     (lambda (id entry)
       (when (emacsvox-aural-scheme-entry-built-in entry)
         (push (symbol-name id) ids)))
     emacsvox-aural-scheme-registry)
    (sort ids #'string-lessp)))

(defun emacsvox-aural-simple-editor--copy-built-in ()
  "Interactively create and return an editable flattened built-in copy."
  (let* ((source
          (intern
           (completing-read
            "Copy built-in scheme: "
            (emacsvox-aural-simple-editor--built-in-scheme-candidates)
            nil 'must-match)))
         (new-id
          (intern
           (read-string
            "New personal scheme name: "
            (format "%s-personal" source)))))
    (emacsvox-copy-aural-scheme source new-id t)
    new-id))

(defun emacsvox-aural-simple-editor--read-scheme ()
  "Read a personal scheme, offering to copy a built-in."
  (let* ((copy "[Copy a built-in scheme]")
         (personal
          (emacsvox-aural-editor--personal-scheme-candidates))
         (choice
          (completing-read
           "Edit personal aural scheme: "
           (append personal (list copy))
           nil 'must-match nil nil
           (if personal (car personal) copy))))
    (if (string= choice copy)
        (emacsvox-aural-simple-editor--copy-built-in)
      (intern choice))))

(defun emacsvox-aural-simple-editor-open (&optional scheme)
  "Open the simple spoken editor for personal SCHEME."
  (let* ((source
          (emacsvox-aural-inspection-remember-source-buffer))
         (scheme
          (or scheme
              (emacsvox-aural-simple-editor--read-scheme)))
         (entry (emacsvox-aural-scheme-entry scheme)))
    (unless entry
      (user-error "Unknown aural scheme: %S" scheme))
    (when (emacsvox-aural-scheme-entry-built-in entry)
      (user-error
       "Built-in scheme %s is read-only; choose Copy a built-in scheme"
       scheme))
    (let ((buffer
           (get-buffer-create
            (format "*Simple Aural Scheme: %s*" scheme))))
      (with-current-buffer buffer
        (emacsvox-aural-simple-editor-mode)
        (emacsvox-aural-inspection-attach-source source)
        (setq
         emacsvox-aural-editor-scope 'scheme
         emacsvox-aural-editor-target scheme
         emacsvox-aural-editor-scheme-data
         (copy-tree (emacsvox-aural-scheme-entry-data entry))
         emacsvox-aural-editor-rules
         (copy-tree
          (plist-get
           (emacsvox-aural-scheme-entry-data entry) :rules))
         emacsvox-aural-editor-dirty nil)
        (emacsvox-aural-simple-editor-refresh))
      (pop-to-buffer buffer)
      (emacsvox-aural-simple-editor--speak-current-field)
      buffer)))

(define-key
 emacsvox-aural-scheme-editor-mode-map
 (kbd "A")
 #'emacsvox-aural-editor-use-simple-editor)

(provide 'emacsvox-aural-simple-editor)
;;; emacsvox-aural-simple-editor.el ends here
