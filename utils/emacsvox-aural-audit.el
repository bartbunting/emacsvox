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
(require 'emacsvox-aural-org)
(require 'emacsvox-aural-representative)

(defconst emacsvox-aural-audit-icon-functions
  '(emacsvox-icon emacsvox-queue-icon)
  "Functions whose literal cue arguments are included in the source audit.")

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
   "Use =M-x emacsvox-list-aural-schemes= to browse schemes, "
   "=M-x emacsvox-set-aural-scheme= to select one, and "
   "=M-x emacsvox-reset-aural-scheme= to return to the default.\n\n"
   "Use =M-x emacsvox-edit-aural-scheme= for a spoken field editor over a "
   "persistent personal scheme.  It can create a flattened editable copy of "
   "a built-in scheme.  Use =M-x emacsvox-edit-aural-scheme-advanced= for "
   "the declarative rule view, or =M-x emacsvox-edit-aural-rules= for "
   "persistent, session, or buffer-local rules.  "
   "=M-x emacsvox-explain-aural-presentation= shows "
   "facts, context, matching rules, provenance, concrete resources, "
   "suppression, and backend degradation at point.  It automatically chooses "
   "the occasion with the most matching rules, speaks a concise description "
   "of the resolved order, and retains detailed output in a Help buffer.  "
   "Use a prefix argument to choose the occasion explicitly.\n\n"
   "** Cascade and Deterministic Selection\n\n"
   "Matching rules are applied from weaker to stronger.  Origin layers are "
   "=core=, module fragments, the active inherited scheme, persistent user "
   "rules, session rules, and buffer rules.  Within an origin, semantic "
   "identity, an exact combined module/mode match, exact or nearest derived "
   "mode, module, additional constraints, inheritance layer, and explicit "
   "rule order determine specificity.  A stable rule identifier breaks a "
   "remaining true tie, so hash and registration order cannot change output.\n\n"
   "A buffer rule can therefore override one module in one buffer without "
   "changing the same semantic in other buffers.  A mode selector also "
   "matches derived modes, with the nearest ancestor winning.  Combine "
   "=:module= and =:mode= when the same mode should sound different in one "
   "integration.\n\n"
   "** Render and Queue Contract\n\n"
   "Each plan has ordered =before= actions, one styled =content= action, and "
   "ordered =after= actions.  Speech, cue, and pause actions may be added.  "
   "Phase operators are =:prepend=, =:append=, =:replace=, =:remove=, and "
   "=:suppress=.  Content independently controls =:speak=, =:voice=, "
   "=:volume=, =:space=, and =:suppress=; the strongest rule that sets a "
   "scalar wins.\n\n"
   "Semantic and contextual resolution happens in Emacs at the source "
   "submission boundary.  Cue names become concrete files or sample IDs, "
   "voices become adapter commands, and spatial requests become backend "
   "values before anything is queued.  The speech server never resolves "
   "schemes, modes, modules, semantics, or resource fallbacks.  A complete "
   "multi-action plan uses one strict queue.  Only a standalone compatibility "
   "cue may use the selected local player.\n\n"
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
   "declarative Lisp data read with evaluation disabled.  Prefer the "
   "accessible editor; if data is authored directly, retain the outer "
   "=:schema-version=, =:schemes=, and =:user-rules= fields.\n\n"
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
   "    (:append ((:id heading-label :kind speech :text \"Heading 1\")))\n"
   "    :content (:voice bolden :space (:balance -0.2))\n"
   "    :after\n"
   "    (:append ((:id heading-end :kind cue :cue section)))))))\n"
   "#+end_src\n\n"
   "Selectors use =:role=, =:event= or =:events=, =:state= or =:states=, "
   "registered attribute keywords, =:module=, =:mode=, =:occasion=, "
   "=:legacy-cue=, and =:legacy-personality=.  Unknown semantics, attributes, "
   "cues, voices, providers, fields, or schema versions fail validation.\n\n"
   "Ordered actions require an =:id= and =:kind=.  A speech action supplies "
   "=:text= and may supply =:voice=, =:volume=, and =:space=.  A cue action "
   "supplies a registered =:cue= and may supply =:volume= and =:space=.  A "
   "pause supplies a nonnegative =:duration=.  Action IDs are the handles "
   "used by later =:remove= operations.\n\n"))

