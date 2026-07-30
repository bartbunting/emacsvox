;;; emacsvox-magit-tests.el --- Magit advice tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'package)
(package-initialize)
(require 'magit)
(require 'magit-blame)
(require 'magit-files)
(require 'magit-repos)
(require 'git-commit)
(require 'git-rebase)

(load
 (expand-file-name
  "../lisp/emacsvox-magit.el"
  (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-magit-current-targets-exist ()
  "Every retained Magit advice target exists."
  (dolist (target emacsvox-magit--simple-advice-targets)
    (should (fboundp target)))
  (dolist (target emacsvox-magit--section-movement-targets)
    (should (fboundp target)))
  (should (fboundp 'magit-diff-show-or-scroll-up))
  (dolist
      (target
       (append
        (mapcar #'car emacsvox-magit--rebase-action-targets)
        (mapcar #'car emacsvox-magit--rebase-view-targets)
        '(git-rebase-backward-line forward-line)))
    (should (fboundp target))))

(ert-deftest emacsvox-magit-repository-list-command-surface-is-covered ()
  "Every current repository-list command has dedicated feedback."
  (should (= (length emacsvox-magit--repolist-around-advice) 4))
  (should (= (length emacsvox-magit--repolist-after-advice) 3))
  (dolist
      (entry
       (append
        emacsvox-magit--repolist-around-advice
        emacsvox-magit--repolist-after-advice))
    (pcase-let ((`(,target ,function) entry))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-magit-repository-tag-reports-object-and-next-focus ()
  "Marking a repository reports its identity and the newly focused row."
  (with-temp-buffer
    (insert "first repository\nsecond repository")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'magit-repolist-mark)
          calls)
      (cl-letf
          (((symbol-function 'tabulated-list-get-id)
            (lambda () "/src/first/"))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push (cons content arguments) calls))))
        (should
         (eq
          (emacsvox--advice-magit-repolist-mark-around
           (lambda ()
             (forward-line 1)
             'marked))
          'marked)))
      (pcase-let* ((`((,content . ,arguments)) calls)
                   (actions
                    (plist-get arguments :compatibility-actions)))
        (should
         (equal
          content
          "Marked first. second repository"))
        (should
         (equal
          (plist-get arguments :facts)
          '(:role vcs-repository :vcs-operation mark
            :events (entry-marked))))
        (should (eq (plist-get arguments :occasion) 'state-change))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-value actions)
          '(mark-object)))))))

(ert-deftest emacsvox-magit-repository-tag-is-silent-programmatically ()
  "Programmatic repository tagging preserves behavior without feedback."
  (let ((calls 0)
        (ems--interactive-fn-name nil))
    (cl-letf
        (((symbol-function 'emacsvox-magit--submit-text)
          (lambda (&rest _) (ert-fail "Programmatic tag produced feedback"))))
      (should
       (eq
        (emacsvox--advice-magit-repolist-unmark-around
         (lambda () (cl-incf calls) 'unmarked))
        'unmarked)))
    (should (= calls 1))))

(ert-deftest emacsvox-magit-repository-fetch-has-aggregate-lifecycle ()
  "Repository fetch reports one aggregate start and completion."
  (let ((ems--interactive-fn-name 'magit-repolist-fetch)
        calls)
    (cl-letf
        (((symbol-function 'emacsvox-magit--submit-text)
          (lambda (&rest arguments) (push arguments calls))))
      (should
       (eq
        (emacsvox--advice-magit-repolist-fetch-around
         (lambda (repositories)
           (should (equal repositories '("one" "two")))
           'fetched)
        '("one" "two"))
        'fetched)))
    (setq calls (nreverse calls))
    (should
     (equal
      (mapcar #'car calls)
      '("Fetching 2 repositories"
        "Fetched 2 repositories")))
    (should
     (equal
      (nth 1 (car calls))
      '(:role vcs-view :vcs-view-kind repositories
        :vcs-operation fetch)))))

(ert-deftest emacsvox-magit-repository-fetch-reports-and-resignals-failure ()
  "Repository fetch failure is announced and the original error is preserved."
  (let ((ems--interactive-fn-name 'magit-repolist-fetch)
        calls)
    (cl-letf
        (((symbol-function 'emacsvox-magit--submit-text)
          (lambda (&rest arguments) (push arguments calls))))
      (should-error
       (emacsvox--advice-magit-repolist-fetch-around
        (lambda (_repositories) (error "network unavailable"))
        'all)
       :type 'error))
    (setq calls (nreverse calls))
    (should
     (equal
      (mapcar #'car calls)
      '("Fetching all displayed repositories"
        "Failed to fetch all displayed repositories")))
    (should
     (equal
      (nth 1 (nth 1 calls))
      '(:role vcs-view :vcs-view-kind repositories
        :vcs-operation fetch :events (operation-failed))))))

(ert-deftest emacsvox-magit-commit-command-surface-is-covered ()
  "Every commit-specific command family has dedicated feedback."
  (should (= (length emacsvox-magit--commit-history-targets) 4))
  (should (= (length emacsvox-magit--commit-trailer-targets) 10))
  (should (= (length emacsvox-magit--commit-insertion-targets) 2))
  (should (= (length emacsvox-magit--commit-around-advice) 18))
  (should (= (length emacsvox-magit--commit-after-advice) 1))
  (dolist
      (entry
       (append
        emacsvox-magit--commit-around-advice
        emacsvox-magit--commit-after-advice))
    (pcase-let ((`(,target ,function) entry))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-magit-commit-content-preserves-faces-and-hides-comments ()
  "Commit feedback retains source faces but excludes Git instructions."
  (with-temp-buffer
    (setq comment-start "#")
    (insert
     (propertize "Summary" 'face 'git-commit-summary)
     "\n\nBody\n"
     "# Changes to be committed:\n# file")
    (let ((content (emacsvox-magit--commit-message-content)))
      (should (equal content "Summary\n\nBody"))
      (should
       (eq
        (get-text-property 0 'face content)
        'git-commit-summary)))))

(ert-deftest emacsvox-magit-commit-history-reports-restored-message ()
  "History navigation reports the operation and restored commit message."
  (with-temp-buffer
    (setq comment-start "#")
    (insert "old")
    (let ((ems--interactive-fn-name 'git-commit-prev-message)
          calls)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push (cons content arguments) calls))))
        (should
         (eq
          (emacsvox--advice-git-commit-prev-message-around
           (lambda (_count)
             (erase-buffer)
             (insert
              (propertize "restored" 'face 'git-commit-summary))
             'restored)
           1)
          'restored)))
      (pcase-let* ((`((,content . ,arguments)) calls)
                   (actions
                    (plist-get arguments :compatibility-actions)))
        (should (equal content "Previous message. restored"))
        (should
         (eq
          (get-text-property (length "Previous message. ") 'face content)
          'git-commit-summary))
        (should
         (equal
          (plist-get arguments :facts)
          '(:role vcs-commit-message
            :vcs-operation previous-message
            :events (focus-entered))))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-value actions)
          '(select-object)))))))

(ert-deftest emacsvox-magit-commit-history-no-op-is-accurate ()
  "Unavailable commit history is not announced as restored content."
  (with-temp-buffer
    (insert "unchanged")
    (let ((ems--interactive-fn-name 'git-commit-next-message)
          calls)
      (cl-letf
          (((symbol-function 'emacsvox-magit--submit-text)
            (lambda (&rest arguments) (push arguments calls))))
        (emacsvox--advice-git-commit-next-message-around
         (lambda (_count) 'empty)
         1))
      (should
       (equal
        calls
        '(("No next message available."
           (:role vcs-commit-message
            :vcs-operation next-message
            :events (operation-failed))
           navigation warn-user)))))))

(ert-deftest emacsvox-magit-commit-trailer-reports-inserted-identity ()
  "Trailer insertion reports its exact token and identity."
  (with-temp-buffer
    (insert "Summary")
    (let ((ems--interactive-fn-name 'git-commit-signoff)
          calls)
      (cl-letf
          (((symbol-function 'emacsvox-magit--submit-text)
            (lambda (&rest arguments) (push arguments calls))))
        (should
         (eq
          (emacsvox--advice-git-commit-signoff-around
           (lambda (_name _mail)
             (goto-char (point-max))
             (insert "\n\nSigned-off-by: Bart <bart@example.com>")
             'inserted)
           "Bart" "bart@example.com")
          'inserted)))
      (should
       (equal
        calls
        '(("Signed-off-by: Bart <bart@example.com>"
           (:role vcs-commit-message
            :vcs-operation signoff
            :events (operation-completed))
           edit open-object)))))))

(ert-deftest emacsvox-magit-commit-lifecycle-hooks-are-distinct ()
  "Commit start, confirmed finish, and cancel have separate feedback."
  (with-temp-buffer
    (setq git-commit-mode t)
    (let (calls)
      (cl-letf
          (((symbol-function 'emacsvox-magit--submit-text)
            (lambda (&rest arguments) (push arguments calls))))
        (emacsvox-magit-enable-commit-feedback)
        (should
         (memq
          #'emacsvox-magit--commit-finish-feedback
          git-commit-post-finish-hook))
        (should
         (memq
          #'emacsvox-magit--commit-cancel-feedback
          with-editor-post-cancel-hook))
        (let ((ems--interactive-fn-name 'with-editor-finish))
          (emacsvox-magit--commit-finish-feedback))
        (let ((ems--interactive-fn-name 'with-editor-cancel))
          (emacsvox-magit--commit-cancel-feedback)))
      (should
       (equal
        (mapcar #'car (nreverse calls))
        '("Editing Git commit message"
          "Created Git commit"
          "Canceled Git commit"))))))

(ert-deftest emacsvox-magit-end-to-end-vocabulary-is-registered ()
  "Every top-level Magit presentation category has registered intent."
  (dolist
      (id
       '(vcs-section vcs-view vcs-blame-chunk vcs-process
         vcs-rebase-entry vcs-commit-message vcs-repository
         section-kind vcs-view-kind vcs-operation vcs-rebase-action
         staged unstaged entry-staged entry-unstaged
         vcs-view-opened vcs-view-closed vcs-commit-displayed
         vcs-diff-scrolled))
    (should (emacsvox-aural-semantic id))))

(ert-deftest emacsvox-magit-all-interface-modes-own-semantic-context ()
  "Magit major and auxiliary modes should identify their aural module."
  (dolist
      (mode
       '(magit-status-mode magit-process-mode magit-refs-mode
         magit-repolist-mode git-rebase-mode))
    (with-temp-buffer
      (setq major-mode mode)
      (emacsvox-magit-enable-aural-context)
      (should (eq emacsvox-aural-module 'magit))))
  (with-temp-buffer
    (setq-local emacsvox-aural-module 'python)
    (setq magit-blame-mode t)
    (emacsvox-magit--update-blame-context)
    (should (eq emacsvox-aural-module 'magit))
    (setq magit-blob-mode t)
    (emacsvox-magit--update-blob-context)
    (setq magit-blame-mode nil)
    (emacsvox-magit--update-blame-context)
    (should (eq emacsvox-aural-module 'magit))
    (setq magit-blob-mode nil)
    (emacsvox-magit--update-blob-context)
    (should (eq emacsvox-aural-module 'python)))
  (with-temp-buffer
    (should-not (local-variable-p 'emacsvox-aural-module))
    (setq git-commit-mode t)
    (emacsvox-magit--update-commit-context)
    (should (eq emacsvox-aural-module 'magit))
    (setq git-commit-mode nil)
    (emacsvox-magit--update-commit-context)
    (should-not (local-variable-p 'emacsvox-aural-module))))

(ert-deftest emacsvox-magit-section-movement-uses-central-hook ()
  "All central section movements produce exactly one native line submission."
  (with-temp-buffer
    (insert "Unstaged changes")
    (goto-char (point-min))
    (emacsvox-magit-enable-aural-context)
    (should
     (memq
      #'emacsvox-magit--section-moved
      magit-section-movement-hook))
    (let (calls)
      (cl-letf
        (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push (cons content arguments) calls))))
        (let ((ems--interactive-fn-name 'magit-section-forward))
          (emacsvox-magit--section-moved
           '(:type unstaged :hidden nil)))
        (should (= (length calls) 1))
        (should
         (equal
          (plist-get (cdar calls) :facts)
          '(:role vcs-section :section-kind unstaged
            :events (focus-entered) :visibility expanded)))
        (let ((ems--interactive-fn-name 'magit-stage))
          (emacsvox-magit--section-moved
           '(:type staged :hidden nil)))
        (let ((ems--interactive-fn-name nil))
          (emacsvox-magit--section-moved
           '(:type staged :hidden nil))))
      (should (= (length calls) 1)))))

(ert-deftest emacsvox-magit-section-jumpers-are-covered ()
  "Every current generated Magit section jumper has navigation feedback."
  (should (= (length emacsvox-magit--section-jump-targets) 15))
  (dolist (target emacsvox-magit--section-jump-targets)
    (should (fboundp target))
    (should
     (memq target emacsvox-magit--navigation-targets))))

(ert-deftest emacsvox-magit-view-kinds-cover-the-interface ()
  "Every distinct Magit interface family should expose a view kind."
  (dolist
      (entry
       '((magit-status-mode . status)
         (magit-process-mode . process)
         (magit-revision-mode . commit)
         (magit-refs-mode . refs)
         (magit-log-mode . log)
         (magit-diff-mode . diff)
         (magit-repolist-mode . repositories)
         (git-rebase-mode . rebase)))
    (with-temp-buffer
      (setq major-mode (car entry))
      (should
       (eq
        (emacsvox-magit-current-view-kind)
        (cdr entry)))))
  (with-temp-buffer
    (setq magit-blame-mode t)
    (should (eq (emacsvox-magit-current-view-kind) 'blame)))
  (with-temp-buffer
    (setq magit-blob-mode t)
    (should (eq (emacsvox-magit-current-view-kind) 'blob)))
  (with-temp-buffer
    (setq git-commit-mode t)
    (should (eq (emacsvox-magit-current-view-kind) 'commit))))

(ert-deftest emacsvox-magit-central-setup-presents-refreshed-view ()
  "Nested Magit view commands present content after setup and refresh finish."
  (let ((buffer (generate-new-buffer " *emacsvox-magit-log*"))
        (ems--interactive-fn-name 'magit-log-current)
        calls)
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (setq major-mode 'magit-log-mode)
            (insert
             (propertize
              "abc Subject" 'face 'magit-log-author)))
          (cl-letf
              (((symbol-function 'emacsvox-aural-submit)
                (lambda (content &rest arguments)
                  (push (cons content arguments) calls))))
            (should
             (eq
              (emacsvox--advice-magit-setup-buffer-internal-around
               (lambda (&rest _) buffer)
               'magit-log-mode nil nil)
              buffer)))
          (pcase-let* ((`((,content . ,arguments)) calls)
                       (actions
                        (plist-get arguments :compatibility-actions)))
            (should (equal content "Log view. abc Subject"))
            (should
             (eq
              (get-text-property (length "Log view. ") 'face content)
              'magit-log-author))
            (should
             (equal
              (plist-get arguments :facts)
              '(:role vcs-view :vcs-view-kind log
                :events (vcs-view-opened)
                :vcs-operation magit-log-current)))
            (should
             (equal
              (mapcar
               #'emacsvox-aural-compatibility-action-value actions)
              '(open-object)))))
      (kill-buffer buffer))))

(ert-deftest emacsvox-magit-central-display-respects-suppression ()
  "Direct displays announce once, while internal and noselect displays do not."
  (let ((buffer (generate-new-buffer " *emacsvox-magit-diff*"))
        calls)
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (setq major-mode 'magit-diff-mode)
            (insert "diff content"))
          (cl-letf
              (((symbol-function 'emacsvox-magit--present-opened-buffer)
                (lambda (&rest arguments) (push arguments calls))))
            (let ((ems--interactive-fn-name 'magit-diff-range)
                  (magit-display-buffer-noselect nil)
                  (emacsvox-magit--setting-up-buffer nil))
              (should
               (eq
                (emacsvox--advice-magit-display-buffer-around
                 (lambda (&rest _) 'displayed)
                 buffer)
                'displayed)))
            (let ((ems--interactive-fn-name 'magit-diff-range)
                  (magit-display-buffer-noselect t)
                  (emacsvox-magit--setting-up-buffer nil))
              (emacsvox--advice-magit-display-buffer-around
               #'ignore buffer))
            (let ((ems--interactive-fn-name 'magit-diff-range)
                  (magit-display-buffer-noselect nil)
                  (emacsvox-magit--setting-up-buffer t))
              (emacsvox--advice-magit-display-buffer-around
               #'ignore buffer))
            (let ((ems--interactive-fn-name 'magit-show-commit)
                  (magit-display-buffer-noselect nil)
                  (emacsvox-magit--setting-up-buffer nil))
              (emacsvox--advice-magit-display-buffer-around
               #'ignore buffer)))
          (should
           (equal calls `((,buffer magit-diff-range)))))
      (kill-buffer buffer))))

(ert-deftest emacsvox-magit-rebase-command-surface-is-covered ()
  "Every current Git Rebase command family should have dedicated feedback."
  (should (= (length emacsvox-magit--rebase-action-targets) 21))
  (should (= (length emacsvox-magit--rebase-view-targets) 3))
  (dolist
      (target
       (append
        (mapcar #'car emacsvox-magit--rebase-action-targets)
        (mapcar #'car emacsvox-magit--rebase-view-targets)
        '(git-rebase-backward-line forward-line)))
    (should (where-is-internal target git-rebase-mode-map)))
  (with-temp-buffer
    (emacsvox-magit-enable-rebase-feedback)
    (should
     (memq
      #'emacsvox-magit--rebase-finish-feedback
      with-editor-post-finish-hook))
    (should
     (memq
      #'emacsvox-magit--rebase-cancel-feedback
      with-editor-post-cancel-hook))))

(ert-deftest emacsvox-magit-rebase-facts-preserve-action-variants ()
  "Rebase facts distinguish fixup and merge message policies."
  (dolist
      (entry
       '(("pick abc # subject" . pick)
         ("fixup -c abc # subject" . fixup-edit-message)
         ("fixup -C abc # subject" . fixup-use-message)
         ("merge -c abc label # subject" . merge-edit-message)
         ("merge -C abc label # subject" . merge-use-message)))
    (with-temp-buffer
      (setq comment-start "#")
      (setq git-rebase-comment-re "^#")
      (insert (car entry))
      (should
       (equal
        (emacsvox-magit-rebase-facts 'inspect 'focus-entered)
        (list
         :role 'vcs-rebase-entry
         :vcs-operation 'inspect
         :vcs-rebase-action (cdr entry)
         :events '(focus-entered)))))))

(ert-deftest emacsvox-magit-rebase-edit-announces-operation-and-focus ()
  "A rebase edit reports both the operation and current focused entry."
  (with-temp-buffer
    (setq comment-start "#")
    (setq git-rebase-comment-re "^#")
    (insert
     (propertize "pick" 'face 'git-rebase-action)
     (propertize " abc # subject" 'face 'git-rebase-description))
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'git-rebase-squash)
          calls)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push (cons content arguments) calls))))
        (should
         (eq
          (emacsvox--advice-git-rebase-squash-around
           (lambda ()
             (delete-region (point-min) (+ (point-min) 4))
             (goto-char (point-min))
             (insert (propertize "squash" 'face 'git-rebase-action))
             'changed))
          'changed)))
      (pcase-let* ((`((,content . ,arguments)) calls)
                   (facts (plist-get arguments :facts))
                   (actions
                    (plist-get arguments :compatibility-actions)))
        (should (equal content "Squash. squash abc # subject"))
        (should
         (eq (get-text-property 0 'personality content) voice-annotate))
        (should
         (eq
          (get-text-property (length "Squash. ") 'face content)
          'git-rebase-action))
        (should
         (equal
          facts
          '(:role vcs-rebase-entry
            :vcs-operation squash
            :vcs-rebase-action squash
            :events (operation-completed))))
        (should (eq (plist-get arguments :occasion) 'state-change))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-value actions)
          '(select-object)))))))

(ert-deftest emacsvox-magit-rebase-no-op-is-not-reported-as-success ()
  "A rebase command that makes no edit reports failure and preserves its result."
  (with-temp-buffer
    (setq comment-start "#")
    (setq git-rebase-comment-re "^#")
    (insert "pick abc # subject")
    (let ((ems--interactive-fn-name 'git-rebase-drop)
          calls)
      (cl-letf
          (((symbol-function 'emacsvox-magit--present-rebase-line)
            (lambda (&rest arguments) (push arguments calls))))
        (should
         (eq
          (emacsvox--advice-git-rebase-drop-around
           (lambda () 'unchanged))
          'unchanged)))
      (should
       (equal
        calls
        '((drop operation-failed state-change warn-user
           "No drop change")))))))

(ert-deftest emacsvox-magit-rebase-forward-line-is-scoped-and-native ()
  "Generic forward-line feedback is added only inside Git Rebase."
  (let (calls)
    (cl-letf
        (((symbol-function 'emacsvox-magit--present-rebase-line)
          (lambda (&rest arguments) (push arguments calls))))
      (with-temp-buffer
        (setq major-mode 'git-rebase-mode)
        (let ((ems--interactive-fn-name 'forward-line))
          (emacsvox--advice-git-rebase-forward-line-after)))
      (with-temp-buffer
        (setq major-mode 'text-mode)
        (let ((ems--interactive-fn-name 'forward-line))
          (emacsvox--advice-git-rebase-forward-line-after))))
    (should
     (equal
      calls
      '((move-forward focus-entered navigation select-object))))))

(ert-deftest emacsvox-magit-rebase-completion-feedback-is-user-driven ()
  "Rebase finish and cancel hooks are silent unless invoked interactively."
  (let (calls)
    (cl-letf
        (((symbol-function 'emacsvox-magit--submit-text)
          (lambda (&rest arguments) (push arguments calls))))
      (let ((ems--interactive-fn-name nil))
        (emacsvox-magit--rebase-finish-feedback)
        (emacsvox-magit--rebase-cancel-feedback))
      (let ((ems--interactive-fn-name 'with-editor-finish))
        (emacsvox-magit--rebase-finish-feedback))
      (let ((ems--interactive-fn-name 'with-editor-cancel))
        (emacsvox-magit--rebase-cancel-feedback)))
    (should (= (length calls) 2))
    (should
     (equal
      (mapcar #'car (nreverse calls))
      '("Submitted interactive rebase"
        "Canceled interactive rebase")))))

(ert-deftest emacsvox-magit-face-inventory-is-current ()
  "Every current Magit and Git editing face should be classified."
  (let ((configured
         (sort
          (append
           (mapcar #'car emacsvox-magit--face-voice-map)
           emacsvox-magit--unvoiced-faces
           nil)
          (lambda (a b) (string< (symbol-name a) (symbol-name b)))))
        (current
         (sort
          (seq-filter
           (lambda (face)
             (let ((name (symbol-name face)))
               (or
                (string-prefix-p "magit-" name)
                (string-prefix-p "git-rebase-" name)
                (string-prefix-p "git-commit-" name))))
           (face-list))
          (lambda (a b) (string< (symbol-name a) (symbol-name b))))))
    (should (equal configured current))
    (should (= (length configured) 126))
    (should
     (= (length configured)
        (length (delete-dups (copy-sequence configured)))))))

(ert-deftest emacsvox-magit-face-voices-are-explicit ()
  "All content-bearing Magit faces resolve to their declared personalities."
  (dolist (entry emacsvox-magit--face-voice-map)
    (should
     (eq
      (voice-setup-get-voice-for-face (car entry))
      (cadr entry))))
  (dolist (face emacsvox-magit--unvoiced-faces)
    (should-not (voice-setup-get-voice-for-face face)))
  (should-not
   (plist-get
    (voice-setup-face-mapping-diagnostic
     'magit-diff-added-highlight)
    :conflict)))

(ert-deftest emacsvox-magit-removed-targets-are-not-recreated ()
  "Do not install phantom advice for removed Magit commands."
  (dolist
      (target
       '(magit-mark-item
         magit-ignore-file
         magit-ignore-item
         magit-ignore-item-locally
         magit-stage-file
         magit-unstage-file
         magit-blame-toggle-headings))
    (should-not (fboundp target))))

(ert-deftest emacsvox-magit-advice-is-directly-registered ()
  "Magit advice uses native advice directly."
  (dolist (target emacsvox-magit--simple-advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (advice-member-p function target))))
  (should
   (advice-member-p
    #'emacsvox--advice-magit-diff-show-or-scroll-up-around
    'magit-diff-show-or-scroll-up))
  (should
   (advice-member-p
    #'emacsvox--advice-magit-setup-buffer-internal-around
    'magit-setup-buffer-internal))
  (should
   (advice-member-p
    #'emacsvox--advice-magit-display-buffer-around
    'magit-display-buffer))
  (dolist
      (target (mapcar #'car emacsvox-magit--rebase-action-targets))
    (should
     (advice-member-p
      (intern (format "emacsvox--advice-%s-around" target))
      target)))
  (dolist
      (target
       (append
        '(git-rebase-backward-line)
        (mapcar #'car emacsvox-magit--rebase-view-targets)))
    (should
     (advice-member-p
      (intern (format "emacsvox--advice-%s-after" target))
      target)))
  (should
   (advice-member-p
    #'emacsvox--advice-git-rebase-forward-line-after
    'forward-line)))

(ert-deftest emacsvox-magit-diff-scroll-calls-original-once ()
  "Diff scrolling calls once, preserves its result, and announces motion."
  (with-temp-buffer
    (insert "a\nb")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'magit-diff-show-or-scroll-up)
          (calls 0)
          events)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push
               (list
                content
                (plist-get arguments :facts)
                (mapcar
                 #'emacsvox-aural-compatibility-action-value
                 (plist-get arguments :compatibility-actions)))
               events))))
        (should
         (eq
          'scrolled
          (emacsvox--advice-magit-diff-show-or-scroll-up-around
           (lambda ()
             (cl-incf calls)
             (forward-line 1)
             'scrolled)))))
      (should (= calls 1))
      (should
       (equal
        events
        '(("b"
           (:role vcs-view :vcs-view-kind diff
            :events (vcs-diff-scrolled))
           (scroll))))))))

(ert-deftest emacsvox-magit-diff-scroll-noninteractive-calls-once ()
  "A noninteractive diff call has no duplicate invocation."
  (let ((calls 0)
        (ems--interactive-fn-name nil))
    (should
     (eq
      'result
      (emacsvox--advice-magit-diff-show-or-scroll-up-around
       (lambda () (cl-incf calls) 'result))))
    (should (= calls 1))))

(ert-deftest emacsvox-magit-stage-facts-express-intent ()
  "Staging and section visibility have explicit semantic facts."
  (should
   (equal
    (emacsvox-magit-section-facts
     'magit-stage '(:type file :hidden nil))
    '(:role vcs-section
      :section-kind file
      :events (entry-staged)
      :states (staged)
      :visibility expanded)))
  (should
   (equal
    (emacsvox-magit-section-facts
     'magit-section-toggle
     '(:type hunk :hidden t)
     'visibility-changed)
    '(:role vcs-section
      :section-kind hunk
      :events (visibility-changed)
      :visibility folded))))

(ert-deftest emacsvox-magit-line-feedback-is-one-native-submission ()
  "Magit line text, source voice, and cue share one native submission."
  (with-temp-buffer
    (insert (propertize "modified file" 'face 'magit-filename))
    (goto-char (point-min))
    (let (calls)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push (cons content arguments) calls)
              'submission)))
        (should
         (eq
          (emacsvox-magit-present-line
           'select-object 'state-change
           'magit-file-unstage '(:type file :hidden nil))
          'submission)))
      (pcase-let* ((`((,content . ,arguments)) calls)
                   (actions
                    (plist-get arguments :compatibility-actions)))
        (should (equal content "modified file"))
        (should
         (eq (get-text-property 0 'face content) 'magit-filename))
        (should
         (equal
          (plist-get arguments :facts)
          '(:role vcs-section :section-kind file
            :events (entry-unstaged) :states (unstaged)
            :visibility expanded)))
        (should (eq (plist-get arguments :module) 'magit))
        (should (eq (plist-get arguments :occasion) 'state-change))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-value actions)
          '(select-object)))))))

(ert-deftest emacsvox-magit-blame-navigation-uses-one-native-submission ()
  "Blame content and its before/after cues are submitted together."
  (with-temp-buffer
    (insert
     (propertize
      "deadbeef" 'personality 'voice-lighten
      'after-string " Author"))
    (goto-char (point-min))
    (let (calls)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push (cons content arguments) calls)
              'submission)))
        (should
         (eq
          (emacsvox-magit-blame-speak 'large-movement)
          'submission)))
      (should (= (length calls) 1))
      (pcase-let* ((`(,content . ,arguments) (car calls))
                   (actions
                    (plist-get arguments :compatibility-actions)))
        (should (equal content "deadbeef Author"))
        (should
         (eq
          (get-text-property 0 'personality content)
          'voice-lighten))
        (should
         (equal
          (plist-get arguments :facts)
          '(:role vcs-blame-chunk :events (focus-entered))))
        (should (eq (plist-get arguments :module) 'magit))
        (should (eq (plist-get arguments :occasion) 'navigation))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-value actions)
          '(left large-movement)))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-phase actions)
          '(before after)))))))

(ert-deftest emacsvox-magit-blame-advice-adds-movement-after-content ()
  "Interactive blame navigation requests one trailing movement cue."
  (let ((ems--interactive-fn-name
         'magit-blame-next-chunk-same-commit)
        calls)
    (cl-letf
        (((symbol-function 'emacsvox-magit-blame-speak)
          (lambda (&optional icon) (push icon calls))))
      (emacsvox--advice-magit-blame-next-chunk-after)
      (emacsvox--advice-magit-blame-next-chunk-same-commit-after))
    (should (equal calls '(large-movement)))))

(ert-deftest emacsvox-magit-empty-blame-is-an-action-only-submission ()
  "An empty blame line still presents its cues through native policy."
  (with-temp-buffer
    (let (calls)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (&rest _)
              (ert-fail "Empty blame content used native submission")))
           ((symbol-function 'emacsvox-aural-submit-actions)
            (lambda (&rest arguments)
              (push arguments calls)
              'submission)))
        (emacsvox-magit-blame-speak 'large-movement))
      (pcase-let* ((`(,arguments) calls)
                   (actions
                    (plist-get arguments :compatibility-actions)))
        (should
         (equal
          (plist-get arguments :facts)
          '(:role vcs-blame-chunk :events (focus-entered))))
        (should (eq (plist-get arguments :module) 'magit))
        (should (eq (plist-get arguments :occasion) 'navigation))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-value actions)
          '(left large-movement)))))))

(ert-deftest emacsvox-magit-native-blame-presents-one-transaction ()
  "Blame navigation preserves voice, order, and icon policy."
  (dolist (icons-enabled '(t nil))
    (with-temp-buffer
      (insert (propertize "deadbeef" 'personality 'voice-lighten))
      (goto-char (point-min))
      (let ((emacsvox-aural-active-scheme 'default)
            (emacsvox-aural-enabled-feature-fragments nil)
            (emacsvox-aural-user-rules nil)
            (emacsvox-aural-session-rules nil)
            (emacsvox-aural-buffer-rules nil)
            (emacsvox-aural-presentation-history nil)
            (emacsvox-aural-presentation-history-limit 20)
            (emacsvox-aural--presentation-sequence 0)
            (emacsvox-aural--submission-sequence 0)
            (emacsvox-aural-plan-presented-hook nil)
            (emacsvox-use-icons icons-enabled)
            (emacsvox-aural-face-presentation-enabled t)
            (voice-lock-mode t)
            events
            submission)
        (cl-letf
            (((symbol-function 'tts-speak)
              (lambda (prepared)
                (with-temp-buffer
                  (insert prepared)
                  (tts-audio-format (point-min) (point-max)))))
             ((symbol-function 'emacsvox-queue-resource)
              (lambda (_resource) (push 'cue events)))
             ((symbol-function 'tts-voice-reset-code)
              (lambda () "RESET"))
             ((symbol-function 'tts--protocol-queue-code) #'ignore)
             ((symbol-function 'tts--protocol-queue-text)
              (lambda (text) (push (list 'text text) events)))
             ((symbol-function 'tts--protocol-silence) #'ignore))
          (setq
           submission
           (emacsvox-magit-blame-speak 'large-movement)))
        (should (emacsvox-aural-submission-p submission))
        (should
         (equal
          (nreverse events)
          (if icons-enabled
              '(cue (text "deadbeef") cue)
            '((text "deadbeef")))))
        (should (= (length emacsvox-aural-presentation-history) 1))
        (should
         (= (emacsvox-aural-presentation-record-transaction-id
             (emacsvox-aural-last-presentation))
            1))
        (let* ((plans (emacsvox-aural-submission-plans submission))
               (plan (car plans))
               (content
                (emacsvox-aural-concrete-plan-content plan)))
          (should (= (length plans) 1))
          (should
           (equal
            (mapcar
             #'emacsvox-aural-concrete-action-cue
             (emacsvox-aural-concrete-plan-before plan))
            (and icons-enabled '(left))))
          (should
           (equal
            (mapcar
             #'emacsvox-aural-concrete-action-cue
             (emacsvox-aural-concrete-plan-after plan))
            (and icons-enabled '(large-movement))))
          (should
           (eq
            (emacsvox-aural-concrete-content-voice-request content)
            'voice-lighten)))))))

(ert-deftest emacsvox-magit-view-and-process-facts-express-intent ()
  "Magit view lifecycle and process completion use distinct semantics."
  (should
   (equal
    (emacsvox-magit-view-facts 'diff 'vcs-diff-scrolled)
    '(:role vcs-view :vcs-view-kind diff
      :events (vcs-diff-scrolled))))
  (should
   (equal
    (emacsvox-magit-process-facts t)
    '(:role vcs-process :events (operation-failed)))))

(ert-deftest emacsvox-magit-programmatic-section-visibility-is-silent ()
  "Internal Magit section rendering must not produce user feedback."
  (let (events)
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit)
          (lambda (&rest _) (push 'text events)))
         ((symbol-function 'emacsvox-aural-submit-actions)
          (lambda (&rest arguments)
            (push
             (mapcar
              #'emacsvox-aural-compatibility-action-value
              (plist-get arguments :compatibility-actions))
             events))))
      (let ((ems--interactive-fn-name nil))
        (emacsvox--advice-magit-section-show-children-after)
        (emacsvox--advice-magit-section-hide-after))
      (should-not events)
      (let ((ems--interactive-fn-name 'magit-section-show-children))
        (emacsvox--advice-magit-section-show-children-after))
      (should (equal events '((open-object)))))))

(ert-deftest emacsvox-magit-process-feedback-is-asynchronous-and-accurate ()
  "Only asynchronous Magit completion gets feedback, using its true result."
  (let (events)
    (cl-letf
        (((symbol-function 'processp)
          (lambda (value) (eq value 'failed-process)))
         ((symbol-function 'process-status)
          (lambda (_) 'exit))
         ((symbol-function 'process-exit-status)
          (lambda (_) 1))
         ((symbol-function 'emacsvox-aural-submit-actions)
          (lambda (&rest arguments)
            (push
             (list
              (mapcar
               #'emacsvox-aural-compatibility-action-value
               (plist-get arguments :compatibility-actions))
              (plist-get arguments :facts))
             events))))
      (emacsvox--advice-magit-process-finish-after 0)
      (should-not events)
      (emacsvox--advice-magit-process-finish-after 'failed-process)
      (should
       (equal
        events
        '(((warn-user)
           (:role vcs-process :events (operation-failed)))))))))

(ert-deftest emacsvox-magit-special-feedback-has-accurate-semantics ()
  "Commit display and diff cycling are not reported as section expansion."
  (let (events)
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit-actions)
          (lambda (&rest arguments)
            (push
             (list
              (mapcar
               #'emacsvox-aural-compatibility-action-value
               (plist-get arguments :compatibility-actions))
              (plist-get arguments :facts)
              (plist-get arguments :occasion))
             events))))
      (let ((ems--interactive-fn-name 'magit-show-commit))
        (emacsvox--advice-magit-show-commit-after))
      (let ((ems--interactive-fn-name 'magit-section-cycle-diffs))
        (emacsvox--advice-magit-section-cycle-diffs-after)))
    (should
     (equal
      (nreverse events)
      '(((open-object)
         (:role vcs-view :vcs-view-kind commit
          :events (vcs-view-opened))
         navigation)
        ((large-movement)
         (:role vcs-view :vcs-view-kind diff
          :events (visibility-changed))
         state-change))))))

(ert-deftest emacsvox-magit-diff-feedback-has-view-context ()
  "Diff scrolling keeps its compatibility output inside one view submission."
  (with-temp-buffer
    (insert "a\nb")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'magit-diff-show-or-scroll-up)
          events)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push
               (list
                content
                (plist-get arguments :facts)
                (plist-get arguments :occasion)
                (mapcar
                 #'emacsvox-aural-compatibility-action-value
                 (plist-get arguments :compatibility-actions)))
               events))))
        (emacsvox--advice-magit-diff-show-or-scroll-up-around
         (lambda () (forward-line 1))))
      (should
       (equal
        (nreverse events)
        '(("b"
           (:role vcs-view :vcs-view-kind diff
            :events (vcs-diff-scrolled))
           navigation
           (scroll))))))))

(provide 'emacsvox-magit-tests)
;;; emacsvox-magit-tests.el ends here
