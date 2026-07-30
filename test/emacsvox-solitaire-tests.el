;;; emacsvox-solitaire-tests.el --- Solitaire advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Solitaire advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'solitaire)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-solitaire.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--solitaire-after-targets
  '(solitaire-left
    solitaire-right
    solitaire-up
    solitaire-down
    solitaire-center-point
    solitaire-move
    solitaire-move-right
    solitaire-move-left
    solitaire-move-up
    solitaire-move-down)
  "Current Solitaire commands using direct after advice.")

(ert-deftest emacsvox-solitaire-advice-is-directly-registered ()
  "Solitaire advice is attached directly to current Emacs 31 commands."
  (dolist (target emacsvox-test--solitaire-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (commandp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-solitaire-omits-removed-quit-command ()
  "The integration does not recreate the removed Solitaire quit command."
  (should-not (fboundp 'solitaire-quit))
  (should-not
   (fboundp 'emacsvox--advice-solitaire-quit-after))
  (should
   (eq (lookup-key solitaire-mode-map "q") 'quit-window)))

(ert-deftest emacsvox-solitaire-cell-policy-uses-named-tones ()
  "Stone and hole meanings resolve across supported interaction occasions."
  (let ((emacsvox-aural-active-scheme 'default)
        (emacsvox-aural-user-rules nil)
        (emacsvox-aural-session-rules nil)
        (emacsvox-aural-buffer-rules nil)
        (emacsvox-aural-enabled-feature-fragments nil)
        (emacsvox-aural--current-rules-cache
         (make-hash-table :test #'equal)))
    (dolist
        (case
         '((stone solitaire-stone-tone solitaire-stone)
           (hole solitaire-hole-tone solitaire-hole)))
      (dolist (occasion '(inspection navigation state-change))
        (let* ((plan
                (emacsvox-aural-resolve-active
                 (list :role 'game-cell :game-cell-kind (car case))
                 (list
                  :module 'solitaire
                  :mode 'solitaire-mode
                  :occasion occasion)))
               (action (car (emacsvox-aural-render-plan-before plan))))
          (should
           (equal
            (emacsvox-aural-render-plan-matched-rules plan)
            (list (nth 1 case))))
          (should (eq (emacsvox-aural-action-kind action) 'tone))
          (should (eq (emacsvox-aural-action-tone action) (nth 2 case))))))))

(ert-deftest emacsvox-solitaire-cell-tone-adapters-submit-meaning ()
  "Legacy stone and hole functions submit semantic cell facts."
  (let (submissions)
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit-actions)
          (lambda (&rest arguments)
            (push arguments submissions))))
      (emacsvox-solitaire-stone)
      (emacsvox-solitaire-hole))
    (should
     (equal
      (nreverse submissions)
      '((:facts (:role game-cell :game-cell-kind stone)
         :module solitaire
         :occasion inspection
         :compatibility-actions nil)
        (:facts (:role game-cell :game-cell-kind hole)
         :module solitaire
         :occasion inspection
         :compatibility-actions nil))))))

(ert-deftest emacsvox-solitaire-coordinates-are-one-native-cell ()
  "Coordinates, cell meaning, and a leading cue share one submission."
  (let (submitted)
    (cl-letf
        (((symbol-function 'emacsvox-solitaire--cell-kind)
          (lambda (&optional _) 'stone))
         ((symbol-function 'emacsvox-solitaire-current-row)
          (lambda () 4))
         ((symbol-function 'emacsvox-solitaire-current-column)
          (lambda () 3))
         ((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (setq submitted (cons content arguments)))))
      (emacsvox-solitaire-speak-coordinates
       'select-object 'navigation))
    (should (equal (car submitted) "stone at 4 3"))
    (should
     (equal
      (plist-get (cdr submitted) :facts)
      '(:role game-cell :game-cell-kind stone)))
    (should (eq (plist-get (cdr submitted) :module) 'solitaire))
    (should (eq (plist-get (cdr submitted) :occasion) 'navigation))
    (should
     (equal
      (mapcar
       #'emacsvox-aural-compatibility-action-value
       (plist-get (cdr submitted) :compatibility-actions))
      '(select-object)))))

(ert-deftest emacsvox-solitaire-stone-count-is-native-game-status ()
  "Remaining-stone feedback uses game status rather than raw speech."
  (let ((solitaire-stones 17)
        submitted)
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (setq submitted (cons content arguments)))))
      (emacsvox-solitaire-speak-stones))
    (should (equal (car submitted) "17 stones"))
    (should
     (equal
      (plist-get (cdr submitted) :facts)
      '(:role game-status :game-piece-count 17)))
    (should (eq (plist-get (cdr submitted) :occasion) 'inspection))))

(ert-deftest emacsvox-solitaire-row-inspection-uses-first-class-tones ()
  "Row inspection submits cell meanings instead of legacy cell icons."
  (with-temp-buffer
    (insert "o   .   o")
    (goto-char (point-min))
    (let (cells)
      (cl-letf
          (((symbol-function 'emacsvox-solitaire--present-cell-tone)
            (lambda (kind) (push kind cells))))
        (emacsvox-solitaire-show-row))
      (should (equal (nreverse cells) '(stone hole stone))))))

(ert-deftest emacsvox-solitaire-column-inspection-uses-first-class-tones ()
  "Column inspection traverses the board and submits each cell meaning."
  (let ((characters '(?o ?. ?o ?o ?. ?. ?o))
        (up-count 0)
        (down-count 0)
        cells)
    (cl-letf
        (((symbol-function 'emacsvox-solitaire-current-row)
          (lambda () 4))
         ((symbol-function 'emacsvox-solitaire-current-column)
          (lambda () 4))
         ((symbol-function 'solitaire-up)
          (lambda () (cl-incf up-count)))
         ((symbol-function 'solitaire-down)
          (lambda () (cl-incf down-count)))
         ((symbol-function 'char-after)
          (lambda (&optional _) (pop characters)))
         ((symbol-function 'emacsvox-solitaire--present-cell-tone)
          (lambda (kind) (push kind cells))))
      (emacsvox-solitaire-show-column))
    (should (= up-count 3))
    (should (= down-count 6))
    (should
     (equal
      (nreverse cells)
      '(stone hole stone stone hole hole stone)))))

(ert-deftest emacsvox-solitaire-spoken-row-is-native-game-status ()
  "Verbal row inspection submits source text through the aural model."
  (with-temp-buffer
    (insert "o   .   o")
    (goto-char (point-min))
    (let (submitted)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq submitted (cons content arguments)))))
        (emacsvox-solitaire-speak-row))
      (should (equal (car submitted) "o   .   o"))
      (should
       (equal
        (plist-get (cdr submitted) :facts)
        '(:role game-status)))
      (should (eq (plist-get (cdr submitted) :occasion) 'inspection)))))

(ert-deftest emacsvox-solitaire-horizontal-feedback-is-target-aware ()
  "Horizontal movement optionally announces the current column."
  (let ((ems--interactive-fn-name 'solitaire-right)
        (emacsvox-solitaire-autoshow t)
        events)
    (cl-letf (((symbol-function 'emacsvox-solitaire-show-column)
               (lambda () (push 'column events)))
              ((symbol-function 'emacsvox-solitaire-speak-coordinates)
               (lambda (&rest arguments)
                 (push (cons 'coordinates arguments) events))))
      (emacsvox--advice-solitaire-left-after)
      (emacsvox--advice-solitaire-right-after))
    (should
     (equal
      (nreverse events)
      '(column (coordinates select-object navigation))))))

(ert-deftest emacsvox-solitaire-vertical-feedback-is-target-aware ()
  "Vertical movement optionally announces the current row."
  (let ((ems--interactive-fn-name 'solitaire-up)
        (emacsvox-solitaire-autoshow t)
        events)
    (cl-letf (((symbol-function 'emacsvox-solitaire-show-row)
               (lambda () (push 'row events)))
              ((symbol-function 'emacsvox-solitaire-speak-coordinates)
               (lambda (&rest arguments)
                 (push (cons 'coordinates arguments) events))))
      (emacsvox--advice-solitaire-up-after)
      (emacsvox--advice-solitaire-down-after))
    (should
     (equal
      (nreverse events)
      '(row (coordinates select-object navigation))))))

(ert-deftest emacsvox-solitaire-autoshow-can-be-disabled ()
  "Normal navigation still announces coordinates without autoshow."
  (let ((ems--interactive-fn-name 'solitaire-left)
        (emacsvox-solitaire-autoshow nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-solitaire-show-column)
               (lambda () (push 'column events)))
              ((symbol-function 'emacsvox-solitaire-speak-coordinates)
               (lambda (&rest arguments)
                 (push (cons 'coordinates arguments) events))))
      (emacsvox--advice-solitaire-left-after))
    (should
     (equal
      (nreverse events)
      '((coordinates select-object navigation))))))

(ert-deftest emacsvox-solitaire-center-feedback-is-target-aware ()
  "Center movement has distinct large-movement feedback."
  (let ((ems--interactive-fn-name 'solitaire-center-point)
        events)
    (cl-letf
        (((symbol-function 'emacsvox-solitaire-speak-coordinates)
          (lambda (&rest arguments)
            (push (cons 'coordinates arguments) events))))
      (emacsvox--advice-solitaire-center-point-after))
    (should
     (equal
      (nreverse events)
      '((coordinates large-movement navigation))))))

(ert-deftest emacsvox-solitaire-stone-move-reports-once ()
  "A nested directional move reports one native completion result."
  (let ((ems--interactive-fn-name 'solitaire-move-right)
        events)
    (cl-letf
        (((symbol-function 'emacsvox-solitaire-speak-coordinates)
          (lambda (&rest arguments)
            (push (cons 'coordinates arguments) events))))
      (emacsvox--advice-solitaire-move-after)
      (emacsvox--advice-solitaire-move-right-after))
    (should
     (equal
      (nreverse events)
      '((coordinates item state-change operation-completed))))))

(ert-deftest emacsvox-solitaire-programmatic-navigation-is-quiet ()
  "Cursor navigation emits no feedback outside interactive dispatch."
  (let ((emacsvox-solitaire-autoshow t)
        events)
    (cl-letf (((symbol-function 'emacsvox-solitaire-show-column)
               (lambda () (push 'column events)))
              ((symbol-function 'emacsvox-solitaire-speak-coordinates)
               (lambda (&rest arguments)
                 (push (cons 'coordinates arguments) events))))
      (emacsvox--advice-solitaire-left-after)
      (emacsvox--advice-solitaire-center-point-after)
      (emacsvox--advice-solitaire-move-after)
      (emacsvox--advice-solitaire-move-left-after))
    (should-not events)))

(ert-deftest emacsvox-solitaire-setup-submits-welcome-once ()
  "Solitaire setup records module context and owns welcome presentation."
  (with-temp-buffer
    (let ((emacsvox-speak-messages t)
          message-state
          submission)
      (cl-letf
          (((symbol-function 'delete-other-windows) #'ignore)
           ((symbol-function 'emacsvox-solitaire-setup-keymap) #'ignore)
           ((symbol-function 'message)
            (lambda (&rest _)
              (setq message-state emacsvox-speak-messages)))
           ((symbol-function 'emacsvox-solitaire--submit)
            (lambda (&rest arguments)
              (setq submission arguments))))
        (emacsvox-solitaire-setup))
      (should (eq emacsvox-aural-module 'solitaire))
      (should (local-variable-p 'emacsvox-aural-module))
      (should-not message-state)
      (should
       (equal
        submission
        '("Welcome to Solitaire"
          (:role game-status)
          state-change
          open-object))))))

(provide 'emacsvox-solitaire-tests)
;;; emacsvox-solitaire-tests.el ends here