(defun emacsvox-aural-audit--insert-module-author-reference ()
  "Insert the integration module-author reference at point."
  (insert
   "* Module Author Reference\n\n"
   "Register meaning before emitting it.  A semantic registration supplies a "
   "unique identifier, =:kind= (=role=, =event=, =state=, or =attribute=), "
   "intent summary, owner, and any value, occasion, phase, fallback, or usage "
   "contract.  Do not use a visual face, voice name, cue name, or file name as "
   "semantic identity.\n\n"
   "#+begin_src emacs-lisp\n"
   "(emacsvox-aural-register-semantic\n"
   " 'diagnostic\n"
   " :kind 'role\n"
   " :summary \"A source diagnostic\"\n"
   " :owner 'example-module\n"
   " :occasions '(navigation continuous)\n"
   " :phases '(before content after))\n"
   "#+end_src\n\n"
   "For persistent formatted text, attach =emacsvox-aural-facts= and "
   "=emacsvox-aural-module= text properties.  For transient output, bind "
   "=emacsvox-aural-submission-facts=, "
   "=emacsvox-aural-submission-context=, "
   "=emacsvox-aural-submission-module=, and "
   "=emacsvox-aural-submission-occasion= around the existing =tts-speak= or "
   "=emacsvox-icon= call.  Capture context in the source buffer before text "
   "enters a scratch buffer or notification log.\n\n"
   "A module may register a read-only fragment for compatibility defaults, "
   "but the fragment still matches semantic facts and emits modality.  Keep "
   "meaning in the registry and presentation in rules.  Preserve established "
   "output during migration, add facts around it, and let users override the "
   "new facts.  Add new core semantics only when their intent is shared; use "
   "a module-owned identifier for genuinely private meaning.\n\n"
   "Extension checklist:\n\n"
   "1. Search the registry for an existing intent and reuse it when exact.\n"
   "2. Register new metadata before a saved scheme could reference it.\n"
   "3. Emit facts and source context without choosing a resource.\n"
   "4. Add compatibility presentation separately when old output must remain.\n"
   "5. Test facts, context, ordering, face fallback, and a user override.\n"
   "6. Run =make aural-reference= and =make aural-audit=.\n\n"))

(defun emacsvox-aural-audit--insert-semantics ()
  "Insert generated semantic and occasion tables at point."
  (insert "* Semantic Registry\n\n")
  (emacsvox-aural-audit--insert-table
   '("Identifier" "Kind" "Owner" "Value" "Occasions" "Phases" "Intent")
   (mapcar
    (lambda (record)
      (list
       (emacsvox-aural-semantic-id record)
       (emacsvox-aural-semantic-kind record)
       (emacsvox-aural-semantic-owner record)
       (or
        (emacsvox-aural-semantic-allowed-values record)
        (emacsvox-aural-semantic-value-type record))
       (emacsvox-aural-semantic-occasions record)
       (emacsvox-aural-semantic-phases record)
       (emacsvox-aural-semantic-summary record)))
    (emacsvox-aural-semantics)))
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

(defun emacsvox-aural-audit--insert-schemes ()
  "Insert generated scheme and module-fragment tables at point."
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
   "Use a parent for deliberate fallback and call "
   "=emacsvox-aural-refresh-resource-pack= after changing files in a live "
   "session.\n\n"
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
    (emacsvox-aural-audit--hash-records
     emacsvox-aural-resource-pack-registry
     #'emacsvox-aural-resource-pack-id)))
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
   "A palette maps stable scheme voice names to device-independent Emacsvox "
   "personality symbols.  Schemes should name palette entries such as "
   "=bolden= instead of backend commands.  A palette may inherit another "
   "palette and override selected names.  Raw ACSS remains valid for a rule "
   "that deliberately needs a generated voice.\n\n")
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
   "override the voice for one module, mode, derived mode, or buffer; without "
   "such a rule, normal Voice Lock behavior remains authoritative.\n\n"
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
   "and this generated file.  =utils/count-icons.pl= remains a historical "
   "text counter; the registry-aware audit is authoritative.\n"))

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
     :parse-errors (plist-get source :parse-errors)
     :errors (nreverse errors)
     :reference-current (emacsvox-aural-reference-current-p root)))))

(defun emacsvox-aural-audit-clean-p (audit)
  "Return non-nil when AUDIT found no contract or documentation failures."
  (and
   (null (plist-get audit :unknown-cues))
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
