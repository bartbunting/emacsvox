;;; emacsvox-aural-audit.el --- Audit and document aural schemes -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Validate the semantic, scheme, cue, sound-pack, and voice-palette
;; registries.  Parse literal auditory-icon calls without evaluating source,
;; and generate the maintained author reference from the live registries.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defvar read-eval)

(defconst emacsvox-aural-audit-reference-file
  "etc/aural-presentation-reference.org"
  "Repository-relative path of the generated aural reference.")

(defconst emacsvox-aural-audit-default-root
  (file-name-as-directory
   (expand-file-name
    ".."
    (file-name-directory (or load-file-name buffer-file-name))))
  "Repository root inferred from this audit utility.")

(defvar emacsvox-sounds-dir
  (expand-file-name "sounds" emacsvox-aural-audit-default-root)
  "Sound directory used while loading resource registries for the audit.")

(require 'emacsvox-sounds)
(require 'emacsvox-aural-tools)
(require 'emacsvox-aural-provider-org)
(require 'emacsvox-aural-provider-workflows)
(require 'emacsvox-aural-provider-markdown)
(require 'emacsvox-aural-provider-notmuch)
(require 'emacsvox-dired)

(defconst emacsvox-aural-audit-icon-functions
  '(emacsvox-icon emacsvox-queue-icon)
  "Functions whose literal cue arguments are included in the source audit.")

(defconst emacsvox-aural-audit-migrated-icon-boundaries
  '((emacsvox-agent-shell.el
     emacsvox-agent-shell--call-with-aural-presentation
     emacsvox-agent-shell--present-feedback)
    (emacsvox-markdown.el
     emacsvox-markdown--call-with-aural-presentation)
    (emacsvox-org.el
     emacsvox-org--call-with-aural-presentation
     emacsvox-org--present-feedback
     emacsvox-org--present-feedback-after)
    (emacsvox-notmuch.el
     emacsvox-notmuch--call-with-aural-presentation
     emacsvox-notmuch--present-feedback)
    (emacsvox-gnus.el
     emacsvox-gnus--call-with-aural-presentation
     emacsvox-gnus--present-feedback)
    (emacsvox-dired.el
     emacsvox-dired--call-with-aural-presentation
     emacsvox-dired--present-feedback)
    (emacsvox-magit.el
     emacsvox-magit--call-with-aural-presentation
     emacsvox-magit--present-feedback))
  "Migrated modules and calls that establish semantic icon context.

A direct icon call in one of these modules must occur below one of its
listed calls, or in an internal function whose name ends in
`-compatibility'.")

(defun emacsvox-aural-audit--root (&optional root)
  "Return normalized repository ROOT or the inferred default."
  (file-name-as-directory
   (expand-file-name (or root emacsvox-aural-audit-default-root))))

(defun emacsvox-aural-audit--symbol-less-p (left right)
  "Return non-nil when LEFT precedes RIGHT by symbol name."
  (string-lessp (symbol-name left) (symbol-name right)))

(defun emacsvox-aural-audit--hash-records (table accessor)
  "Return TABLE values sorted by the identifier returned by ACCESSOR."
  (let (records)
    (maphash (lambda (_ record) (push record records)) table)
    (sort
     records
     (lambda (left right)
       (emacsvox-aural-audit--symbol-less-p
        (funcall accessor left)
        (funcall accessor right))))))

(defun emacsvox-aural-audit--source-files (root)
  "Return sorted Lisp source files below ROOT."
  (sort
   (directory-files-recursively
    (expand-file-name "lisp" root) "\\.el\\'")
   #'string-lessp))

(defun emacsvox-aural-audit--record-cue (cue relative usage)
  "Record literal CUE from RELATIVE in USAGE."
  (let ((entry (gethash cue usage)))
    (puthash
     cue
     (list
      :count (1+ (or (plist-get entry :count) 0))
      :files (sort
              (delete-dups
               (cons relative (copy-sequence (plist-get entry :files))))
              #'string-lessp))
     usage)))

(defun emacsvox-aural-audit-source-cues (&optional root)
  "Return literal and dynamic auditory-icon usage below repository ROOT.

Source forms are read with `read-eval' disabled.  Calls in comments, strings,
and quoted data are ignored.  The result contains sorted usage entries,
dynamic-call count, and source parse errors."
  (let* ((root (emacsvox-aural-audit--root root))
         (usage (make-hash-table :test #'eq))
         (dynamic-count 0)
         parse-errors)
    (dolist (file (emacsvox-aural-audit--source-files root))
      (let ((relative (file-relative-name file root)))
        (with-temp-buffer
          (insert-file-contents file)
          (emacs-lisp-mode)
          (goto-char (point-min))
          (let ((read-eval nil))
            (cl-labels
                ((walk
                  (form)
                  (cond
                   ((atom form) nil)
                   ((eq (car form) 'quote) nil)
                   (t
                    (when (memq
                           (car form)
                           emacsvox-aural-audit-icon-functions)
                      (let ((argument (cadr form)))
                        (if
                            (and
                             (consp argument)
                             (eq (car argument) 'quote)
                             (symbolp (cadr argument)))
                            (emacsvox-aural-audit--record-cue
                             (cadr argument) relative usage)
                          (cl-incf dynamic-count))))
                    (walk (car form))
                    (walk (cdr form))))))
              (condition-case error
                  (while
                      (progn
                        (forward-comment (point-max))
                        (not (eobp)))
                    (walk (read (current-buffer))))
                (error
                 (push
                  (format
                   "%s:%d: %s"
                   relative
                   (line-number-at-pos)
                   (error-message-string error))
                  parse-errors))))))))
    (let (entries)
      (maphash
       (lambda (cue data) (push (cons cue data) entries))
       usage)
      (list
       :usage
       (sort
        entries
        (lambda (left right)
          (emacsvox-aural-audit--symbol-less-p
           (car left) (car right))))
       :literal-count
       (cl-loop
        for (_ . data) in entries
        sum (plist-get data :count))
       :dynamic-count dynamic-count
       :parse-errors (nreverse parse-errors)))))

(defun emacsvox-aural-audit--compatibility-function-p (function)
  "Return non-nil when FUNCTION explicitly names a compatibility adapter."
  (and
   (symbolp function)
   (string-suffix-p "-compatibility" (symbol-name function))))

(defun emacsvox-aural-audit-context-free-icons (&optional root)
  "Return direct icon calls outside semantic boundaries in migrated modules.

Repository ROOT is read without evaluation.  Each returned plist identifies
the source file, containing function when statically known, and icon
function.  Calls to a named compatibility adapter must themselves occur
below a presentation boundary."
  (let ((root (emacsvox-aural-audit--root root))
        failures)
    (dolist (entry emacsvox-aural-audit-migrated-icon-boundaries)
      (let* ((basename (symbol-name (car entry)))
             (boundaries (cdr entry))
             (file (expand-file-name (concat "lisp/" basename) root))
             forms
             (compatibility-icons (make-hash-table :test #'eq)))
        (when (file-readable-p file)
          (with-temp-buffer
            (insert-file-contents file)
            (emacs-lisp-mode)
            (goto-char (point-min))
            (let ((read-eval nil))
              (condition-case nil
                  (while
                      (progn
                        (forward-comment (point-max))
                        (not (eobp)))
                    (push (read (current-buffer)) forms))
                (error nil))))
          (setq forms (nreverse forms))
          (cl-labels
              ((collect-icons
                (form function)
                (cond
                 ((atom form) nil)
                 ((eq (car form) 'quote) nil)
                 ((eq (car form) 'defun)
                  (let ((nested
                         (and (symbolp (cadr form)) (cadr form))))
                    (dolist (body-form (cdddr form))
                      (collect-icons body-form nested))))
                 (t
                  (when
                      (and function
                           (memq
                            (car form)
                            emacsvox-aural-audit-icon-functions))
                    (puthash
                     function
                     (delete-dups
                      (cons
                       (car form)
                       (gethash function compatibility-icons)))
                     compatibility-icons))
                  (let ((tail form))
                    (while (consp tail)
                      (collect-icons (car tail) function)
                      (setq tail (cdr tail)))
                    (when tail
                      (collect-icons tail function)))))))
            (dolist (form forms)
              (when
                  (and
                   (consp form)
                   (eq (car form) 'defun)
                   (emacsvox-aural-audit--compatibility-function-p
                    (cadr form)))
                (collect-icons form nil))))
          (cl-labels
              ((record
                (function icon-function &optional compatibility-function)
                (push
                 (append
                  (list
                   :file (file-relative-name file root)
                   :function function
                   :icon-function icon-function)
                  (when compatibility-function
                    (list
                     :compatibility-function compatibility-function)))
                 failures))
               (walk
                (form inside-boundary containing-function)
                (cond
                 ((atom form) nil)
                 ((eq (car form) 'quote) nil)
                 ((eq (car form) 'defun)
                  (let ((function
                         (if (symbolp (cadr form))
                             (cadr form)
                           containing-function)))
                    (dolist (body-form (cdddr form))
                      (walk body-form nil function))))
                 (t
                  (let* ((head (car form))
                         (bounded
                          (or inside-boundary
                              (memq head boundaries)))
                         (compatibility
                          (gethash head compatibility-icons)))
                    (when
                        (and
                         (memq head emacsvox-aural-audit-icon-functions)
                         (not bounded)
                         (not
                          (emacsvox-aural-audit--compatibility-function-p
                           containing-function)))
                      (record containing-function head))
                    (when (and compatibility (not bounded))
                      (dolist (icon-function compatibility)
                        (record
                         containing-function icon-function head)))
                    (let ((tail form))
                      (while (consp tail)
                        (walk (car tail) bounded containing-function)
                        (setq tail (cdr tail)))
                      (when tail
                        (walk tail bounded containing-function))))))))
            (dolist (form forms)
              (walk form nil nil))))))
    (sort
     failures
     (lambda (left right)
       (let ((left-key
              (format
               "%s:%s:%s:%s"
               (plist-get left :file)
               (plist-get left :function)
               (plist-get left :icon-function)
               (plist-get left :compatibility-function)))
             (right-key
              (format
               "%s:%s:%s:%s"
               (plist-get right :file)
               (plist-get right :function)
               (plist-get right :icon-function)
               (plist-get right :compatibility-function))))
         (string-lessp left-key right-key))))))

(defun emacsvox-aural-audit--org-value (value)
  "Return VALUE formatted for an Org table cell."
  (let ((text
         (cond
          ((null value) "-")
          ((stringp value) value)
          ((listp value)
           (mapconcat
            (lambda (item) (format "=%s=" item))
            value ", "))
          (t (format "=%s=" value)))))
    (replace-regexp-in-string "[|\n]" " " text)))

(defun emacsvox-aural-audit--insert-table (headers rows)
  "Insert an Org table with HEADERS and ROWS at point."
  (insert
   "| "
   (mapconcat #'identity headers " | ")
   " |\n|"
   (mapconcat
    (lambda (header)
      (make-string (+ 2 (length header)) ?-))
    headers
    "+")
   "|\n")
  (dolist (row rows)
    (insert
     "| "
     (mapconcat #'emacsvox-aural-audit--org-value row " | ")
     " |\n"))
  (insert "\n"))

(defun emacsvox-aural-audit--insert-overview ()
  "Insert the maintained user and contract overview at point."
  (insert
   "* Using Aural Presentation Schemes\n\n"
   "A semantic fact says what an object or event means.  A scheme decides "
   "whether that fact is conveyed by speech, voice, a cue, a pause, spatial "
   "placement, or a composition of those modalities.  Modules therefore do "
   "not need to agree on one preferred presentation.\n\n"
   "The built-in =default= scheme preserves existing Emacsvox voices and "
   "auditory icons.  The Org example schemes are opt-in demonstrations.  "
   "Use =M-x emacsvox-aural= or =C-e H= to open the spoken aural home.  "
   "It reports current status and routes to explanation, schemes, presentation "
   "options, presentation profiles, source-buffer rules, semantic "
   "vocabulary, sound packs, spatial controls, training, and the Aural "
   "Doctor.  Press =h= in any routed manager or editor to return home.  From "
   "an ordinary buffer, =C-e E= always invokes "
   "=emacsvox-aural-explain-presentation= at point.\n\n"
   "Visual face presentation is a separate default-on control.  Use the "
   "=Visual face presentation= row, press =v= in the aural home, or run "
   "=M-x emacsvox-aural-toggle-face-presentation= to toggle rules with a "
   "=:legacy-face= selector.  Turning it off does not disable semantic "
   "role, event, state, or attribute rules.  Voice Lock remains a per-buffer "
   "compatibility control: it gates only historical face/personality-to-voice "
   "mapping and =:legacy-personality= matching.  The source state of both "
   "controls is frozen into each presentation and reported by explanation "
   "and the Aural Doctor.\n\n"
   "Use =M-x emacsvox-aural-list-profiles= to save and switch complete named "
   "configurations.  A profile references one base scheme and ordered feature "
   "fragments and may capture sound-pack, voice-palette, and portable-spatial "
   "settings.  It never copies rules: edit those in the scheme and fragment "
   "managers.  Profile activation validates every reference before changing "
   "the live configuration and rolls the complete change back on failure.  "
   "Exactly one persisted profile identity is selected.  It is active while "
   "live values match its saved configuration and modified after settings "
   "diverge; other profiles remain inactive even when their values match.\n\n"
   "Use =M-x emacsvox-aural-doctor= to inspect the live bindings, loaded "
   "source or byte-code, active scheme and fragments, saved profiles, sound "
   "resources, personal data, spatial fallback, speech server, and training "
   "state, including the independent face and Voice Lock controls.  It does "
   "not start the server or repair anything automatically.  "
   "The =r= command runs the explicitly offered safe repair for one row.\n\n"
   "Use =M-x emacsvox-aural-list-schemes= to open the spoken scheme manager.  "
   "It views direct and inherited presentations and provides edit, copy, "
   "delete, rename, activate, preview, and validation actions.  Use "
   "=M-x emacsvox-aural-reset-scheme= to return to the default.  Established "
   "verb-first command names remain compatible.\n\n"
   "Use =M-x emacsvox-aural-list-feature-fragments= to manage independent "
   "presentation additions over the active base scheme.  The user interface "
   "calls these presentation options and groups them into expandable "
   "integration collections.  Core, integration modules, third-party "
   "extensions, and personal data may provide options; collection membership "
   "affects discovery only.  Press =a= to show enabled options in exact "
   "weakest-to-strongest cascade order.  Enabling or disabling an option "
   "preserves that stable order.  Press =P= to preview an option composed "
   "with the active configuration without enabling it, or =C-u P= to hear "
   "the option alone.  Preview uses matching facts from the remembered source "
   "buffer when possible and announces that as live source context; otherwise "
   "it announces and uses a simulated example.  Create, copy, edit, delete, "
   "validate, toggle, and reorder changes use the same atomic personal-data store.  "
   "Built-in Org options can add a dynamic heading-level label, section cue, "
   "or visibility-change wording without replacing the active scheme.\n\n"
   "Use =M-x emacsvox-aural-list-sound-packs= to inspect active state, "
   "inheritance, native and effective assets, coverage, spatialization, "
   "validation, directory, and intent.  Its cue browser identifies native, "
   "inherited, fallback, and missing resources and auditions the frozen "
   "concrete file without activating the inspected pack.  Discovered personal "
   "packs have a guided, atomic, data-only manifest editor.\n\n"
   "Use =M-x emacsvox-aural-edit-scheme= for a spoken field editor over a "
   "persistent personal scheme.  It can create a flattened editable copy of "
   "a built-in scheme.  Use =M-x emacsvox-aural-edit-scheme-advanced= for "
   "the declarative rule view, or =M-x emacsvox-aural-edit-rules= for "
   "persistent, session, or buffer-local rules.  "
   "=M-x emacsvox-explain-aural-presentation= shows "
   "facts, context, matching rules, provenance, concrete resources, "
   "suppression, and backend degradation.  When available it explains the "
   "last exact presentation queued from the source buffer, including its "
   "source position and object/run identity, even after configuration changes.  "
   "Both spoken and visual output label this as exact heard output.  Without "
   "a queued record it labels current rule resolution as a simulation and "
   "automatically chooses the occasion with the most matching rules.  Use a "
   "prefix argument to deliberately simulate another occasion.  History is "
   "bounded by =emacsvox-aural-presentation-history-limit= and never retains "
   "source buffers; set the limit to zero to disable it.\n\n"
   "** Cascade and Deterministic Selection\n\n"
   "Matching rules are applied from weaker to stronger.  Origin layers are "
   "=core=, module fragments, the active inherited scheme, ordered enabled "
   "presentation options, persistent user rules, session rules, and buffer "
   "rules.  One base scheme is active, while any number of independent "
   "presentation options may add presentation without replacing it.  "
   "Automatic module compatibility fragments are a separate default layer "
   "and do not appear as toggleable options.  Within an origin, semantic "
   "identity, an exact combined module/mode match, exact or nearest derived "
   "mode, module, additional constraints, inheritance layer, and explicit "
   "rule order determine specificity.  A stable rule identifier breaks a "
   "remaining true tie, so hash and registration order cannot change output.\n\n"
   "A buffer rule can therefore override one module in one buffer without "
   "changing the same semantic in other buffers.  A mode selector also "
   "matches derived modes, with the nearest ancestor winning.  Combine "
   "=:module= and =:mode= when the same mode should sound different in one "
   "integration.  Interactive physical or visual Up and Down movement uses "
   "the =navigation= occasion and =focus-entered= event, so arrowing onto a "
   "semantic object matches structural navigation.  Continuous-reading "
   "commands retain the =continuous= occasion.\n\n"
   "** Render and Queue Contract\n\n"
   "Each aural object has ordered =before= actions, one or more styled content "
   "runs, and ordered =after= actions.  A face or personality change creates "
   "a formatting run, not another object, so object labels and cues do not "
   "repeat merely because styling changes.  Speech, cue, and pause actions "
   "may be added.  "
   "Phase operators are =:prepend=, =:append=, =:replace=, =:remove=, and "
   "=:suppress=.  Content independently controls =:speak=, =:voice=, "
   "=:volume=, =:space=, and =:suppress=; the strongest rule that sets a "
   "scalar wins.  Ordered actions may use =:anchor object=, =:anchor run=, "
   "or =:anchor transition=.  An omitted anchor defaults to =run= for face "
   "and personality selectors and =object= otherwise.\n\n"
   "Named source faces are captured before source text is copied.  Ordered "
   "overlay faces use Emacs overlay priority and precede explicit =face= and "
   "=font-lock-face= text properties; both text properties are retained, with "
   "=face= first.  Only explicit symbol or string face names and named "
   "=:inherit= values are captured.  Theme inheritance and face remapping are "
   "not expanded into identity.  Frozen context retains data-only source, "
   "property, priority, range, and order provenance.\n\n"
   "Semantic and contextual resolution happens in Emacs at the source "
   "submission boundary.  Safe speech templates become literal text, cue "
   "names become concrete files or sample IDs, voices become adapter "
   "commands, and spatial requests become backend values before anything is "
   "queued.  The speech server never resolves templates, schemes, modes, "
   "modules, semantics, or resource fallbacks.  A complete multi-action plan "
   "uses one strict queue.  Only a standalone compatibility cue may use the "
   "selected local player.  Validated rule snapshots and inherited providers "
   "are reused within one configuration generation.  Sound content digests "
   "are reused by canonical file identity and modification metadata and are "
   "cleared when resource packs refresh.\n\n"
   "The current speech queue has no portable volume operation.  Explicit "
   "content or action volume therefore records an =unsupported-volume= "
   "capability degradation by default instead of being silently ignored.  "
   "Set =emacsvox-aural-unsupported-volume-policy= to =reject= to fail before "
   "queueing any presentation that requests volume.\n\n"
   "** Spatial Fallback\n\n"
   "Portable space is normalized =:balance= from =-1.0= left through =+1.0= "
   "right.  Listener-relative =:azimuth= from =-180= through =+180= degrees "
   "reduces to stereo balance.  Unsupported or mono transports remain audible "
   "at the centre, and pre-spatialized assets are not positioned twice.  "
   "Global, speech-only, cue-only, output, maximum-separation, and remapping "
   "controls are available through the =emacsvox-aural-spatial= Customize "
   "group.  Use =M-x emacsvox-describe-aural-spatial-capabilities= to inspect "
   "the current fallback.\n\n"))

(defun emacsvox-aural-audit--insert-scheme-author-reference ()
  "Insert the declarative scheme-author reference at point."
  (insert
   "* Scheme Author Reference\n\n"
   "Personal data lives in =~/.emacsvox/aural-schemes.el=.  It is versioned "
   "declarative Lisp data; evaluation syntax is rejected by the reader.  Prefer the "
   "accessible editor; if data is authored directly, retain the outer "
   "=:schema-version=, =:schemes=, =:feature-fragments=, "
   "=:feature-fragment-order=, =:enabled-feature-fragments=, "
   "=:voice-palettes=, =:profiles=, =:active-profile=, and =:user-rules= "
   "fields.\n\n"
   "A scheme contains =:schema-version=, =:id=, nonempty =:summary=, optional "
   "=:parent=, optional =:resource-pack= and =:voice-palette=, and =:rules=.  "
   "Every rule has a globally stable =:id=, optional boolean =:enabled=, "
   "optional integer =:order=, a =:match= plist, and a =:render= plist.\n\n"
   "#+begin_src emacs-lisp\n"
   "(:schema-version 1\n"
   " :id personal-headings\n"
   " :summary \"Speak and position first-level Org headings\"\n"
   " :parent default\n"
   " :rules\n"
   " ((:id personal-org-heading-1\n"
   "   :match (:role heading :module org :mode org-mode\n"
   "           :occasion navigation :level 1)\n"
   "   :render\n"
   "   (:before\n"
   "    (:append ((:id heading-label :kind speech :text \"Heading 1\"\n"
   "              :anchor object)))\n"
   "    :content (:voice bolden :space (:balance -0.2))\n"
   "    :after\n"
   "    (:append ((:id heading-end :kind cue :cue section)))))))\n"
   "#+end_src\n\n"
   "Selectors use =:role=, =:event= or =:events=, =:state= or =:states=, "
   "registered attribute keywords, =:requires= for registered attributes "
   "that must exist without fixing their value, =:module=, =:mode=, "
   "=:occasion=, =:legacy-cue=, =:legacy-face=, and "
   "=:legacy-personality=.  Unknown "
   "semantics, attributes, cues, voices, providers, fields, or schema "
   "versions fail validation.  Singular and plural state and event forms are "
   "canonicalized, range-local scalar facts override base facts, and local "
   "state and event sets compose with base sets.  Explanation displays this "
   "same authoritative fact plist.  Declared role, occasion, and phase "
   "contracts reject impossible selectors.  Validation warns about deprecated "
   "semantic aliases and rules whose fallback selectors overlap more-specific "
   "rules.\n\n"
   "Ordered actions require an =:id= and =:kind=.  A speech action supplies "
   "either literal =:text= or a safe =:text-template= such as "
   "=\"Heading {level}\"=, and may supply =:voice=, =:volume=, and =:space=.  "
   "A template can name only =role= or registered attributes, and its "
   "selector must guarantee every field by exact match or =:requires=.  "
   "Templates perform substitution only; they cannot evaluate Lisp.  A cue "
   "action supplies a registered =:cue= and may supply =:volume= and "
   "=:space=.  A pause supplies a nonnegative =:duration=.  Optional "
   "=:anchor= is =object=, =run=, or =transition=.  Semantic rules default "
   "to one action per object; compatibility face and personality rules "
   "default to one per formatting run.  A before transition action occurs "
   "when entering matching presentation and an after transition action when "
   "leaving it.  Action IDs are the handles used by later =:remove= "
   "operations.\n\n"))

(defun emacsvox-aural-audit--insert-module-author-reference ()
  "Insert the integration module-author reference at point."
  (insert
   "* Module Author Reference\n\n"
   "Register meaning before emitting it.  A semantic registration supplies a "
   "unique identifier, =:kind= (=role=, =event=, =state=, or =attribute=), "
   "intent summary, owner, and any value, occasion, phase, fallback, or usage "
   "contract.  Optional =:roles= restricts a state, event, or attribute to "
   "named roles; optional =:attributes=, =:states=, and =:events= restrict a "
   "role.  These restrictions, =:occasions=, and =:phases= are enforced for "
   "facts and rules rather than serving only as documentation.  The registry "
   "owner defines the intent, type, and allowed values; modules emit those "
   "facts, while schemes and fragments decide only how to present them.  "
   "For example, core owns the =visibility= attribute "
   "and its =folded= and =expanded= values.  Do not use a visual face, voice "
   "name, cue name, or file name as semantic identity.\n\n"
   "#+begin_src emacs-lisp\n"
   "(emacsvox-aural-register-semantic\n"
   " 'diagnostic\n"
   " :kind 'role\n"
   " :summary \"A source diagnostic\"\n"
   " :owner 'example-module\n"
   " :occasions '(navigation continuous)\n"
   " :phases '(before content after))\n"
   "#+end_src\n\n"
   "Use =emacsvox-aural-register-semantic-alias= when an identifier must be "
   "renamed.  Aliases remain readable migration hooks tagged with the "
   "semantic contract version, compile to the canonical identifier, and "
   "produce deprecation diagnostics.  Never silently reuse an old identifier "
   "for a different intent.  A fallback must retain the same semantic kind.  "
   "When emitted facts name a more specific semantic, rules selecting its "
   "fallback also match weakly; exact rules compose later and explanation "
   "shows the complete path and distance.\n\n"
   "For persistent formatted text, attach =emacsvox-aural-facts= and "
   "=emacsvox-aural-module= text properties.  A submission is one inferred "
   "object until facts, module, occasion, or a new queued icon changes.  "
   "Attach the same non-nil =emacsvox-aural-object= value across adjacent "
   "runs when an explicitly identified object must span those changes.  For "
   "transient output, bind "
   "=emacsvox-aural-submission-facts=, "
   "=emacsvox-aural-submission-context=, "
   "=emacsvox-aural-submission-module=, and "
   "=emacsvox-aural-submission-occasion= around the existing =tts-speak= or "
   "=emacsvox-icon= call.  Use =emacsvox-aural-source-substring= instead of "
   "=buffer-substring= when copied source text can be styled by overlays; the "
   "returned string carries the same authoritative face snapshot used by "
   "point explanation.  Capture context in the source buffer before text "
   "enters a scratch buffer or notification log.  A migrated integration "
   "should centralize that binding in a small call boundary and put preserved "
   "legacy output in a function ending in =-compatibility=.  The source audit "
   "rejects direct icon calls elsewhere in migrated modules.\n\n"
   "A module may register a read-only fragment for compatibility defaults, "
   "but the fragment still matches semantic facts and emits modality.  Keep "
   "meaning in the registry and presentation in rules.  Preserve established "
   "output during migration, add facts around it, and let users override the "
   "new facts.  Add new core semantics only when their intent is shared; use "
   "a module-owned identifier for genuinely private meaning.\n\n"
   "A module or third-party extension may also register optional, read-only "
   "feature fragments, presented to users as presentation options.  Supply a "
   "=:collection= symbol to group related options under the integration that "
   "owns them.  Use a broader collection when an option intentionally spans "
   "several integrations.  Collection membership never changes rule matching "
   "or cascade order; enabled precedence is controlled separately.  Providers "
   "may call =emacsvox-aural-register-feature-fragment-example= after the "
   "option is registered.  Name the exact option rule demonstrated and supply "
   "a short summary plus data-only =:facts= and =:context=.  Registration "
   "normalizes the input and rejects examples that do not match their named "
   "rule.  Curated examples are runtime provider metadata, not persistent "
   "personal data.  Preview derives a representative simulation for each "
   "enabled rule not covered by a curated example.\n\n"
   "Repository data-only providers use the flat library name "
   "=emacsvox-aural-provider-SCOPE.el=.  A provider may register semantic "
   "metadata and presentation data, but must not load its external package, "
   "inspect live buffers, install package hooks or advice, or speak.  The "
   "corresponding =emacsvox-SCOPE.el= integration requires the provider and "
   "owns live fact capture and feedback.  Cross-integration definitions use a "
   "descriptive shared scope such as =workflows=.\n\n"
   "Extension checklist:\n\n"
   "1. Search the registry for an existing intent and reuse it when exact.\n"
   "2. Register new metadata before a saved scheme could reference it.\n"
   "3. Emit facts and source context without choosing a resource.\n"
   "4. Add compatibility presentation separately when old output must remain.\n"
   "5. Test facts, context, ordering, face fallback, and a user override.\n"
   "6. Run =make aural-reference= and =make aural-audit=.\n\n"))

(defun emacsvox-aural-audit--insert-semantics ()
  "Insert generated semantic and occasion tables at point."
  (insert
   "* Semantic Registry\n\n"
   (format
    "Operational semantic contract version: =%d=.\n\n"
    emacsvox-aural-semantic-schema-version))
  (emacsvox-aural-audit--insert-table
   '("Identifier" "Kind" "Owner" "Value" "Roles" "Attributes" "States"
     "Events" "Occasions" "Phases" "Fallback" "Intent")
   (mapcar
    (lambda (record)
      (list
       (emacsvox-aural-semantic-id record)
       (emacsvox-aural-semantic-kind record)
       (emacsvox-aural-semantic-owner record)
       (or
        (emacsvox-aural-semantic-allowed-values record)
        (emacsvox-aural-semantic-value-type record))
       (emacsvox-aural-semantic-roles record)
       (emacsvox-aural-semantic-attributes record)
       (emacsvox-aural-semantic-states record)
       (emacsvox-aural-semantic-events record)
       (emacsvox-aural-semantic-occasions record)
       (emacsvox-aural-semantic-phases record)
       (emacsvox-aural-semantic-fallback record)
       (emacsvox-aural-semantic-summary record)))
    (emacsvox-aural-semantics)))
  (insert "** Stable Semantic Aliases\n\n")
  (emacsvox-aural-audit--insert-table
   '("Deprecated identifier" "Canonical identifier" "Owner"
     "Since contract version" "Migration note")
   (mapcar
    (lambda (record)
      (list
       (emacsvox-aural-semantic-alias-id record)
       (emacsvox-aural-canonical-semantic-id
        (emacsvox-aural-semantic-alias-id record))
       (emacsvox-aural-semantic-alias-owner record)
       (emacsvox-aural-semantic-alias-since-version record)
       (emacsvox-aural-semantic-alias-summary record)))
    (emacsvox-aural-semantic-aliases)))
  (insert "** Presentation Occasions\n\n")
  (emacsvox-aural-audit--insert-table
   '("Identifier" "Owner" "Intent")
   (mapcar
    (lambda (record)
      (list
       (emacsvox-aural-occasion-id record)
       (emacsvox-aural-occasion-owner record)
       (emacsvox-aural-occasion-summary record)))
    (emacsvox-aural-occasions))))

(defun emacsvox-aural-audit--built-in-schemes ()
  "Return built-in scheme entries sorted by identifier."
  (let (entries)
    (maphash
     (lambda (_ entry)
       (when (emacsvox-aural-scheme-entry-built-in entry)
         (push entry entries)))
     emacsvox-aural-scheme-registry)
    (sort
     entries
     (lambda (left right)
       (emacsvox-aural-audit--symbol-less-p
        (emacsvox-aural-scheme-entry-id left)
        (emacsvox-aural-scheme-entry-id right))))))

(defun emacsvox-aural-audit--module-fragments ()
  "Return module fragments sorted by identifier."
  (emacsvox-aural-audit--hash-records
   emacsvox-aural-module-fragment-registry
   #'emacsvox-aural-module-fragment-id))

(defun emacsvox-aural-audit--built-in-feature-fragments ()
  "Return built-in feature-fragment entries sorted by identifier."
  (cl-remove-if-not
   #'emacsvox-aural-feature-fragment-entry-built-in
   (emacsvox-aural-audit--hash-records
    emacsvox-aural-feature-fragment-registry
    #'emacsvox-aural-feature-fragment-entry-id)))

(defun emacsvox-aural-audit--insert-schemes ()
  "Insert generated scheme and fragment tables at point."
  (insert "* Built-in Schemes\n\n")
  (emacsvox-aural-audit--insert-table
   '("Identifier" "Parent" "Sound Pack" "Voice Palette" "Rules" "Intent")
   (mapcar
    (lambda (entry)
      (let ((scheme (emacsvox-aural-scheme-entry-compiled entry)))
        (list
         (emacsvox-aural-scheme-entry-id entry)
         (emacsvox-aural-scheme-parent scheme)
         (emacsvox-aural-effective-scheme-provider
          'resource-pack (emacsvox-aural-scheme-entry-id entry))
         (emacsvox-aural-effective-scheme-provider
          'voice-palette (emacsvox-aural-scheme-entry-id entry))
         (length (emacsvox-aural-scheme-rules scheme))
         (emacsvox-aural-scheme-summary scheme))))
    (emacsvox-aural-audit--built-in-schemes)))
  (insert "** Built-in Feature Fragments\n\n")
  (emacsvox-aural-audit--insert-table
   '("Identifier" "Collection" "Rules" "Curated Examples" "Source" "Intent")
   (mapcar
    (lambda (entry)
      (let ((scheme
             (emacsvox-aural-feature-fragment-entry-compiled entry)))
        (list
         (emacsvox-aural-feature-fragment-entry-id entry)
         (emacsvox-aural-feature-fragment-collection entry)
         (length (emacsvox-aural-scheme-rules scheme))
         (length
          (emacsvox-aural-feature-fragment-examples
           (emacsvox-aural-feature-fragment-entry-id entry)))
         (emacsvox-aural-feature-fragment-entry-source entry)
         (emacsvox-aural-scheme-summary scheme))))
    (emacsvox-aural-audit--built-in-feature-fragments)))
  (insert "** Module Compatibility Fragments\n\n")
  (emacsvox-aural-audit--insert-table
   '("Identifier" "Module" "Rules" "Source" "Intent")
   (mapcar
    (lambda (fragment)
      (let ((scheme (emacsvox-aural-module-fragment-compiled fragment)))
        (list
         (emacsvox-aural-module-fragment-id fragment)
         (emacsvox-aural-module-fragment-module fragment)
         (length (emacsvox-aural-scheme-rules scheme))
         (emacsvox-aural-module-fragment-source fragment)
         (emacsvox-aural-scheme-summary scheme))))
    (emacsvox-aural-audit--module-fragments))))

(defun emacsvox-aural-audit--insert-sound-packs (root)
  "Insert sound-pack author guidance and generated tables for ROOT."
  (insert
   "* Sound Pack Author Reference\n\n"
   "Register a cue with intent before adding an asset.  Register a pack with "
   "an identifier, summary, =sound= or =prompt= kind, directory, optional "
   "parent, requirement profiles, and default spatialization.  File basenames "
   "are cue identifiers.  Unknown files fail audit; missing required cues fail "
   "pack validation.  Every standalone sound pack must resolve =button=.  "
   "Use a parent for deliberate fallback.\n\n"
   "Bundled packs live below =sounds/packs/=.  Personal packs live below "
   "=~/.emacsvox/sounds/packs/= by default; customize "
   "=emacsvox-aural-personal-sound-packs-directory= to use another root.  "
   "Immediate subdirectories containing =button.ogg= are discovered "
   "automatically.  Direct =sounds/PACK/= children remain a deprecated, "
   "lowest-precedence compatibility source.  A partial pack without "
   "=button.ogg= can opt in with a data-only =emacsvox-sound-pack.el= "
   "manifest containing =:schema-version 1= and optional =:summary=, "
   "=:parent=, =:profiles=, and =:default-spatialization= fields.  Discovery "
   "runs before pack completion and selection; "
   "=M-x emacsvox-aural-refresh-discovered-resource-packs= forces it "
   "explicitly.  Call =emacsvox-aural-refresh-resource-pack= after changing "
   "files in an already selected pack.\n\n"
   "Use =M-x emacsvox-aural-list-sound-packs= for the spoken workbench.  "
   "It can rescan, validate, activate, audition, open the pack directory, "
   "browse cue intent and provenance, and guidedly edit manifests belonging "
   "to discovered packs.  Registered built-in metadata remains read-only.  "
   "Manifest replacement is atomic, retains the previous file as =~=, and "
   "rolls back when refreshed metadata cannot be validated.\n\n"
   "Default spatialization is =neutral=, =stereo=, or =pre-spatialized=.  Mark "
   "HRTF or otherwise positioned assets =pre-spatialized= so runtime balance "
   "does not position them again.\n\n"
   "** Registered Packs\n\n")
  (emacsvox-aural-audit--insert-table
   '("Identifier" "Kind" "Parent" "Profiles" "Spatial" "Assets" "Directory"
     "Intent")
   (mapcar
    (lambda (pack)
      (list
       (emacsvox-aural-resource-pack-id pack)
       (emacsvox-aural-resource-pack-kind pack)
       (emacsvox-aural-resource-pack-parent pack)
       (emacsvox-aural-resource-pack-profiles pack)
       (emacsvox-aural-resource-pack-default-spatialization pack)
       (hash-table-count (emacsvox-aural-resource-pack-assets pack))
       (directory-file-name
        (file-relative-name
         (emacsvox-aural-resource-pack-directory pack) root))
       (emacsvox-aural-resource-pack-summary pack)))
    (seq-remove
     (lambda (pack)
       (eq
        (emacsvox-aural-resource-pack-origin pack)
        'discovered))
     (emacsvox-aural-audit--hash-records
      emacsvox-aural-resource-pack-registry
      #'emacsvox-aural-resource-pack-id))))
  (insert "** Registered Cues\n\n")
  (emacsvox-aural-audit--insert-table
   '("Identifier" "Kind" "Owner" "Fallback" "Intent")
   (mapcar
    (lambda (cue)
      (list
       (emacsvox-aural-cue-id cue)
       (emacsvox-aural-cue-kind cue)
       (emacsvox-aural-cue-owner cue)
       (emacsvox-aural-cue-fallback cue)
       (emacsvox-aural-cue-summary cue)))
    (emacsvox-aural-audit--hash-records
     emacsvox-aural-cue-registry
     #'emacsvox-aural-cue-id))))

(defun emacsvox-aural-audit--insert-voice-palettes ()
  "Insert voice-palette author guidance and generated tables at point."
  (insert
   "* Voice Palette Author Reference\n\n"
   "A palette maps stable scheme voice names to either device-independent "
   "Emacsvox personality symbols or declarative ACSS style data.  Schemes "
   "should name palette entries such as =bolden= instead of backend commands.  "
   "A palette may inherit another palette and override selected names.  Raw "
   "ACSS remains valid for a rule that deliberately needs a generated voice."
   "\n\n"
   "The ACSS =:family= dimension selects a base voice.  =male=, =female=, and "
   "=child= are portable requests: they resolve again through the active "
   "speech adapter whenever the style is compiled.  Adapter-specific names "
   "such as =outloud-v2= or =betty= request one exact synth voice.  If that "
   "exact voice is unavailable after changing synth, Emacsvox applies the new "
   "adapter default and reports an =unavailable-voice-family= degradation; it "
   "does not silently reinterpret the identifier.\n\n"
   "Each adapter publishes whether family selection is enumerated, free-form, "
   "or unsupported, together with available families, portable traits, "
   "supported normalized dimensions, and parameter ranges.  Outloud exposes "
   "its eight Eloquence presets, DECtalk exposes its nine built-ins, Mac and "
   "SwiftMac accept installed voice names, and eSpeak currently performs "
   "voice selection through its language interface rather than inline ACSS.  "
   "Catalogues are static today; the function-valued capability interface "
   "allows later discovery when a speech-server response channel exists."
   "\n\n"
   "Numeric ACSS dimensions remain normalized from zero through nine and are "
   "applied only when explicitly requested.  For Eloquence and DECtalk "
   "non-default base voices, current numeric overrides reuse the established "
   "Paul calibration tables; omitted dimensions preserve the native preset's "
   "own characteristics.\n\n")
  (dolist
      (palette
       (emacsvox-aural-audit--hash-records
        emacsvox-aural-voice-palette-registry
        #'emacsvox-aural-voice-palette-id))
    (insert
     "** "
     (symbol-name (emacsvox-aural-voice-palette-id palette))
     "\n\n"
     (emacsvox-aural-voice-palette-summary palette)
     "\n\n")
    (when-let* ((parent (emacsvox-aural-voice-palette-parent palette)))
      (insert "Parent: =" (symbol-name parent) "=\n\n"))
    (emacsvox-aural-audit--insert-table
     '("Scheme Voice" "Personality")
     (mapcar
      (lambda (entry) (list (car entry) (cdr entry)))
      (sort
       (copy-tree
        (emacsvox-aural-effective-voice-entries
         (emacsvox-aural-voice-palette-id palette)))
       (lambda (left right)
         (emacsvox-aural-audit--symbol-less-p
          (car left) (car right))))))))

(defun emacsvox-aural-audit--insert-migration ()
  "Insert compatibility migration and rollout guidance at point."
  (insert
   "* Compatibility, Migration, and Rollout\n\n"
   "Existing direct =emacsvox-icon= calls, queued =auditory-icon= properties, "
   "=personality= properties, face-to-voice mappings, sound directories, and "
   "backend choices remain supported inputs.  They are compatibility "
   "presentation hints, not semantic identity.  If no semantic rule replaces "
   "or clears an existing voice or cue, the old presentation remains.\n\n"
   "To migrate a direct icon path, first characterize its text, cue, and order. "
   "Register or reuse the intent, bind semantic facts and source context "
   "around the unchanged call, then add an optional compatibility fragment "
   "only if the old output must be expressed as a rule.  Do not replace cue "
   "symbols with file paths and do not queue unresolved semantic names.\n\n"
   "To migrate styled text, keep existing =personality= or face properties "
   "while adding semantic fact properties.  A semantic scheme can then "
   "override the voice for one module, mode, derived mode, or buffer.  Voice "
   "Lock controls only the legacy personality voice fallback; it does not "
   "disable semantic rules or explicit face rules.  A "
   "=:legacy-face= compatibility selector can deliberately match one named "
   "visual face when no semantic intent is available.  It can add before or "
   "after cues and select a palette voice, and can be scoped by module, mode, "
   "occasion, or buffer like any other rule.  This is a presentation fallback, "
   "not semantic identity.  Users can disable every explicit face rule with "
   "=emacsvox-aural-face-presentation-enabled= or its spoken toggle while "
   "leaving semantic presentation and Voice Lock unchanged.\n\n"
   "#+begin_src emacs-lisp\n"
   "(:id warning-face-presentation\n"
   " :match (:legacy-face font-lock-warning-face\n"
   "         :mode emacs-lisp-mode :occasion navigation)\n"
   " :render\n"
   " (:before\n"
   "  (:append ((:id warning-cue :kind cue :cue warn-user)))\n"
   "  :content (:voice bolden)))\n"
   "#+end_src\n\n"
   "A text run may carry an ordered list of named faces.  Every matching face "
   "rule participates in normal rule composition, so append or prepend "
   "operations can accumulate cues.  The first, strongest Emacs face wins a "
   "tie between face-only scalar settings such as content voice.  Semantic "
   "identity remains stronger within the same rule origin, while stronger "
   "user, session, and buffer origins can intentionally override module "
   "defaults.  Source overlay faces are snapshotted strongest-first before "
   "copying, followed by explicit =face= and =font-lock-face= text names.  "
   "String face names are normalized to their existing face symbols, and "
   "anonymous faces contribute only explicit named =:inherit= values.  "
   "Module speech paths should copy styled ranges with "
   "=emacsvox-aural-source-substring= so heard output and point explanation "
   "share this snapshot.\n\n"
   "Agent Shell, Markdown, Org, Notmuch, Gnus, Dired, and Magit now attach "
   "registered conversation, document, organizer, message, filesystem, and "
   "version-control facts around their established feedback.  Their speech "
   "and cue order remains unchanged unless a scheme or fragment matches the "
   "new facts.  Optional fragments demonstrate customization without "
   "requiring the corresponding third-party package at startup.\n\n"
   "Rollout is deliberately staged.  The default scheme is compatibility "
   "preserving, the Org variants are selectable examples, and integrations "
   "move in small tested batches.  Critical alerts currently follow the same "
   "explicit suppression contract as other actions; deployments that require "
   "a mandatory alternative should enforce that policy in a site scheme until "
   "a shared critical-alert contract is registered.\n\n"
   "* Maintenance\n\n"
   "Run =make aural-reference= after changing a registry or this generator.  "
   "Run =make aural-audit= to validate registry cross-references, every "
   "registered pack and built-in scheme, literal cue calls, voice palettes, "
   "semantic icon boundaries in migrated modules, and this generated file.  "
   "=utils/count-icons.pl= remains a historical text counter; the "
   "registry-aware audit is authoritative.\n"))

(defun emacsvox-aural-reference-string (&optional root)
  "Return the generated aural author reference for repository ROOT."
  (let ((root (emacsvox-aural-audit--root root)))
    (with-temp-buffer
      (insert
       "#+title: Emacsvox Aural Presentation Reference\n"
       "#+author: Emacsvox Contributors\n"
       "#+options: toc:3\n\n"
       "# This file is generated by utils/emacsvox-aural-audit.el.\n"
       "# Do not edit it directly; run make aural-reference.\n\n")
      (emacsvox-aural-audit--insert-overview)
      (emacsvox-aural-audit--insert-scheme-author-reference)
      (emacsvox-aural-audit--insert-module-author-reference)
      (emacsvox-aural-audit--insert-semantics)
      (emacsvox-aural-audit--insert-schemes)
      (emacsvox-aural-audit--insert-sound-packs root)
      (emacsvox-aural-audit--insert-voice-palettes)
      (emacsvox-aural-audit--insert-migration)
      (buffer-string))))

(defun emacsvox-aural-write-reference (&optional root file)
  "Atomically write the generated reference for ROOT to FILE.

FILE defaults to `emacsvox-aural-audit-reference-file' below ROOT."
  (interactive)
  (let* ((root (emacsvox-aural-audit--root root))
         (file
          (expand-file-name
           (or file emacsvox-aural-audit-reference-file) root))
         (directory (file-name-directory file))
         (temporary (make-temp-file
                     (expand-file-name ".aural-reference-" directory))))
    (unwind-protect
        (progn
          (with-temp-buffer
            (insert (emacsvox-aural-reference-string root))
            (write-region (point-min) (point-max) temporary nil 'silent))
          (set-file-modes temporary #o644)
          (rename-file temporary file t)
          (setq temporary nil))
      (when (and temporary (file-exists-p temporary))
        (delete-file temporary)))
    file))

(defun emacsvox-aural-reference-current-p (&optional root file)
  "Return non-nil when generated FILE is current for repository ROOT."
  (let* ((root (emacsvox-aural-audit--root root))
         (file
          (expand-file-name
           (or file emacsvox-aural-audit-reference-file) root)))
    (and
     (file-readable-p file)
     (with-temp-buffer
       (insert-file-contents file)
       (string= (buffer-string)
                (emacsvox-aural-reference-string root))))))

(defun emacsvox-aural-audit-directory (&optional root)
  "Audit aural registries, source cues, and generated docs below ROOT."
  (let* ((root (emacsvox-aural-audit--root root))
         (source (emacsvox-aural-audit-source-cues root))
         (usage (plist-get source :usage))
         (context-free-icons
          (emacsvox-aural-audit-context-free-icons root))
         unknown
         errors)
    (dolist (entry usage)
      (unless (emacsvox-aural-cue (car entry))
        (push entry unknown)))
    (cl-labels
        ((capture
          (label thunk)
          (condition-case error
              (funcall thunk)
            (error
             (push
              (format "%s: %s" label (error-message-string error))
              errors)))))
      (capture "Semantic registry" #'emacsvox-aural-validate-registry)
      (capture "Resource registry"
               #'emacsvox-aural-validate-resource-registry)
      (capture "Scheme registry"
               #'emacsvox-aural-validate-scheme-registry)
      (dolist
          (pack
           (emacsvox-aural-audit--hash-records
            emacsvox-aural-resource-pack-registry
            #'emacsvox-aural-resource-pack-id))
        (capture
         (format "Resource pack %s"
                 (emacsvox-aural-resource-pack-id pack))
         (lambda ()
           (let ((report
                  (emacsvox-aural-validate-resource-pack
                   (emacsvox-aural-resource-pack-id pack))))
             (unless (emacsvox-aural-resource-report-valid report)
               (error
                "Missing=%S unknown=%S directory-missing=%S"
                (emacsvox-aural-resource-report-missing-required report)
                (emacsvox-aural-resource-report-unknown-assets report)
                (emacsvox-aural-resource-report-missing-directory
                 report)))))))
      (dolist (entry (emacsvox-aural-audit--built-in-schemes))
        (let* ((id (emacsvox-aural-scheme-entry-id entry))
               (report (emacsvox-aural-validate-scheme id)))
          (unless (emacsvox-aural-validation-report-valid report)
            (push
             (format
              "Scheme %s: %s"
              id
              (string-join
               (emacsvox-aural-validation-report-errors report)
               "; "))
             errors))))
      ;; Registration and resource-registry validation guarantee palette
      ;; entry shape and inheritance without requiring a live TTS adapter.
    (list
     :root root
     :usage usage
     :literal-count (plist-get source :literal-count)
     :dynamic-count (plist-get source :dynamic-count)
     :unknown-cues (nreverse unknown)
     :context-free-icons context-free-icons
     :parse-errors (plist-get source :parse-errors)
     :errors (nreverse errors)
     :reference-current (emacsvox-aural-reference-current-p root)))))

(defun emacsvox-aural-audit-clean-p (audit)
  "Return non-nil when AUDIT found no contract or documentation failures."
  (and
   (null (plist-get audit :unknown-cues))
   (null (plist-get audit :context-free-icons))
   (null (plist-get audit :parse-errors))
   (null (plist-get audit :errors))
   (plist-get audit :reference-current)))

(defun emacsvox-aural-audit-format (audit)
  "Return deterministic human-readable output for AUDIT."
  (let* ((usage (plist-get audit :usage))
         (used (length usage))
         (registered (hash-table-count emacsvox-aural-cue-registry)))
    (concat
     (format
      "Aural audit: %d literal cue calls, %d dynamic calls, %d/%d registered cues used\n"
      (plist-get audit :literal-count)
      (plist-get audit :dynamic-count)
      used
      registered)
     (mapconcat
      (lambda (entry)
        (format
         "  %s: %d\n"
         (car entry)
         (plist-get (cdr entry) :count)))
      (sort
       (copy-tree usage)
       (lambda (left right)
         (let ((left-count (plist-get (cdr left) :count))
               (right-count (plist-get (cdr right) :count)))
           (if (= left-count right-count)
               (emacsvox-aural-audit--symbol-less-p
                (car left) (car right))
             (< left-count right-count)))))
      "")
     (mapconcat
      (lambda (entry)
        (format
         "Unknown literal cue %s in %s\n"
         (car entry)
         (string-join (plist-get (cdr entry) :files) ", ")))
      (plist-get audit :unknown-cues)
      "")
     (mapconcat
      (lambda (failure)
        (format
         "Context-free icon call %s in %s%s%s\n"
         (plist-get failure :icon-function)
         (plist-get failure :file)
         (if-let* ((function (plist-get failure :function)))
             (format " (%s)" function)
           "")
         (if-let* ((adapter
                    (plist-get failure :compatibility-function)))
             (format " via %s" adapter)
           "")))
      (plist-get audit :context-free-icons)
      "")
     (mapconcat
      (lambda (error) (concat "Source parse error: " error "\n"))
      (plist-get audit :parse-errors)
      "")
     (mapconcat
      (lambda (error) (concat "Validation error: " error "\n"))
      (plist-get audit :errors)
      "")
     (format
      "Generated reference: %s\n"
      (if (plist-get audit :reference-current) "current" "stale or missing")))))

(defun emacsvox-aural-audit-batch (&optional root)
  "Audit repository ROOT, print the report, and fail batch Emacs if dirty."
  (let ((audit (emacsvox-aural-audit-directory root)))
    (princ (emacsvox-aural-audit-format audit))
    (unless (emacsvox-aural-audit-clean-p audit)
      (kill-emacs 1))
    audit))

(provide 'emacsvox-aural-audit)
;;; emacsvox-aural-audit.el ends here
