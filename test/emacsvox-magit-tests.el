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
(require 'emacsvox-advice)

(load
 (expand-file-name
  (if (equal (getenv "EMACSVOX_MAGIT_TEST_LOAD") "compiled")
      "../lisp/emacsvox-magit.elc"
    "../lisp/emacsvox-magit.el")
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
    (insert (propertize "first repository\n" 'tabulated-list-id "/src/first/")
            (propertize "second repository" 'tabulated-list-id "/src/second/"))
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'magit-repolist-mark)
          calls)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
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
           (dotimes (_ 2)
             (emacsvox--advice-magit-process-finish-around #'identity 0))
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
           state-change open-object)))))))

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
    (should
     (memq
      #'emacsvox-magit--section-moved
      magit-mouse-set-point-hook))
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

(ert-deftest emacsvox-magit-line-content-presents-visual-semantics ()
  "Margin content and fringe state replace Magit's visual carriers."
  (with-temp-buffer
    (insert "abc123 Commit subject")
    (goto-char (point-min))
    (let* ((note (propertize " reviewed" 'personality voice-annotate))
           (margin
            (propertize " 2026-08-24 " 'personality voice-smoothen))
           (display-content
            (concat
             (propertize
              "fringe" 'display '(left-fringe magit-fringe-bitmap> fringe))
             note
             (propertize
              "o" 'display `((margin right-margin) ,margin)))))
      (cl-letf (((symbol-function 'ems--display-props-get)
                 (lambda () display-content)))
        (let ((content (emacsvox-magit--line-content 'folded)))
          (should
           (equal
            (substring-no-properties content)
            "abc123 Commit subject reviewed, 2026-08-24, collapsed"))
          (should
           (eq
            (get-text-property
             (string-match-p "reviewed" content) 'personality content)
            voice-annotate))
          (should
           (eq
            (get-text-property
             (string-match-p "2026" content) 'personality content)
            voice-smoothen))
          (should
           (eq
            (get-text-property
             (string-match-p "collapsed" content) 'personality content)
            voice-annotate)))
        (should
         (equal
          (substring-no-properties (emacsvox-magit--line-content 'expanded))
          "abc123 Commit subject reviewed, 2026-08-24, expanded"))
        (should
         (equal
          (substring-no-properties (emacsvox-magit--line-content))
          "abc123 Commit subject reviewed, 2026-08-24"))))))

(ert-deftest emacsvox-magit-navigation-names-fringe-visibility ()
  "Navigating to a fringe-marked section names its current visibility."
  (with-temp-buffer
    (insert "Unmerged into origin/master")
    (goto-char (point-min))
    (let (calls)
      (cl-letf
          (((symbol-function 'ems--display-props-get)
            (lambda ()
              (propertize
               "fringe" 'display
               '(left-fringe magit-fringe-bitmap> fringe))))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push (cons content arguments) calls))))
        (emacsvox-magit-present-line
         'select-object 'navigation 'magit-next-line
         '(:type unpushed :hidden t)))
      (pcase-let ((`((,content . ,arguments)) calls))
        (should
         (equal
          (substring-no-properties content)
          "Unmerged into origin/master, collapsed"))
        (should
         (equal
          (plist-get arguments :facts)
          '(:role vcs-section :section-kind unpushed
            :events (focus-entered) :visibility folded)))))))

(ert-deftest emacsvox-magit-line-content-finds-margin-away-from-point ()
  "Margin metadata is presented even when point is outside its overlay."
  (with-temp-buffer
    (insert "abc123 Commit subject")
    (let ((overlay (make-overlay (1+ (point-min)) (point-max) nil t)))
      (overlay-put
       overlay 'before-string
       (propertize
        "o" 'display
        '((margin right-margin) "Ada, two days ago")))
      (goto-char (point-min))
      (should (string-empty-p (ems--display-props-get)))
      (should
       (equal
        (substring-no-properties (emacsvox-magit--line-content))
        "abc123 Commit subject, Ada, two days ago")))))

(ert-deftest emacsvox-magit-line-content-discards-empty-margin-backing ()
  "A section heading never speaks Magit's blank margin backing character."
  (with-temp-buffer
    (insert "Unmerged into origin/master (2)")
    (let ((fringe (make-overlay (point-min) (point-max)))
          (margin (make-overlay (1+ (point-min)) (point-max))))
      (overlay-put
       fringe 'before-string
       (propertize
        "fringe" 'display '(left-fringe magit-fringe-bitmapv fringe)))
      (overlay-put
       margin 'before-string
       (propertize "o" 'display '((margin right-margin) " ")))
      (goto-char (point-min))
      (should
       (equal
        (substring-no-properties (emacsvox-magit--line-content 'expanded))
        "Unmerged into origin/master (2), expanded")))))

(ert-deftest emacsvox-magit-blank-line-discards-empty-margin-backing ()
  "A blank row never consists of Magit's margin backing character."
  (with-temp-buffer
    (insert "Commit\n\n")
    (goto-char (1- (point-max)))
    (let ((margin (make-overlay (point) (point-max))))
      (overlay-put
       margin 'before-string
       (propertize "o" 'display '((margin right-margin) " ")))
      (should (string-empty-p (buffer-substring
                               (line-beginning-position)
                               (line-end-position))))
      (should
       (string-empty-p
        (substring-no-properties (emacsvox-magit--line-content)))))))

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
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist (target emacsvox-magit--copy-targets)
    (should
     (advice-member-p
      (intern (format "emacsvox--advice-%s-around" target))
      target)))
  (dolist (target emacsvox-magit--destination-targets)
    (should
     (advice-member-p
      (intern (format "emacsvox--advice-%s-around" target))
      target)))
  (dolist (target emacsvox-magit--browse-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-around" target))))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist (entry emacsvox-magit--log-select-advice)
    (pcase-let ((`(,target ,function) entry))
      (should (advice-member-p function target))))
  (should
   (advice-member-p
    #'emacsvox--advice-magit-diff-show-or-scroll-up-around
    'magit-diff-show-or-scroll-up))
  (should
   (advice-member-p
    #'emacsvox--advice-magit-diff-show-or-scroll-down-around
    'magit-diff-show-or-scroll-down))
  (dolist (target emacsvox-magit--reference-navigation-targets)
    (should
     (advice-member-p
      (intern (format "emacsvox--advice-%s-around" target))
      target)))
  (should
   (advice-member-p
    #'emacsvox--advice-magit-setup-buffer-internal-around
    'magit-setup-buffer-internal))
  (should
   (advice-member-p
    #'emacsvox--advice-magit-display-buffer-around
    'magit-display-buffer))
  (dolist
      (entry
       '((magit-run-git emacsvox--advice-magit-run-git-around)
         (magit-git emacsvox--advice-magit-git-around)
         (magit-run-git-with-input
          emacsvox--advice-magit-run-git-with-input-around)
         (magit-start-process
          emacsvox--advice-magit-start-process-around)
         (magit-process-kill
          emacsvox--advice-magit-process-kill-around)
         (magit-diff-refresh
          emacsvox--advice-magit-diff-refresh-around)
         (magit-log-refresh
          emacsvox--advice-magit-log-refresh-around)
         (magit-mouse-toggle-section
          emacsvox--advice-magit-mouse-toggle-section-around)
         (magit-patch-save
          emacsvox--advice-magit-patch-save-around)
         (magit-do-async-shell-command
          emacsvox--advice-magit-do-async-shell-command-around)))
    (pcase-let ((`(,target ,function) entry))
      (should (advice-member-p function target))))
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
          (((symbol-function 'scroll-up)
            (lambda (&rest _)
              (forward-line 1)))
           ((symbol-function 'emacsvox-aural-submit)
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
             (scroll-up)
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

(ert-deftest emacsvox-magit-diff-display-is-not-misreported-as-scroll ()
  "Showing a commit without calling the scroll function is a view event."
  (let ((ems--interactive-fn-name 'magit-diff-show-or-scroll-down)
        calls)
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
             calls))))
      (should
       (eq
        (emacsvox--advice-magit-diff-show-or-scroll-down-around
         (lambda () 'displayed))
        'displayed))
      (should
       (equal
        calls
        '(("Displayed commit in other window"
           (:role vcs-view :vcs-view-kind commit
            :events (vcs-commit-displayed))
           (open-object))))))))

(ert-deftest emacsvox-magit-reference-navigation-is-accurate ()
  "Reference navigation distinguishes movement from an exhausted search."
  (with-temp-buffer
    (insert "first\nsecond")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'magit-next-reference)
          calls)
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
               calls))))
        (emacsvox-magit--call-reference-navigation
         (lambda (&rest _) (forward-line 1))
         'magit-next-reference nil)
        (should
         (equal
          calls
          '(("second"
             (:role vcs-view :vcs-view-kind other
              :events (focus-entered)
              :vcs-operation magit-next-reference)
             (select-object)))))))))

(ert-deftest emacsvox-magit-reference-boundary-is-not-selection ()
  "An exhausted reference search reports a boundary, not movement."
  (with-temp-buffer
    (let ((ems--interactive-fn-name 'magit-previous-reference)
          message-state
          calls)
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
               calls))))
        (emacsvox-magit--call-reference-navigation
         (lambda (&rest _)
           (setq
            message-state
            (list emacsvox-speak-messages inhibit-message))
           'boundary)
         'magit-previous-reference nil)
        (should (equal message-state '(nil t)))
        (should
         (equal
          calls
          '(("No more references"
             (:role vcs-view :vcs-view-kind other
              :events (operation-failed)
              :vcs-operation magit-previous-reference)
             (warn-user)))))))))

(ert-deftest emacsvox-magit-blob-navigation-identifies-revision ()
  "Changing blobs speaks the selected revision, file, and source line."
  (with-temp-buffer
    (insert "source line")
    (setq-local magit-buffer-revision "abc123")
    (setq-local magit-buffer-file-name "lisp/example.el")
    (should
     (equal
      (substring-no-properties (emacsvox-magit--blob-summary))
      "abc123, lisp/example.el. source line"))))

(ert-deftest emacsvox-magit-copy-feedback-reports-the-value ()
  "Copying a concise Magit value speaks it in one native transaction."
  (let ((ems--interactive-fn-name 'magit-copy-section-value)
        (kill-ring '("abc123"))
        calls)
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
             calls))))
      (should
       (eq
        (emacsvox-magit--call-copy-command
         (lambda (&rest _) (kill-new "abc123") 'copied)
         'magit-copy-section-value nil)
        'copied))
      (should
       (equal
        (mapcar
         (lambda (call)
           (cons (substring-no-properties (car call)) (cdr call)))
         calls)
        '(("Copied. abc123"
           (:role vcs-view :vcs-view-kind other
            :events (operation-completed)
            :vcs-operation magit-copy-section-value)
           (mark-object))))))))

(ert-deftest emacsvox-magit-copy-feedback-summarizes-large-content ()
  "Copy feedback does not unexpectedly speak a large patch."
  (let ((kill-ring '("one\ntwo\nthree")))
    (should (equal (emacsvox-magit--copied-content) "Copied 3 lines")))
  (let ((kill-ring (list (make-string 201 ?x))))
    (should
     (equal
      (emacsvox-magit--copied-content)
      "Copied 201 characters"))))

(ert-deftest emacsvox-magit-process-kill-reports-interrupt ()
  "The first process-kill request is identified as an interrupt."
  (let ((ems--interactive-fn-name 'magit-process-kill)
        calls)
    (cl-letf
        (((symbol-function 'magit-section-value-if)
          (lambda (_) 'fake-process))
         ((symbol-function 'process-status)
          (lambda (_) 'run))
         ((symbol-function 'process-get)
          (lambda (&rest _) nil))
         ((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (push
             (list
              content
              (plist-get arguments :facts)
              (mapcar
               #'emacsvox-aural-compatibility-action-value
               (plist-get arguments :compatibility-actions)))
             calls))))
      (should
       (eq
        (emacsvox-magit--call-process-kill
         (lambda (&rest _) 'interrupted)
         nil)
        'interrupted))
      (should
       (equal
        calls
        '(("Interrupted process"
           (:role vcs-process :events (operation-completed)
            :vcs-operation interrupt)
           (close-object))))))))

(ert-deftest emacsvox-magit-process-kill-reports-no-target ()
  "Process kill reports the absence of a running process as failure."
  (let ((ems--interactive-fn-name 'magit-process-kill)
        calls)
    (cl-letf
        (((symbol-function 'magit-section-value-if)
          (lambda (_) nil))
         ((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (push
             (list
              content
              (plist-get arguments :facts)
              (mapcar
               #'emacsvox-aural-compatibility-action-value
               (plist-get arguments :compatibility-actions)))
             calls))))
      (emacsvox-magit--call-process-kill
       (lambda (&rest _) 'no-process)
       nil)
      (should
       (equal
        calls
        '(("No process at point"
           (:role vcs-process :events (operation-failed)
            :vcs-operation interrupt)
           (warn-user))))))))

(ert-deftest emacsvox-magit-section-description-is-native ()
  "Section inspection submits concise identity and semantic context."
  (let ((ems--interactive-fn-name 'magit-describe-section)
        calls)
    (cl-letf
        (((symbol-function 'magit-describe-section-briefly)
          (lambda (&rest _) "#<magit-file-section README>"))
         ((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (push
             (list
              content
              (plist-get arguments :facts)
              (plist-get arguments :occasion)
              (mapcar
               #'emacsvox-aural-compatibility-action-value
               (plist-get arguments :compatibility-actions)))
             calls))))
      (emacsvox--advice-magit-describe-section-after
       '(:type file))
      (should
       (equal
        calls
        '(("#<magit-file-section README>"
           (:role vcs-section :section-kind file
            :events (operation-completed)
            :visibility expanded
            :vcs-operation magit-describe-section)
           notification
           (help))))))))

(ert-deftest emacsvox-magit-semantic-occasions-pass-runtime-validation ()
  "Every Magit semantic family accepts its runtime occasions."
  (dolist
      (entry
       '(((:role vcs-section :section-kind file
           :events (focus-entered))
          navigation)
         ((:role vcs-section :section-kind file
           :events (visibility-changed))
          state-change)
         ((:role vcs-section :section-kind file
           :events (operation-completed))
          notification)
         ((:role vcs-view :vcs-view-kind status
           :events (vcs-view-opened))
          navigation)
         ((:role vcs-view :vcs-view-kind status
           :events (vcs-view-opened))
          state-change)
         ((:role vcs-view :vcs-view-kind diff
           :events (operation-completed))
          state-change)
         ((:role vcs-view :vcs-view-kind diff
           :events (operation-completed))
          notification)
         ((:role vcs-blame-chunk :events (focus-entered))
          navigation)
         ((:role vcs-blame-chunk :events (operation-completed))
          inspection)
         ((:role vcs-process :events (operation-completed))
          notification)
         ((:role vcs-rebase-entry :vcs-rebase-action pick
           :events (operation-completed))
          state-change)
         ((:role vcs-rebase-entry :events (focus-entered))
          navigation)
         ((:role vcs-commit-message :events (focus-entered))
          navigation)
         ((:role vcs-commit-message :events (operation-completed))
          state-change)
         ((:role vcs-repository :events (entry-marked))
          state-change)
         ((:role vcs-repository :events (operation-completed))
          notification)))
    (pcase-let ((`(,facts ,occasion) entry))
      (should
       (emacsvox-aural-input-p
        (emacsvox-aural-normalize-input
         facts
         (list :module 'magit :occasion occasion)))))))

(ert-deftest emacsvox-magit-visibility-fragment-replaces-fallback-cue ()
  "The visibility fragment and compatibility fallback produce one cue."
  (let ((emacsvox-aural-active-scheme 'default)
        (emacsvox-aural-enabled-feature-fragments
         '(magit-section-visibility-cues))
        (emacsvox-aural-user-rules nil)
        (emacsvox-aural-session-rules nil)
        (emacsvox-aural-buffer-rules nil)
        submission)
    (cl-letf (((symbol-function 'tts-speak) #'ignore))
      (setq
       submission
       (emacsvox-magit--submit-text
        "expanded section"
        '(:role vcs-section :section-kind file
          :events (visibility-changed)
          :visibility expanded)
        'state-change 'open-object 'after)))
    (let* ((plans (emacsvox-aural-submission-plans submission))
           (plan (car plans)))
      (should (= (length plans) 1))
      (should-not (emacsvox-aural-concrete-plan-before plan))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-concrete-action-id
         (emacsvox-aural-concrete-plan-after plan))
        '(workflow-magit-section-expanded-cue)))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-concrete-action-cue
         (emacsvox-aural-concrete-plan-after plan))
        '(open-object))))))

(ert-deftest emacsvox-magit-destination-command-presents-selected-buffer ()
  "A file destination outside Magit receives explicit view feedback."
  (let ((destination (generate-new-buffer "destination.el"))
        (ems--interactive-fn-name 'magit-diff-visit-file)
        calls)
    (unwind-protect
        (progn
          (with-current-buffer destination
            (emacs-lisp-mode)
            (insert "(message \"destination\")"))
          (cl-letf
              (((symbol-function 'selected-window)
                (lambda () 'fake-window))
               ((symbol-function 'window-buffer)
                (lambda (_) destination))
               ((symbol-function 'emacsvox-aural-submit)
                (lambda (content &rest arguments)
                  (push
                   (list
                    (substring-no-properties content)
                    (plist-get arguments :facts)
                    (mapcar
                     #'emacsvox-aural-compatibility-action-value
                     (plist-get arguments :compatibility-actions)))
                   calls))))
            (should
             (eq
              (emacsvox-magit--call-destination-command
               (lambda (&rest _) 'visited)
               'magit-diff-visit-file nil)
              'visited))
            (should
             (equal
              calls
              '(("destination.el, elisp. (message \"destination\")"
                 (:role vcs-view :vcs-view-kind other
                  :events (vcs-view-opened)
                  :vcs-operation magit-diff-visit-file)
                 (open-object)))))))
      (kill-buffer destination))))

(ert-deftest emacsvox-magit-browse-command-identifies-opened-url ()
  "Opening a URL from Magit receives explicit native feedback."
  (let ((ems--interactive-fn-name 'magit-browse-thing)
        calls)
    (cl-letf
        (((symbol-function 'thing-at-point)
          (lambda (&rest _) "https://example.com/change/1"))
         ((symbol-function 'emacsvox-magit--submit-text)
          (lambda (&rest arguments) (push arguments calls))))
      (should
       (eq
        (emacsvox-magit--call-browse-command
         (lambda (&rest _) 'opened)
         'magit-browse-thing nil)
        'opened)))
    (should
     (equal
      calls
      '(("Opened link in browser. https://example.com/change/1"
         (:role vcs-view :vcs-view-kind other
          :events (operation-completed)
          :vcs-operation magit-browse-thing)
         state-change open-object))))))

(ert-deftest emacsvox-magit-log-selection-identifies-commit ()
  "A log selection without a downstream operation reports its commit."
  (let ((ems--interactive-fn-name 'magit-log-select-pick)
        calls)
    (cl-letf
        (((symbol-function 'magit-commit-at-point)
          (lambda () "abc123"))
         ((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (push
             (list
              content
              (plist-get arguments :facts)
              (mapcar
               #'emacsvox-aural-compatibility-action-value
               (plist-get arguments :compatibility-actions)))
             calls))))
      (should
       (eq
        (emacsvox--advice-magit-log-select-pick-around
         (lambda (&rest _) 'selected))
        'selected))
      (should
       (equal
        calls
        '(("Selected commit abc123"
           (:role vcs-view :vcs-view-kind log
            :vcs-operation magit-log-select-pick
            :events (operation-completed))
           (select-object))))))))

(ert-deftest emacsvox-magit-log-selection-enriches-downstream-operation ()
  "A log-selection callback supplies commit identity to process feedback."
  (let ((emacsvox-magit--operation-detail "commit abc123"))
    (should
     (equal
      (emacsvox-magit--operation-label 'magit-log-select-pick)
      "log select pick, commit abc123"))))

(ert-deftest emacsvox-magit-specialized-blame-entry-is-distinct ()
  "A specialized blame command identifies the chosen blame direction."
  (let ((ems--interactive-fn-name 'magit-blame-removal)
        calls)
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
             calls))))
      (emacsvox--advice-magit-blame-removal-after)
      (should
       (equal
        calls
        '(("Blaming line removals"
           (:role vcs-view :vcs-view-kind blame
            :events (vcs-view-opened)
            :vcs-operation magit-blame-removal)
           (open-object))))))))

(ert-deftest emacsvox-magit-diff-context-reports-effective-value ()
  "Changing diff context reports the effective count and current line."
  (with-temp-buffer
    (insert "current diff line")
    (let ((ems--interactive-fn-name 'magit-diff-more-context)
          calls)
      (cl-letf
          (((symbol-function 'magit-diff-get-context)
            (lambda () 7))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push
               (list
                (substring-no-properties content)
                (plist-get arguments :facts)
                (mapcar
                 #'emacsvox-aural-compatibility-action-value
                 (plist-get arguments :compatibility-actions)))
               calls))))
        (emacsvox--advice-magit-diff-more-context-after)
        (should
         (equal
          calls
          '(("Diff context is 7 lines. current diff line"
             (:role vcs-view :vcs-view-kind other
              :events (operation-completed)
              :vcs-operation magit-diff-more-context)
             (task-done)))))))))

(ert-deftest emacsvox-magit-log-limit-reports-all-or-count ()
  "Log-limit descriptions reflect the effective argument."
  (cl-letf
      (((symbol-function 'magit-log-get-commit-limit)
        (lambda () nil)))
    (should
     (equal
      (emacsvox-magit--view-setting-description
       'magit-log-toggle-commit-limit)
      "Showing all commits")))
  (cl-letf
      (((symbol-function 'magit-log-get-commit-limit)
        (lambda () 128)))
    (should
     (equal
      (emacsvox-magit--view-setting-description
       'magit-log-half-commit-limit)
      "Showing up to 128 commits"))))

(ert-deftest emacsvox-magit-refresh-distinguishes-menu-from-application ()
  "Opening a refresh transient is silent here; applying it is presented."
  (with-temp-buffer
    (insert "selected commit")
    (let ((ems--interactive-fn-name 'magit-log-refresh)
          (transient-current-command nil)
          calls)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (&rest _)
              (push 'submitted calls))))
        (should
         (eq
          (emacsvox-magit--call-transient-refresh
           (lambda (&rest _) 'menu)
           'magit-log-refresh nil)
          'menu))
        (should-not calls)
        (should (eq ems--interactive-fn-name 'magit-log-refresh))))
    (let ((ems--interactive-fn-name 'magit-log-refresh)
          (transient-current-command 'magit-log-refresh)
          calls)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push
               (list
                (substring-no-properties content)
                (plist-get arguments :facts)
                (mapcar
                 #'emacsvox-aural-compatibility-action-value
                 (plist-get arguments :compatibility-actions)))
               calls))))
        (should
         (eq
          (emacsvox-magit--call-transient-refresh
           (lambda (&rest _) 'refreshed)
           'magit-log-refresh nil)
          'refreshed))
        (should
         (equal
          calls
          '(("Refreshed Other view. selected commit"
             (:role vcs-view :vcs-view-kind other
              :events (refresh-completed)
              :vcs-operation magit-log-refresh)
             (task-done)))))))))

(ert-deftest emacsvox-magit-mouse-movement-uses-section-feedback ()
  "Mouse point selection is owned by the central section movement hook."
  (with-temp-buffer
    (insert "clicked section")
    (let ((ems--interactive-fn-name 'magit-mouse-set-point)
          calls)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push
               (list
                content
                (plist-get arguments :facts))
               calls))))
        (emacsvox-magit--section-moved
         '(:type commit :hidden nil))
        (should
         (equal
          calls
          '(("clicked section"
             (:role vcs-section :section-kind commit
              :events (focus-entered)
              :visibility expanded)))))))))

(ert-deftest emacsvox-magit-patch-export-identifies-file ()
  "Saving a patch reports the actual destination."
  (let ((ems--interactive-fn-name 'magit-patch-save)
        calls)
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
             calls))))
      (should
       (eq
        (emacsvox--advice-magit-patch-save-around
         (lambda (&rest _) 'saved)
         "/tmp/topic.patch")
        'saved))
      (should
       (equal
        calls
        '(("Saved patch to /tmp/topic.patch"
           (:role vcs-view :vcs-view-kind diff
            :events (operation-completed)
            :vcs-operation magit-patch-save)
           (save-object))))))))

(ert-deftest emacsvox-magit-shell-handoff-identifies-file ()
  "A Dired shell handoff reports that it started and for which file."
  (let ((ems--interactive-fn-name 'magit-do-async-shell-command)
        calls)
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
             calls))))
      (emacsvox--advice-magit-do-async-shell-command-around
       (lambda (&rest _) 'started)
       "/src/README")
      (should
       (equal
        calls
        '(("Started shell command for README"
           (:role vcs-view :vcs-view-kind other
            :vcs-operation magit-do-async-shell-command)
           (progress))))))))

(ert-deftest emacsvox-magit-conflict-choice-is-explicit ()
  "Conflict resolution descriptions identify the version kept."
  (should
   (equal
    (emacsvox-magit--view-setting-description
     'magit-smerge-keep-upper)
    "Kept upper conflict version"))
  (should
   (equal
    (emacsvox-magit--view-setting-description
     'magit-smerge-keep-all)
    "Kept all conflict version")))

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
    (dolist (face-presentation '(t nil))
      (dolist (voice-lock-enabled '(t nil))
        (with-temp-buffer
          (insert (propertize "deadbeef" 'face 'magit-blame-hash))
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
                (emacsvox-aural-face-presentation-enabled
                 face-presentation)
                (voice-lock-mode voice-lock-enabled)
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
                   (context
                    (emacsvox-aural-concrete-plan-context plan))
                   (content
                    (emacsvox-aural-concrete-plan-content plan)))
              (should (= (length plans) 1))
              (should
               (eq
                (plist-get context :icons-enabled)
                icons-enabled))
              (should
               (eq
                (plist-get context :face-presentation-enabled)
                face-presentation))
              (should
               (eq
                (plist-get context :voice-lock-enabled)
                voice-lock-enabled))
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
                (and voice-lock-enabled
                     'voice-monotone-extra))))))))))

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
      (should (equal events '(text))))))

(ert-deftest emacsvox-magit-process-feedback-is-asynchronous-and-accurate ()
  "Only asynchronous Magit completion gets feedback, using its true result."
  (let (events)
    (cl-letf
        (((symbol-function 'processp)
          (lambda (value) (eq value 'failed-process)))
         ((symbol-function 'process-get)
          (lambda (&rest _) nil))
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

(ert-deftest emacsvox-magit-synchronous-operation-has-one-lifecycle ()
  "A synchronous Git boundary reports start and its actual exit status."
  (let ((ems--interactive-fn-name 'magit-branch-delete)
        calls)
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
             calls))))
      (should
       (zerop
        (emacsvox-magit--call-synchronous-operation
         (lambda (&rest _) 0)
         '("branch" "--delete" "topic"))))
      (should-not ems--interactive-fn-name)
      (should
       (equal
        (nreverse calls)
        '(("Started branch delete"
           (:role vcs-view :vcs-view-kind other
            :vcs-operation magit-branch-delete)
           (progress))
          ("Completed branch delete"
           (:role vcs-view :vcs-view-kind other
            :vcs-operation magit-branch-delete
            :events (operation-completed))
           (task-done))))))))

(ert-deftest emacsvox-magit-synchronous-operation-reports-failure ()
  "A nonzero exit and a signaled error are failures, never completions."
  (dolist
      (case
       `((7 7)
         (error
          ,(lambda (&rest _)
             (signal 'magit-git-error '("deliberate failure"))))))
    (let ((ems--interactive-fn-name 'magit-reset-hard)
          calls)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest _)
              (push content calls))))
        (pcase-let ((`(,kind ,value) case))
          (if (eq kind 'error)
              (should-error
               (emacsvox-magit--call-synchronous-operation value nil)
               :type 'magit-git-error)
            (should
             (equal
              (emacsvox-magit--call-synchronous-operation
               (lambda (&rest _) value)
               nil)
              value))))
        (should
         (equal
          (nreverse calls)
          '("Started reset hard" "Failed reset hard")))))))

(ert-deftest emacsvox-magit-dedicated-operation-retains-ownership ()
  "A command with specific feedback bypasses the generic Git boundary."
  (let ((ems--interactive-fn-name 'magit-stage)
        (called 0))
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit)
          (lambda (&rest _)
            (ert-fail "Generic operation feedback was submitted"))))
      (should
       (eq
        (emacsvox-magit--call-synchronous-operation
         (lambda (&rest _)
           (cl-incf called)
           'specific-result)
         nil)
        'specific-result))
      (should (= called 1))
      (should (eq ems--interactive-fn-name 'magit-stage)))))

(ert-deftest emacsvox-magit-remote-input-defers-to-asynchronous-boundary ()
  "Remote input operations leave lifecycle ownership to their process."
  (let ((ems--interactive-fn-name 'magit-apply-patch)
        marker-at-call)
    (cl-letf
        (((symbol-function 'file-remote-p)
          (lambda (&rest _) "/ssh:example:"))
         ((symbol-function 'emacsvox-aural-submit)
          (lambda (&rest _)
            (ert-fail "Synchronous operation feedback was submitted"))))
      (should
       (eq
        (emacsvox--advice-magit-run-git-with-input-around
         (lambda (&rest _)
           (setq marker-at-call ems--interactive-fn-name)
           'remote-result)
         "apply")
        'remote-result))
      (should (eq marker-at-call 'magit-apply-patch))
      (should (eq ems--interactive-fn-name 'magit-apply-patch)))))

(ert-deftest emacsvox-magit-asynchronous-operation-carries-identity ()
  "An asynchronous process retains its initiating command until completion."
  (let ((ems--interactive-fn-name 'magit-push-current-to-pushremote)
        properties
        calls)
    (cl-letf
        (((symbol-function 'process-put)
          (lambda (_process property value)
            (push (cons property value) properties)))
         ((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (push (list content (plist-get arguments :facts)) calls))))
      (should
       (eq
        (emacsvox--advice-magit-start-process-around
         (lambda (&rest _) 'fake-process)
         "git" nil "push")
        'fake-process))
      (should-not ems--interactive-fn-name)
      (should
       (equal
        properties
        '((emacsvox-magit-operation-label
           . "push current to pushremote")
          (emacsvox-magit-operation
           . magit-push-current-to-pushremote))))
      (should
       (equal
        calls
        '(("Started push current to pushremote"
           (:role vcs-view :vcs-view-kind other
            :vcs-operation magit-push-current-to-pushremote))))))))

(ert-deftest emacsvox-magit-process-completion-uses-operation-identity ()
  "Process completion reports the operation stored at dispatch time."
  (let (calls)
    (cl-letf
        (((symbol-function 'processp)
          (lambda (value) (eq value 'fake-process)))
         ((symbol-function 'process-status)
          (lambda (_) 'exit))
         ((symbol-function 'process-exit-status)
          (lambda (_) 0))
         ((symbol-function 'process-get)
          (lambda (_process property)
            (pcase property
              ('emacsvox-magit-operation
               'magit-push-current-to-pushremote)
              ('emacsvox-magit-operation-label
               "push current to pushremote"))))
         ((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (push
             (list
              content
              (plist-get arguments :facts)
              (mapcar
               #'emacsvox-aural-compatibility-action-value
               (plist-get arguments :compatibility-actions)))
             calls))))
      (emacsvox--advice-magit-process-finish-after 'fake-process)
      (should
       (equal
        calls
        '(("Completed push current to pushremote"
           (:role vcs-process :events (operation-completed)
            :vcs-operation magit-push-current-to-pushremote)
           (task-done))))))))

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
          (((symbol-function 'scroll-up)
            (lambda (&rest _)
              (forward-line 1)))
           ((symbol-function 'emacsvox-aural-submit)
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
         (lambda () (scroll-up))))
      (should
       (equal
        (nreverse events)
        '(("b"
           (:role vcs-view :vcs-view-kind diff
            :events (vcs-diff-scrolled))
           navigation
           (scroll))))))))

;;; Regression coverage against real Magit commands and Git repositories:

(defvar emacsvox-magit-test--calls nil)

(defun emacsvox-magit-test--capture (content &rest arguments)
  (push (cons content arguments) emacsvox-magit-test--calls))

(defun emacsvox-magit-test--git (&rest arguments)
  (with-temp-buffer
    (should (zerop (apply #'process-file "git" nil t nil arguments)))
    (string-trim (buffer-string))))

(defmacro emacsvox-magit-test--with-repository (&rest body)
  "Run BODY in an isolated Git repository, capturing speech submissions."
  (declare (indent 0))
  `(let* ((directory (file-name-as-directory (make-temp-file "emacsvox-magit-" t)))
          (default-directory directory)
          (process-environment (append '("GIT_CONFIG_GLOBAL=/dev/null"
                                         "GIT_CONFIG_NOSYSTEM=1")
                                       process-environment))
          (magit-auto-revert-mode nil)
          (magit-save-repository-buffers nil)
          (magit-pre-call-git-hook nil)
          (magit-credential-hook nil)
          (magit-process-raise-error nil)
          (magit-inhibit-refresh t)
          (magit-wip-mode nil)
          (emacsvox-magit-test--calls nil))
     (unwind-protect
         (progn
           (emacsvox-magit-test--git "init" "-q" "-b" "main")
           (emacsvox-magit-test--git "config" "user.name" "Speech Test")
           (emacsvox-magit-test--git "config" "user.email" "test@example.invalid")
           (write-region "initial\n" nil "sample.txt" nil 'silent)
           (emacsvox-magit-test--git "add" "sample.txt")
           (emacsvox-magit-test--git "commit" "-qm" "Fixture")
           (with-temp-buffer
             (cl-letf (((symbol-function 'emacsvox-aural-submit)
                        #'emacsvox-magit-test--capture)
                       ((symbol-function 'emacsvox-aural-submit-actions)
                        (lambda (&rest args)
                          (apply #'emacsvox-magit-test--capture nil args))))
               ,@body)))
       (dolist (buffer (buffer-list))
         (when (with-current-buffer buffer
                 (string-prefix-p directory default-directory))
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer)))
       (delete-directory directory t))))

(ert-deftest emacsvox-magit-real-staging-and-unstaging-identify-files ()
  (emacsvox-magit-test--with-repository
    (write-region "modified\n" nil "sample.txt" nil 'silent)
    (funcall-interactively #'magit-stage-files '("sample.txt"))
    (should (equal (emacsvox-magit-test--git "diff" "--cached" "--name-only")
                   "sample.txt"))
    (should (equal (mapcar #'car emacsvox-magit-test--calls) '("Staged sample.txt")))
    (should (equal (plist-get (plist-get (cdar emacsvox-magit-test--calls) :facts)
                              :events) '(entry-staged)))
    (setq emacsvox-magit-test--calls nil)
    (funcall-interactively #'magit-unstage-files '("sample.txt"))
    (should (string-empty-p (emacsvox-magit-test--git "diff" "--cached" "--name-only")))
    (should (equal (mapcar #'car emacsvox-magit-test--calls) '("Unstaged sample.txt")))
    (should (equal (plist-get (plist-get (cdar emacsvox-magit-test--calls) :facts)
                              :events) '(entry-unstaged)))))

(ert-deftest emacsvox-magit-real-stage-failure-never-emits-staged ()
  (emacsvox-magit-test--with-repository
    (write-region "modified\n" nil "sample.txt" nil 'silent)
    (write-region "" nil ".git/index.lock" nil 'silent)
    (funcall-interactively #'magit-stage-modified)
    (should (string-empty-p (emacsvox-magit-test--git "diff" "--cached" "--name-only")))
    (should (equal (mapcar #'car emacsvox-magit-test--calls) '("Failed to stage changes")))
    (let ((facts (plist-get (cdar emacsvox-magit-test--calls) :facts)))
      (should (equal (plist-get facts :events) '(operation-failed)))
      (should-not (plist-get facts :states)))))

(ert-deftest emacsvox-magit-real-stage-error-is-preserved ()
  (emacsvox-magit-test--with-repository
    (write-region "modified\n" nil "sample.txt" nil 'silent)
    (write-region "" nil ".git/index.lock" nil 'silent)
    (let ((magit-process-raise-error t))
      (should-error (funcall-interactively #'magit-stage-files '("sample.txt"))
                    :type 'magit-git-error))
    (should (equal (mapcar #'car emacsvox-magit-test--calls)
                   '("Failed to stage sample.txt")))))

(ert-deftest emacsvox-magit-nested-staging-has-one-owner ()
  (emacsvox-magit-test--with-repository
    (write-region "modified\n" nil "sample.txt" nil 'silent)
    (let ((ems--interactive-fn-name 'magit-stage))
      (emacsvox-magit--call-checked-operation
       (lambda () (funcall-interactively #'magit-stage-files '("sample.txt")))
       'magit-stage nil))
    (should (= (length emacsvox-magit-test--calls) 1))
    (should (equal (plist-get (plist-get (cdar emacsvox-magit-test--calls) :facts)
                              :events) '(entry-staged)))))

(ert-deftest emacsvox-magit-programmatic-staging-remains-silent ()
  (emacsvox-magit-test--with-repository
    (write-region "modified\n" nil "sample.txt" nil 'silent)
    (magit-stage-files '("sample.txt"))
    (should (equal (emacsvox-magit-test--git "diff" "--cached" "--name-only")
                   "sample.txt"))
    (should-not emacsvox-magit-test--calls)))

(ert-deftest emacsvox-magit-real-checkout-rename-and-stash-are-spoken ()
  (emacsvox-magit-test--with-repository
    (emacsvox-magit-test--git "branch" "topic")
    (funcall-interactively #'magit-branch-checkout "topic")
    (should (equal (emacsvox-magit-test--git "branch" "--show-current") "topic"))
    (should (equal (mapcar #'car (reverse emacsvox-magit-test--calls))
                   '("Started branch checkout" "Completed branch checkout")))
    (setq emacsvox-magit-test--calls nil)
    (funcall-interactively #'magit-branch-rename "topic" "renamed")
    (should (equal (emacsvox-magit-test--git "branch" "--show-current") "renamed"))
    (should (equal (mapcar #'car (reverse emacsvox-magit-test--calls))
                   '("Started branch rename" "Completed branch rename")))
    (setq emacsvox-magit-test--calls nil)
    (write-region "modified\n" nil "sample.txt" nil 'silent)
    (funcall-interactively #'magit-stash-both "Saved work")
    (should (string-match-p "Saved work" (emacsvox-magit-test--git "stash" "list")))
    (should (string-empty-p (emacsvox-magit-test--git "diff" "--name-only")))
    (should (equal (mapcar #'car (reverse emacsvox-magit-test--calls))
                   '("Started stash both" "Completed stash both")))))

(ert-deftest emacsvox-magit-checked-operation-retains-earlier-failures ()
  (let ((ems--interactive-fn-name 'magit-branch-rename)
        (emacsvox-magit-test--calls nil))
    (cl-letf (((symbol-function 'emacsvox-aural-submit) #'emacsvox-magit-test--capture))
      (should
       (eq 'original-result
           (emacsvox-magit--call-checked-operation
            (lambda (&rest _)
              (emacsvox--advice-magit-process-finish-around #'identity 1)
              (emacsvox--advice-magit-process-finish-around #'identity 0)
              'original-result)
            'magit-branch-rename '("old" "new")))))
    (should (equal (mapcar #'car (reverse emacsvox-magit-test--calls))
                   '("Started branch rename" "Failed branch rename")))))

(ert-deftest emacsvox-magit-real-remote-rename-remove-and-noop ()
  (emacsvox-magit-test--with-repository
    (emacsvox-magit-test--git "remote" "add" "origin" directory)
    (funcall-interactively #'magit-remote-rename "origin" "upstream")
    (should (equal (emacsvox-magit-test--git "remote") "upstream"))
    (should (equal (mapcar #'car (reverse emacsvox-magit-test--calls))
                   '("Started remote rename" "Completed remote rename")))
    (setq emacsvox-magit-test--calls nil)
    (funcall-interactively #'magit-remote-rename "upstream" "upstream")
    (should (equal (caar emacsvox-magit-test--calls) "No change for remote rename"))
    (should-not (plist-get (plist-get (cdar emacsvox-magit-test--calls) :facts) :events))
    (setq emacsvox-magit-test--calls nil)
    (funcall-interactively #'magit-remote-remove "upstream")
    (should (string-empty-p (emacsvox-magit-test--git "remote")))
    (should (equal (mapcar #'car (reverse emacsvox-magit-test--calls))
                   '("Started remote remove" "Completed remote remove")))))

(ert-deftest emacsvox-magit-new-branch-keeps-asynchronous-lifecycle ()
  (emacsvox-magit-test--with-repository
    (funcall-interactively #'magit-branch-checkout "created" "main")
    (let ((process magit-this-process))
      (should-not (process-get process 'emacsvox-magit-collected))
      (with-timeout (5 (ert-fail "Checkout process did not finish"))
        (while (eq magit-this-process process) (accept-process-output nil 0.05)))
      (should (equal (emacsvox-magit-test--git "branch" "--show-current") "created"))
      (should (equal (mapcar #'car (reverse emacsvox-magit-test--calls))
                     '("Started branch checkout" "Completed branch checkout")))
      (should (eq (plist-get (cdar emacsvox-magit-test--calls) :lane) 'notification)))))

(ert-deftest emacsvox-magit-waited-process-has-one-command-result ()
  (emacsvox-magit-test--with-repository
    (let ((ems--interactive-fn-name 'magit-remote-remove)
          process)
      (emacsvox-magit--call-checked-operation
       (lambda ()
         ;; Exercise the start-and-wait lifecycle used by remote Git calls.
         (setq process (magit-start-process "git" nil "status" "--short"))
         (set-process-sentinel process #'ignore)
         (with-timeout (5 (ert-fail "Git process did not finish"))
           (while (process-live-p process) (accept-process-output process 0.05))))
       'magit-remote-remove nil)
      (should (equal (process-get process 'emacsvox-magit-collected) [1 nil]))
      ;; A delayed sentinel still updates Magit but produces no second result.
      (magit-process-sentinel process "finished\n"))
    (should (equal (mapcar #'car (reverse emacsvox-magit-test--calls))
                   '("Started remote remove" "Completed remote remove")))
    (should (eq (plist-get (cdar emacsvox-magit-test--calls) :lane) 'main))))

(ert-deftest emacsvox-magit-real-fetch-reports-partial-failure ()
  (emacsvox-magit-test--with-repository
    (emacsvox-magit-test--git "remote" "add" "origin"
                             (expand-file-name "missing-remote.git"))
    (let ((other (expand-file-name "second/")))
      (make-directory other)
      (let ((default-directory other)) (emacsvox-magit-test--git "init" "-q"))
      (funcall-interactively #'magit-repolist-fetch (list directory other)))
    (should (equal (mapcar #'car (reverse emacsvox-magit-test--calls))
                   '("Fetching 2 repositories" "Fetched 1 of 2 repositories; 1 failed")))
    (should (equal (plist-get (plist-get (cdar emacsvox-magit-test--calls) :facts)
                              :events) '(operation-failed)))))

(ert-deftest emacsvox-magit-real-fetch-failure-is-never-success ()
  (emacsvox-magit-test--with-repository
    (emacsvox-magit-test--git "remote" "add" "origin"
                             (expand-file-name "missing-remote.git"))
    (funcall-interactively #'magit-repolist-fetch (list directory))
    (should (equal (mapcar #'car (reverse emacsvox-magit-test--calls))
                   '("Fetching 1 repository" "Failed to fetch 1 repository")))))

(ert-deftest emacsvox-magit-real-fetch-success-is-confirmed ()
  (emacsvox-magit-test--with-repository
    (funcall-interactively #'magit-repolist-fetch (list directory))
    (should (equal (mapcar #'car (reverse emacsvox-magit-test--calls))
                   '("Fetching 1 repository" "Fetched 1 repository")))))

(defmacro emacsvox-magit-test--with-sections (&rest body)
  "Run BODY in a displayed section tree with two commit rows."
  (declare (indent 0))
  `(save-window-excursion
     (with-temp-buffer
       (switch-to-buffer (current-buffer))
       (magit-section-mode)
       (emacsvox-magit-enable-aural-context)
       (let ((inhibit-read-only t))
         (magit-insert-section (root)
           (magit-insert-section (recent)
             (magit-insert-heading "Recent commits")
             (magit-insert-section (commit "123456789")
               (insert (propertize "123456789" 'font-lock-face 'magit-hash)
                       " First commit\n")
               (magit-insert-heading))
             (magit-insert-section (commit "abcdef123")
               (insert (propertize "abcdef123" 'font-lock-face 'magit-hash)
                       " Second commit\n")
               (magit-insert-heading))
             (insert "\n"))))
       (goto-char (point-min))
       ,@body)))

(ert-deftest emacsvox-magit-level-one-reports-actual-collapse ()
  (emacsvox-magit-test--with-sections
    (let (call)
      (cl-letf (((symbol-function 'emacsvox-aural-submit)
                 (lambda (text &rest args) (setq call (cons text args)))))
        (funcall-interactively #'magit-section-show-level-1))
      (should (oref (magit-current-section) hidden))
      (should (string-prefix-p "Collapsed." (car call)))
      (should (eq (plist-get (plist-get (cdr call) :facts) :visibility) 'folded))
      (should (eq (emacsvox-aural-compatibility-action-value
                   (car (plist-get (cdr call) :compatibility-actions))) 'close-object)))))

(ert-deftest emacsvox-magit-show-children-distinguishes-hidden-bodies ()
  (with-temp-buffer
    (magit-section-mode)
    (let ((inhibit-read-only t) call)
      (magit-insert-section (root)
        (magit-insert-section (file "sample.txt")
          (magit-insert-heading "sample.txt")
          (magit-insert-section (body)
            (magit-insert-heading "Hunk")
            (insert "+content\n"))))
      (goto-char (point-min))
      (cl-letf (((symbol-function 'emacsvox-aural-submit)
                 (lambda (text &rest args) (setq call (cons text args)))))
        (funcall-interactively #'magit-section-show-children (magit-current-section) 0))
      (should (string-prefix-p "Headings shown." (car call)))
      (should (eq (plist-get (plist-get (cdr call) :facts) :visibility) 'expanded))
      (cl-letf (((symbol-function 'emacsvox-aural-submit)
                 (lambda (text &rest args) (setq call (cons text args)))))
        (funcall-interactively #'magit-section-show-headings (magit-current-section)))
      ;; Follow actual visibility even when Magit's implementation differs
      ;; from the show-headings command's advertised behavior.
      (should (string-prefix-p "Expanded." (car call))))))

(ert-deftest emacsvox-magit-copy-empty-heading-does-not-claim-old-kill ()
  (emacsvox-magit-test--with-sections
    (let ((kill-ring '("unrelated old text"))
          (emacsvox-magit-test--calls nil))
      (cl-letf (((symbol-function 'emacsvox-aural-submit) #'emacsvox-magit-test--capture))
        (funcall-interactively #'magit-copy-section-value nil))
      (should (equal kill-ring '("unrelated old text")))
      (should (equal (mapcar #'car emacsvox-magit-test--calls) '("Nothing to copy here"))))))

(ert-deftest emacsvox-magit-recopying-identical-content-is-acknowledged ()
  (let ((kill-ring '("same"))
        (kill-do-not-save-duplicates t)
        (ems--interactive-fn-name 'magit-copy-section-value)
        (emacsvox-magit-test--calls nil))
    (cl-letf (((symbol-function 'emacsvox-aural-submit) #'emacsvox-magit-test--capture))
      (emacsvox-magit--call-copy-command
       (lambda () (kill-new "same")) 'magit-copy-section-value nil))
    (should (equal (mapcar #'car emacsvox-magit-test--calls) '("Copied. same")))))

(ert-deftest emacsvox-magit-blank-navigation-uses-core-tone-without-icon ()
  (dolist (case '(("" empty line-empty) ("  " whitespace-only line-whitespace)))
    (emacsvox-magit-test--with-sections
      (goto-char (point-max))
      (forward-line -1)
      (let ((inhibit-read-only t)) (insert (car case)))
      (forward-line -1)
      (let ((emacsvox-use-icons t)
            submission)
        (cl-letf (((symbol-function 'tts-stop) #'ignore)
                  ((symbol-function 'emacsvox-queue-resource) #'ignore)
                  ((symbol-function 'tts-tone) #'ignore))
          (let ((submit (symbol-function 'emacsvox-aural-submit-actions)))
            (cl-letf (((symbol-function 'emacsvox-aural-submit-actions)
                       (lambda (&rest args)
                         (setq submission (apply submit args)))))
              (funcall-interactively #'magit-next-line 1 nil))))
        (let* ((plan (car (emacsvox-aural-submission-plans submission)))
               (actions (emacsvox-aural-concrete-plan-before plan)))
          (should (eq (emacsvox-aural-submission-lane submission) 'main))
          (should (eq (emacsvox-aural-submission-interruption-policy submission) 'lane))
          (should (= (length actions) 1))
          (should (eq (emacsvox-aural-concrete-action-tone (car actions)) (nth 2 case))))))))

(ert-deftest emacsvox-magit-hash-voice-survives-forward-and-backward-highlighting ()
  (dolist (voice '(inaudible voice-lighten))
    (emacsvox-magit-test--with-sections
      (setq-local voice-setup-local-map (make-hash-table :test #'eq))
      (puthash 'magit-hash voice voice-setup-local-map)
      (forward-line 1)
      (magit-section-update-highlight t)
      (let (styles)
        (cl-letf (((symbol-function 'tts-stop) #'ignore)
                  ((symbol-function 'emacsvox-aural-submit)
                   (lambda (text &rest _)
                     (push (emacsvox-aural--string-style text 0) styles))))
          (dolist (command '(magit-next-line magit-previous-line))
            (magit-section-pre-command-hook)
            (funcall-interactively command 1 nil)
            (magit-section-post-command-hook)))
        (should (equal styles (list voice voice))))
      (should-not (get-text-property (point) 'personality))
      ;; Explicit line/region reading uses captured overlay faces as well.
      (let* ((text (emacsvox-aural-source-substring
                    (line-beginning-position) (line-end-position)))
             (snapshot (emacsvox-aural--string-face-snapshot text 0)))
        (should (eq (emacsvox-aural--string-style text 0 snapshot) voice))))))

(ert-deftest emacsvox-magit-highlighting-preserves-deliberate-personalities ()
  (emacsvox-magit-test--with-sections
    (forward-line 1)
    (let ((inhibit-read-only t))
      (put-text-property (point) (1+ (point)) 'personality 'voice-animate))
    (magit-section-update-highlight t)
    (let ((overlay (car magit-section-highlight-overlays)))
      ;; Font Lock can later copy font-lock-face into face outside Magit.
      (overlay-put overlay 'face 'magit-section-highlight)
      (move-overlay overlay (1+ (point)) (line-end-position))
      (delete-overlay overlay))
    (should (eq (get-text-property (point) 'personality) 'voice-animate))))

(ert-deftest emacsvox-magit-completion-and-entry-have-independent-lanes ()
  (let ((process (make-process :name "emacsvox-magit-test" :command '("true")
                               :sentinel #'ignore :noquery t))
        (emacsvox-use-icons t))
    (unwind-protect
        (progn
          (while (process-live-p process) (accept-process-output process 0.05))
          (process-put process 'emacsvox-magit-operation 'magit-fetch)
          (process-put process 'emacsvox-magit-operation-label "fetch")
          (cl-letf (((symbol-function 'tts-speak) #'ignore)
                    ((symbol-function 'tts-stop) #'ignore)
                    ((symbol-function 'emacsvox-queue-resource) #'ignore))
            (let ((submission (emacsvox--advice-magit-process-finish-after process)))
              (should (eq (emacsvox-aural-submission-lane submission) 'notification))
              (should (eq (emacsvox-aural-submission-interruption-policy submission) 'none))
              (should (eq (emacsvox-aural-concrete-action-cue
                           (car (emacsvox-aural-concrete-plan-before
                                 (car (emacsvox-aural-submission-plans submission)))))
                          'task-done)))
            (with-temp-buffer
              (insert "Head: main")
              (let* ((ems--interactive-fn-name 'magit-status)
                     (submission (emacsvox--advice-magit-status-after)))
                (should (eq (emacsvox-aural-submission-lane submission) 'main))
                (should (eq (emacsvox-aural-submission-interruption-policy submission) 'lane))))))
      (when (process-live-p process) (delete-process process)))))

(ert-deftest emacsvox-magit-observer-ignores-unrelated-process-completion ()
  (let* ((process (make-pipe-process :name "emacsvox-magit-unrelated"
                                    :sentinel #'ignore :noquery t))
         (emacsvox-magit--git-results (vector 0 nil)))
    (unwind-protect
        (progn
          (emacsvox--advice-magit-process-finish-around #'identity process)
          (should (equal emacsvox-magit--git-results [0 nil]))
          (process-put process 'emacsvox-magit-collected emacsvox-magit--git-results)
          (dotimes (_ 2)
            (emacsvox--advice-magit-process-finish-around #'identity process))
          (should (equal emacsvox-magit--git-results [1 nil])))
      (delete-process process))))

(provide 'emacsvox-magit-tests)
;;; emacsvox-magit-tests.el ends here
