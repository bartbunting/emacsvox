;;; emacsvox-mermaid-tests.el --- Spoken graph navigation tests -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Run with run-mermaid-tests.el after installing the pinned optional parser.

;;; Code:

(require 'ert)
(require 'cl-lib)

(defvar emacsvox-mermaid-test--speech nil)

(defun emacsvox-mermaid-test--fixture (name)
  "Read the Mermaid test diagram named NAME."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name (concat "test/fixtures/mermaid/" name ".mmd") emacsvox-directory))
    (buffer-string)))

(defun emacsvox-mermaid-test--wait (predicate)
  "Wait at most three seconds for PREDICATE while servicing process output."
  (let ((deadline (+ (float-time) 3)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.02))
    (should (funcall predicate))))

(defun emacsvox-mermaid-test--parse (text)
  "Parse TEXT using the real helper and return its reply."
  (let (response)
    (emacsvox-mermaid--request text (lambda (reply) (setq response reply)))
    (emacsvox-mermaid-test--wait (lambda () response))
    response))

(defmacro emacsvox-mermaid-test--with-view (text &rest body)
  "Create a source and explorer for TEXT, then execute BODY with speech captured."
  (declare (indent 1))
  `(let ((source (generate-new-buffer " *mermaid-test-source*"))
         (explorer (generate-new-buffer " *mermaid-test-explorer*"))
         (emacsvox-mermaid-test--speech nil))
     (unwind-protect
         (save-window-excursion
           (cl-letf (((symbol-function 'emacsvox-aural-submit)
                      (lambda (text &rest properties)
                        (push (cons text properties) emacsvox-mermaid-test--speech))))
             (let* ((text ,text)
                    (view (with-current-buffer source
                            (insert text)
                            (emacsvox-mermaid--view-create
                             :source source :start (copy-marker (point-min))
                             :end (copy-marker (point-max) t)))))
               (with-current-buffer explorer
                 (emacsvox-mermaid-mode)
                 (setq emacsvox-mermaid--view view)
                 (emacsvox-mermaid--accept explorer view text (emacsvox-mermaid-test--parse text))
                 ,@body))))
       (when (buffer-live-p explorer) (kill-buffer explorer))
       (when (buffer-live-p source) (kill-buffer source)))))

(ert-deftest emacsvox-mermaid-combined-list-orders-and-announces-directions ()
  (emacsvox-mermaid-test--with-view
      "flowchart TD\nA[Here] --> B[First out]\nA --> C[Second out]\nD[First in] --> A\nE[Second in] --> A"
    (should (equal '("B" "C" "D" "E") (mapcar #'cdr (emacsvox-mermaid--items))))
    (emacsvox-mermaid-next)
    (should (equal "Second out. 2 of 2." (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid-next)
    (should (equal "Incoming. From First in. 1 of 2." (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid-next)
    (should (equal "From Second in. 2 of 2." (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid-previous)
    (emacsvox-mermaid-previous)
    (should (equal "Outgoing. Second out. 2 of 2." (caar emacsvox-mermaid-test--speech)))
    (should (equal "A" (emacsvox-mermaid--view-current view)))))

(ert-deftest emacsvox-mermaid-direction-arrows-choose-then-follow ()
  (emacsvox-mermaid-test--with-view
      "flowchart TD\nA[Here] --> B[First out]\nA --> C[Second out]\nD[First in] --> A\nE[Second in] --> A"
    ;; Without a selected connection, the arrow offers its direction's choices.
    (goto-char (point-min))
    (call-interactively (key-binding (kbd "<right>")))
    (should (equal "A" (emacsvox-mermaid--view-current view)))
    (should (equal '("B" "C") (mapcar #'cdr (emacsvox-mermaid--items))))
    (should (equal "Outgoing. First out. 1 of 2." (caar emacsvox-mermaid-test--speech)))
    (call-interactively (key-binding (kbd "<down>")))
    (call-interactively (key-binding (kbd "<right>")))
    (should (equal "C" (emacsvox-mermaid--view-current view)))
    (emacsvox-mermaid-back)
    (should (eq 'outgoing (emacsvox-mermaid--view-section view)))
    (should (= 1 (get-text-property (point) 'emacsvox-mermaid-item)))
    ;; The opposite arrow opens its own choices, not the selected outgoing edge.
    (call-interactively (key-binding (kbd "<left>")))
    (should (equal "A" (emacsvox-mermaid--view-current view)))
    (should (equal '("D" "E") (mapcar #'cdr (emacsvox-mermaid--items))))
    (should (equal "Incoming. From First in. 1 of 2." (caar emacsvox-mermaid-test--speech)))
    (call-interactively (key-binding (kbd "<down>")))
    (call-interactively (key-binding (kbd "RET")))
    (should (equal "E" (emacsvox-mermaid--view-current view)))
    ;; One outgoing edge moves immediately.  The chooser is fresh on return.
    (call-interactively (key-binding (kbd "<right>")))
    (should (equal "A" (emacsvox-mermaid--view-current view)))
    (should (eq 'connections (emacsvox-mermaid--view-section view)))
    (call-interactively (key-binding (kbd "<left>")))
    (should (equal "A" (emacsvox-mermaid--view-current view)))
    (call-interactively (key-binding (kbd "<left>")))
    (should (equal "D" (emacsvox-mermaid--view-current view)))))

(ert-deftest emacsvox-mermaid-support-ticket-selected-connections-follow-immediately ()
  (emacsvox-mermaid-test--with-view
      (emacsvox-mermaid-test--fixture "support-ticket")
    (switch-to-buffer source)
    (pop-to-buffer explorer)
    (call-interactively (key-binding (kbd "<right>")))
    (should (equal "Triage" (emacsvox-mermaid--view-current view)))
    (should (equal '("Guide" "Investigate" "Start") (mapcar #'cdr (emacsvox-mermaid--items))))
    ;; The initial selected Yes row is already a choice, even in a combined list.
    (call-interactively (key-binding (kbd "<right>")))
    (should (equal "Guide" (emacsvox-mermaid--view-current view)))
    (emacsvox-mermaid-back)
    (should (eq 'connections (emacsvox-mermaid--view-section view)))
    (should (= 0 (get-text-property (point) 'emacsvox-mermaid-item)))
    (call-interactively (key-binding (kbd "<down>")))
    (call-interactively (key-binding (kbd "<right>")))
    (should (equal "Investigate" (emacsvox-mermaid--view-current view)))
    (emacsvox-mermaid-back)
    (should (= 1 (get-text-property (point) 'emacsvox-mermaid-item)))
    (call-interactively (key-binding (kbd "<down>")))
    (call-interactively (key-binding (kbd "<left>")))
    (should (equal "Start" (emacsvox-mermaid--view-current view)))
    ;; Left also follows the selected row when there are several incoming edges.
    (emacsvox-mermaid--visit "Resolve")
    (should (equal '("Close" "Guide" "Investigate") (mapcar #'cdr (emacsvox-mermaid--items))))
    ;; Ordinary point movement must take precedence over the remembered index.
    (goto-char (text-property-any (point-min) (point-max) 'emacsvox-mermaid-item 2))
    (call-interactively (key-binding (kbd "<left>")))
    (should (equal "Investigate" (emacsvox-mermaid--view-current view)))
    (emacsvox-mermaid-back)
    (should (equal "Resolve" (emacsvox-mermaid--view-current view)))
    (should (= 2 (get-text-property (point) 'emacsvox-mermaid-item)))
    (emacsvox-mermaid-previous)
    (call-interactively (key-binding (kbd "<left>")))
    (should (equal "Guide" (emacsvox-mermaid--view-current view)))))

(ert-deftest emacsvox-mermaid-selected-two-way-and-undirected-links-follow-either-arrow ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA --> B\nA <--> C\nA --- D\nX --> A"
    (should (equal '("B" "C" "X" "D") (mapcar #'cdr (emacsvox-mermaid--items))))
    (dolist (choice '((1 . "C") (3 . "D")))
      (dolist (key '("<left>" "<right>"))
        (goto-char (text-property-any (point-min) (point-max) 'emacsvox-mermaid-item (car choice)))
        (call-interactively (key-binding (kbd key)))
        (should (equal (cdr choice) (emacsvox-mermaid--view-current view)))
        (emacsvox-mermaid-back)
        (should (equal "A" (emacsvox-mermaid--view-current view)))
        (should (eq 'connections (emacsvox-mermaid--view-section view)))
        (should (= (car choice) (get-text-property (point) 'emacsvox-mermaid-item)))))))

(ert-deftest emacsvox-mermaid-direction-arrows-single-and-empty ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA[Start] --> B[Finish]"
    (call-interactively (key-binding (kbd "<left>")))
    (should (equal "No incoming." (caar emacsvox-mermaid-test--speech)))
    (should (equal "A" (emacsvox-mermaid--view-current view)))
    (should-not (emacsvox-mermaid--view-history view))
    (call-interactively (key-binding (kbd "<right>")))
    (should (equal "B" (emacsvox-mermaid--view-current view)))
    (call-interactively (key-binding (kbd "<right>")))
    (should (equal "No outgoing." (caar emacsvox-mermaid-test--speech)))
    (should (equal "B" (emacsvox-mermaid--view-current view)))
    (call-interactively (key-binding (kbd "<left>")))
    (should (equal "A" (emacsvox-mermaid--view-current view)))))

(ert-deftest emacsvox-mermaid-summary-limit-is-per-direction ()
  (emacsvox-mermaid-test--with-view
      "flowchart TD\nA[Here] -->|Yes| B[One]\nA --> C[Two]\nA --> D[Three]\nA --> E[Four]\nX[Before] --> A"
    (let ((emacsvox-mermaid-connection-speech-limit 3))
      (emacsvox-mermaid-current)
      (should (equal "Here. square. 4 outgoing. Incoming: Before."
                     (caar emacsvox-mermaid-test--speech)))
      (emacsvox-mermaid-outgoing)
      (should (equal "4 outgoing."
                     (caar emacsvox-mermaid-test--speech)))
      (should (equal "A" (emacsvox-mermaid--view-current view))))
    (let ((emacsvox-mermaid-connection-speech-limit 4))
      (emacsvox-mermaid-current)
      (should (equal "Here. square. Outgoing: Yes: One; Two; Three; Four. Incoming: Before."
                     (caar emacsvox-mermaid-test--speech))))
    (let ((emacsvox-mermaid-connection-speech-limit 0))
      (emacsvox-mermaid-current)
      (should (equal "Here. square. 4 outgoing. 1 incoming."
                     (caar emacsvox-mermaid-test--speech))))
    ;; Summarizing prepares the direction; the next arrow follows its selection.
    (emacsvox-mermaid-incoming)
    (should (equal "A" (emacsvox-mermaid--view-current view)))
    (call-interactively (key-binding (kbd "<left>")))
    (should (equal "X" (emacsvox-mermaid--view-current view)))))

(ert-deftest emacsvox-mermaid-quit-announces-the-destination-once ()
  ;; Exercise the real quit advice, including another integration's advice.
  (require 'emacsvox-advice)
  (require 'ibuffer)
  (require 'emacsvox-ibuffer)
  (dolist (display '(display-buffer-same-window display-buffer-pop-up-window))
    (emacsvox-mermaid-test--with-view "flowchart TD\nA --> B"
      (let (events)
        (cl-letf (((symbol-function 'emacsvox-icon)
                   (lambda (icon) (push (list 'icon icon) events)))
                  ((symbol-function 'tts-stop) (lambda (&rest _) (push 'stop events)))
                  ((symbol-function 'emacsvox-speak-mode-line)
                   (lambda () (push (list 'buffer (current-buffer)) events))))
          (switch-to-buffer source)
          (pop-to-buffer explorer (list display))
          (setq events nil)
          (call-interactively (key-binding "q"))
          (should (eq source (window-buffer (selected-window))))
          (should (equal (nreverse events) (list 'stop '(icon close-object) (list 'buffer source)))))))))

(ert-deftest emacsvox-mermaid-explanation-describes-support-ticket-without-moving ()
  (emacsvox-mermaid-test--with-view
      (emacsvox-mermaid-test--fixture "support-ticket")
    (emacsvox-mermaid-right)
    (emacsvox-mermaid-next)
    (let ((location (emacsvox-mermaid--location))
          (history (copy-tree (emacsvox-mermaid--view-history view)))
          (contents (buffer-string))
          (position (point))
          (requests emacsvox-mermaid--sequence))
      (call-interactively (key-binding "e"))
      (should (equal
               "Known solution? Incoming path: Receive ticket. yes leads to Follow support guide. no leads to Investigate the problem. Following arrows, both branches rejoin at Resolve the ticket."
               (caar emacsvox-mermaid-test--speech)))
      (should (equal location (emacsvox-mermaid--location)))
      (should (equal history (emacsvox-mermaid--view-history view)))
      (should (equal contents (buffer-string)))
      (should (= position (point)))
      (should (= requests emacsvox-mermaid--sequence)))
    (emacsvox-mermaid--visit "Resolve")
    (emacsvox-mermaid-explain)
    (should (equal
             "Resolve the ticket. Two paths from Known solution? meet here. The yes path: Follow support guide. The no path: Investigate the problem. The outgoing connection leads to Close ticket."
             (caar emacsvox-mermaid-test--speech)))
    (with-temp-buffer (should (eq (key-binding "e") 'self-insert-command)))))

(ert-deftest emacsvox-mermaid-explanation-distinguishes-guaranteed-and-possible-joins ()
  (dolist (extra '("" "\nB --> End[Other end]" "\nB --> B"))
    (emacsvox-mermaid-test--with-view
        (concat "flowchart TD\nA --> B\nA --> C\nB --> Join[Common step]\nC --> Join" extra)
      (emacsvox-mermaid-explain)
      (if (string-empty-p extra)
          (should (string-match-p "both branches rejoin at Common step" (caar emacsvox-mermaid-test--speech)))
        (should (string-match-p "both branches can reach Common step. Other paths can avoid it" (caar emacsvox-mermaid-test--speech)))
        (should-not (string-match-p "rejoin at" (caar emacsvox-mermaid-test--speech)))))))

(ert-deftest emacsvox-mermaid-explanation-traces-the-two-reviews-without-moving ()
  (emacsvox-mermaid-test--with-view
      (emacsvox-mermaid-test--fixture "duplicate-labels")
    (emacsvox-mermaid--visit "Schedule")
    (emacsvox-mermaid-next)
    (let ((location (emacsvox-mermaid--location))
          (history (copy-tree (emacsvox-mermaid--view-history view)))
          (contents (buffer-string)) (position (point)))
      (emacsvox-mermaid-explain)
      (should (equal
               "Schedule work. Two paths from Receive change request meet here. The manager path: Review, then Approved. The security path: Review, then Approved. No outgoing arrows."
               (caar emacsvox-mermaid-test--speech)))
      (should (equal location (emacsvox-mermaid--location)))
      (should (equal history (emacsvox-mermaid--view-history view)))
      (should (equal contents (buffer-string)))
      (should (= position (point))))
    ;; Context replaces IDs only in the explanation, not in navigation.
    (emacsvox-mermaid-current)
    (should (string-match-p "Approved, node A1; Approved, node A2" (caar emacsvox-mermaid-test--speech)))))

(ert-deftest emacsvox-mermaid-explanation-bounds-incoming-paths-separately-from-counts ()
  (emacsvox-mermaid-test--with-view
      "flowchart TD\nS[Start] -->|manager| R1[Review]\nS -->|security| R2[Review]\nR1 --> A1[Approved]\nR2 --> A2[Approved]\nA1 --> End\nA2 --> End"
    (emacsvox-mermaid--visit "End")
    (let ((emacsvox-mermaid-explanation-path-limit 2))
      (emacsvox-mermaid-explain)
      (should (string-match-p "Review, node R1, then Approved, node A1. Earlier steps omitted" (caar emacsvox-mermaid-test--speech)))
      (should-not (string-match-p "Start\\|manager\\|security" (caar emacsvox-mermaid-test--speech))))
    (let ((emacsvox-mermaid-explanation-path-limit 3))
      (emacsvox-mermaid-explain)
      (should (string-match-p "Two paths from Start meet here" (caar emacsvox-mermaid-test--speech)))
      (should-not (string-match-p "omitted\\|node R1\\|node A1" (caar emacsvox-mermaid-test--speech))))
    (let ((emacsvox-mermaid-explanation-path-limit 0))
      (emacsvox-mermaid-explain)
      (should (equal "End. Arrows from Approved, node A1 and Approved, node A2 meet here. No outgoing arrows."
                     (caar emacsvox-mermaid-test--speech))))
    (let ((emacsvox-mermaid-connection-speech-limit 1))
      (emacsvox-mermaid-explain)
      (should (equal "End. 2 incoming connections meet here. No outgoing arrows."
                     (caar emacsvox-mermaid-test--speech))))))

(ert-deftest emacsvox-mermaid-explanation-stops-incoming-paths-at-structural-boundaries ()
  (dolist (diagram '("flowchart TD\nEarlier --> Fork\nFork --> Step\nFork --> Other\nStep --> End"
                     "flowchart TD\nEarlier --> Join\nOther --> Join\nJoin --> Step\nStep --> End"))
    (emacsvox-mermaid-test--with-view diagram
      (emacsvox-mermaid--visit "End")
      (emacsvox-mermaid-explain)
      (should (string-match-p "Incoming path: \\(Fork\\|Join\\), then Step" (caar emacsvox-mermaid-test--speech)))
      (should-not (string-match-p "Earlier\\|Other" (caar emacsvox-mermaid-test--speech)))))
  ;; Shape alone does not interrupt an unbranched sequence.
  (emacsvox-mermaid-test--with-view "flowchart TD\nStart --> D{Check}\nD --> End"
    (emacsvox-mermaid--visit "End")
    (emacsvox-mermaid-explain)
    (should (equal "End. Incoming path: Start, then Check. No outgoing arrows."
                   (caar emacsvox-mermaid-test--speech)))))

(ert-deftest emacsvox-mermaid-explanation-bounds-incoming-loops-and-two-way-connections ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA --> B\nB --> C\nC --> A"
    (emacsvox-mermaid-explain)
    (should (string-match-p "Incoming path: B, then C. Backward trace stopped at a loop" (caar emacsvox-mermaid-test--speech))))
  (emacsvox-mermaid-test--with-view "flowchart TD\nEarlier <--> Boundary\nBoundary --> End"
    (emacsvox-mermaid--visit "End")
    (emacsvox-mermaid-explain)
    (should (string-match-p "Incoming path: Boundary. Backward trace stopped at a two-way connection" (caar emacsvox-mermaid-test--speech)))
    (should-not (string-match-p "Earlier" (caar emacsvox-mermaid-test--speech))))
  (emacsvox-mermaid-test--with-view "flowchart TD\nEarlier --- Boundary\nBoundary --> End"
    (emacsvox-mermaid--visit "End")
    (emacsvox-mermaid-explain)
    (should (equal "End. Incoming path: Boundary. No outgoing arrows."
                   (caar emacsvox-mermaid-test--speech)))))

(ert-deftest emacsvox-mermaid-explanation-preserves-labels-through-incoming-paths ()
  (emacsvox-mermaid-test--with-view
      "flowchart TD\nStart -->|open| Check\nCheck -->|approved| Ready\nReady -->|done| End"
    (emacsvox-mermaid--visit "End")
    (emacsvox-mermaid-explain)
    (should (equal "End. Incoming path: Start, then open: Check, then approved: Ready, then done: here. No outgoing arrows."
                   (caar emacsvox-mermaid-test--speech)))))

(ert-deftest emacsvox-mermaid-explanation-describes-direct-and-separate-incoming-paths ()
  (emacsvox-mermaid-test--with-view
      "flowchart TD\nStart -->|direct| End\nStart -->|review| Check\nCheck -->|approved| Ready\nReady -->|done| End"
    (emacsvox-mermaid--visit "End")
    (emacsvox-mermaid-explain)
    (should (equal
             "End. Two paths from Start meet here. The direct path leads directly here. The review path: Check, then approved: Ready, then done: here. No outgoing arrows."
             (caar emacsvox-mermaid-test--speech))))
  (emacsvox-mermaid-test--with-view "flowchart TD\nFirst --> A --> End\nSecond --> B --> End"
    (emacsvox-mermaid--visit "End")
    (emacsvox-mermaid-explain)
    (should (equal "End. Two incoming paths meet here. Path 1: First, then A. Path 2: Second, then B. No outgoing arrows."
                   (caar emacsvox-mermaid-test--speech))))
  (emacsvox-mermaid-test--with-view "flowchart TD\nsubgraph Group\nUnconnected\nend\nGroup --> End"
    (emacsvox-mermaid--visit "End")
    (emacsvox-mermaid-explain)
    (should (equal "End. Incoming path: Group. No outgoing arrows."
                   (caar emacsvox-mermaid-test--speech)))))

(ert-deftest emacsvox-mermaid-explanation-keeps-ids-when-path-labels-are-ambiguous ()
  ;; Capitalization alone does not distinguish spoken path names.
  (dolist (label '("review" "Review"))
    (emacsvox-mermaid-test--with-view
        (format "flowchart TD\nStart -->|review| R1[Review]\nStart -->|%s| R2[Review]\nR1 --> End\nR2 --> End" label)
      (emacsvox-mermaid--visit "End")
      (emacsvox-mermaid-explain)
      (should (string-match-p "Path 1: review: Review, node R1" (caar emacsvox-mermaid-test--speech)))
      (should (string-match-p (regexp-quote (format "Path 2: %s: Review, node R2" label))
                              (caar emacsvox-mermaid-test--speech)))))
  (emacsvox-mermaid-test--with-view
      "flowchart TD\nStart -->|manager| R1[Review]\nStart -->|manager| Elsewhere\nStart -->|security| R2[Review]\nR1 --> End\nR2 --> End"
    (emacsvox-mermaid--visit "End")
    (emacsvox-mermaid-explain)
    (should (string-match-p "Path 1: manager: Review, node R1" (caar emacsvox-mermaid-test--speech)))
    (should (string-match-p "The security path: Review" (caar emacsvox-mermaid-test--speech))))
  (emacsvox-mermaid-test--with-view
      "flowchart TD\nStart -->|manager| R1[Step]\nR1 --> R2[Step]\nR2 --> End\nStart -->|security| Other\nOther --> End"
    (emacsvox-mermaid--visit "End")
    (emacsvox-mermaid-explain)
    (should (string-match-p "The manager path: Step, node R1, then Step, node R2" (caar emacsvox-mermaid-test--speech)))))

(ert-deftest emacsvox-mermaid-explanation-does-not-join-through-the-original-fork ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA[Fork] -->|retry| B[Retry]\nA -->|finish| C[Done]\nB --> A"
    (emacsvox-mermaid-explain)
    (should (string-match-p "retry leads to Retry. That branch can loop back here" (caar emacsvox-mermaid-test--speech)))
    (should (string-match-p "No shared destination is reachable along arrows without returning here" (caar emacsvox-mermaid-test--speech)))
    (should-not (string-match-p "rejoin at\\|both branches can reach" (caar emacsvox-mermaid-test--speech)))))

(ert-deftest emacsvox-mermaid-explanation-ignores-containment-and-undirected-paths ()
  (emacsvox-mermaid-test--with-view
      "flowchart TD\nA --> B\nA --> C\nsubgraph G[Container]\nB\nC\nend\nB --- C\nZ --> Z"
    (emacsvox-mermaid-explain)
    (should (string-match-p "No shared destination" (caar emacsvox-mermaid-test--speech)))
    (should-not (string-match-p "rejoin\\|can reach\\|cycle\\|loop" (caar emacsvox-mermaid-test--speech)))))

(ert-deftest emacsvox-mermaid-explanation-handles-nested-branches-and-cycles-after-a-join ()
  (emacsvox-mermaid-test--with-view
      "flowchart TD\nA --> B\nA --> C\nB --> D\nB --> E\nD --> J[Check?]\nE --> J\nC --> J\nJ --> Later\nLater --> Later"
    (emacsvox-mermaid-explain)
    (should (string-match-p (regexp-quote "Following arrows, both branches rejoin at Check? A directed cycle is reachable from here.")
                            (caar emacsvox-mermaid-test--speech)))
    (should-not (string-match-p "Other paths can avoid" (caar emacsvox-mermaid-test--speech)))))

(ert-deftest emacsvox-mermaid-explanation-distinguishes-loop-kinds ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA -->|wait| A"
    (emacsvox-mermaid-explain)
    (should (equal "A. wait is a self loop." (caar emacsvox-mermaid-test--speech))))
  (emacsvox-mermaid-test--with-view "flowchart TD\nA <--> B"
    (emacsvox-mermaid-explain)
    (should (equal "A. The outgoing connection is a two-way connection to B." (caar emacsvox-mermaid-test--speech))))
  (emacsvox-mermaid-test--with-view "flowchart TD\nA <--> B\nB --> C\nC --> A"
    (emacsvox-mermaid-explain)
    (should (string-match-p "That branch can loop back here" (caar emacsvox-mermaid-test--speech))))
  (emacsvox-mermaid-test--with-view "flowchart TD\nA --> B\nB --> C\nC --> B"
    (emacsvox-mermaid-explain)
    (should (string-match-p "A directed cycle is reachable from here" (caar emacsvox-mermaid-test--speech))))
  (emacsvox-mermaid-test--with-view "flowchart TD\nA --- B"
    (emacsvox-mermaid-explain)
    (should (equal "A. No outgoing arrows. Undirected: B." (caar emacsvox-mermaid-test--speech)))))

(ert-deftest emacsvox-mermaid-explanation-respects-limits-and-distinguishes-parallel-connections ()
  (emacsvox-mermaid-test--with-view
      "flowchart TD\nA --> B[Same]\nA --> C[Same]\nA --> D\nA --> E\nB --> J[Join]\nC --> J\nD --> J\nE --> J"
    (let ((emacsvox-mermaid-connection-speech-limit 3))
      (emacsvox-mermaid-explain)
      (should (equal "A. 4 outgoing connections. Following arrows, all 4 branches rejoin at Join."
                     (caar emacsvox-mermaid-test--speech))))
    (let ((emacsvox-mermaid-connection-speech-limit 4))
      (emacsvox-mermaid-explain)
      (should (string-match-p "Connection 1 leads to Same, node B. Connection 2 leads to Same, node C."
                              (caar emacsvox-mermaid-test--speech)))))
  (emacsvox-mermaid-test--with-view "flowchart TD\nA -->|one| B\nA -->|two| B"
    (emacsvox-mermaid-explain)
    (should (equal "A. one leads to B. two leads to B. Both connections lead to B."
                   (caar emacsvox-mermaid-test--speech)))
    (should-not (string-match-p "rejoin" (caar emacsvox-mermaid-test--speech)))
    (let ((emacsvox-mermaid-connection-speech-limit 0))
      (emacsvox-mermaid-explain)
      (should (equal "A. 2 outgoing connections. Both connections lead to B."
                     (caar emacsvox-mermaid-test--speech))))))

(ert-deftest emacsvox-mermaid-forward-explanation-describes-both-review-paths ()
  (emacsvox-mermaid-test--with-view
      (emacsvox-mermaid-test--fixture "duplicate-labels")
    (emacsvox-mermaid-explain)
    (should (equal
             "Receive change request. The manager path: Review, then Approved. The security path: Review, then Approved. Following arrows, both branches rejoin at Schedule work."
             (caar emacsvox-mermaid-test--speech)))
    (let ((emacsvox-mermaid-explanation-path-limit 1))
      (emacsvox-mermaid-explain)
      (should (string-match-p "manager leads to Review, node R1. Later steps omitted" (caar emacsvox-mermaid-test--speech))))
    (let ((emacsvox-mermaid-explanation-path-limit 0))
      (emacsvox-mermaid-explain)
      (should-not (string-match-p "Approved\\|omitted" (caar emacsvox-mermaid-test--speech))))))

(ert-deftest emacsvox-mermaid-forward-explanation-stops-at-boundaries-and-keeps-labels ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA --> B -->|next| C --> Fork\nFork --> D\nFork --> E"
    (emacsvox-mermaid-explain)
    (should (string-match-p "The outgoing connection: B, then next: C, then Fork" (caar emacsvox-mermaid-test--speech)))
    (should-not (string-match-p "then D\\|then E" (caar emacsvox-mermaid-test--speech))))
  (emacsvox-mermaid-test--with-view "flowchart TD\nA --> B --> C\nC <--> D"
    (emacsvox-mermaid-explain)
    (should (string-match-p "B, then C" (caar emacsvox-mermaid-test--speech)))
    (should-not (string-match-p "then D" (caar emacsvox-mermaid-test--speech))))
  (emacsvox-mermaid-test--with-view "flowchart TD\nA --> B --> C --> A"
    (emacsvox-mermaid-explain)
    (should (string-match-p "B, then C. That branch can loop back here" (caar emacsvox-mermaid-test--speech)))))

(ert-deftest emacsvox-mermaid-explanation-panel-expands-one-path-without-moving ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA -->|first| B --> C --> D\nA -->|second| X --> Y"
    (let* ((emacsvox-mermaid-explanation-path-limit 1)
           (before (emacsvox-mermaid--location)) (position (point)) (contents (buffer-string))
           (panel (emacsvox-mermaid-browse-explanation)))
      (with-current-buffer panel
        (should (eq (key-binding "+") 'emacsvox-mermaid-panel-expand))
        (emacsvox-mermaid-panel-next)
        (emacsvox-mermaid-panel-expand)
        (should (string-match-p "B, then C. Later steps omitted" (caar emacsvox-mermaid-test--speech)))
        (let ((rows (plist-get emacsvox-mermaid--panel :items)))
          (should (= 2 (plist-get (nth 1 rows) :limit)))
          (should (= 1 (plist-get (nth 2 rows) :limit))))
        (emacsvox-mermaid-panel-expand)
        (should (string-match-p "B, then C, then D" (caar emacsvox-mermaid-test--speech)))
        (should-error (emacsvox-mermaid-panel-expand) :type 'user-error)
        (should (= 1 emacsvox-mermaid-explanation-path-limit)))
      (with-current-buffer explorer
        (should (equal before (emacsvox-mermaid--location)))
        (should (= position (point))) (should (equal contents (buffer-string)))
        (should-not (emacsvox-mermaid--view-history view))))))

(ert-deftest emacsvox-mermaid-explanation-panel-expands-incoming-path-and-preserves-context ()
  (emacsvox-mermaid-test--with-view
      (emacsvox-mermaid-test--fixture "duplicate-labels")
    (emacsvox-mermaid--visit "Schedule")
    (let* ((emacsvox-mermaid-explanation-path-limit 1)
           (panel (emacsvox-mermaid-browse-explanation)))
      (with-current-buffer panel
        (emacsvox-mermaid-panel-next)
        (emacsvox-mermaid-panel-expand)
        (should (string-match-p "Earlier steps omitted" (caar emacsvox-mermaid-test--speech)))
        (emacsvox-mermaid-panel-expand)
        (should (string-match-p "Incoming manager path from Receive change request: Review, then Approved" (caar emacsvox-mermaid-test--speech)))
        (should-not (string-match-p "node R1\\|node A1" (caar emacsvox-mermaid-test--speech))))
      (with-current-buffer explorer (emacsvox-mermaid--visit "Request"))
      (with-current-buffer panel
        (emacsvox-mermaid-panel-current)
        (should (string-match-p "Incoming manager path" (caar emacsvox-mermaid-test--speech)))))))

(ert-deftest emacsvox-mermaid-explanation-panel-browses-counted-paths-and-honours-point ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA --> B --> C\nA --> X --> Y"
    (let* ((emacsvox-mermaid-connection-speech-limit 0)
           (emacsvox-mermaid-explanation-path-limit 1)
           (panel (emacsvox-mermaid-browse-explanation)))
      (with-current-buffer panel
        (should (string-match-p "Summary. 2 paths available" (caar emacsvox-mermaid-test--speech)))
        (should-not (string-match-p "leads to\\|omitted" (caar emacsvox-mermaid-test--speech)))
        ;; Ordinary point movement selects a row independently of the saved index.
        (goto-char (text-property-any (point-min) (point-max) 'emacsvox-mermaid-panel-item 2))
        (emacsvox-mermaid-panel-expand)
        (should (string-match-p "X, then Y" (caar emacsvox-mermaid-test--speech)))
        (should (= 2 (get-text-property (point) 'emacsvox-mermaid-panel-item)))
        (should (= 1 (plist-get (nth 1 (plist-get emacsvox-mermaid--panel :items)) :limit)))))))

(ert-deftest emacsvox-mermaid-panels-reject-replaced-snapshots-and-close-with-explorer ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA --> B --> C"
    (let ((explanation (emacsvox-mermaid-browse-explanation)) route)
      (with-current-buffer explorer (setq route (emacsvox-mermaid-route "C")))
      ;; Source edits retain the snapshot until an explicit refresh.
      (with-current-buffer source (goto-char (point-max)) (insert "\nC --> D"))
      (with-current-buffer explanation (emacsvox-mermaid-panel-next))
      (with-current-buffer explorer (emacsvox-mermaid-refresh))
      (with-current-buffer explanation (should-error (emacsvox-mermaid-panel-current) :type 'user-error))
      (with-current-buffer route (should-error (emacsvox-mermaid-panel-step) :type 'user-error))
      (kill-buffer explorer)
      (should-not (buffer-live-p explanation)) (should-not (buffer-live-p route)))))

(ert-deftest emacsvox-mermaid-route-preview-follow-and-back-preserve-navigation ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA -->|go| B --> C --> D\nA --> X"
    (emacsvox-mermaid-next)
    (let* ((before (emacsvox-mermaid--location)) (position (point))
           (panel (emacsvox-mermaid-route "D")))
      (with-current-buffer panel
        (emacsvox-mermaid-panel-next)
        (emacsvox-mermaid-panel-next)
        (should (equal "A" (emacsvox-mermaid--view-current view)))
        ;; Previewing a later step cannot skip intervening route connections.
        (call-interactively (key-binding (kbd "RET")))
        (should (equal "B" (emacsvox-mermaid--view-current view)))
        (should (= 1 (plist-get emacsvox-mermaid--panel :progress)))
        (emacsvox-mermaid-panel-step)
        (emacsvox-mermaid-panel-step)
        (should (equal "D" (emacsvox-mermaid--view-current view)))
        (should (string-match-p "Route complete" (caar emacsvox-mermaid-test--speech)))
        (should-error (emacsvox-mermaid-panel-step) :type 'user-error)
        (dotimes (_ 3) (emacsvox-mermaid-panel-back))
        (should-error (emacsvox-mermaid-panel-back) :type 'user-error))
      (with-current-buffer explorer
        (should (equal before (emacsvox-mermaid--location))) (should (= position (point)))
        (should-not (emacsvox-mermaid--view-history view))))))

(ert-deftest emacsvox-mermaid-route-follows-arrows-and-preserves-physical-edge-choices ()
  (emacsvox-mermaid-test--with-view
      "flowchart TD\nA -->|first| B\nA -->|second| B\nB --> A\nB --> D\nD --- Isolated\nA ~~~ Hidden\nsubgraph Group\nD\nend"
    (let* ((steps (emacsvox-mermaid--route-steps "A" "D")))
      (should (equal '("B" "D") (mapcar (lambda (row) (cdr (plist-get row :item))) steps)))
      (should (equal "first" (alist-get 'label (car (plist-get (car steps) :item))))))
    (dolist (target '("Isolated" "Hidden" "Group" "A"))
      (should-error (emacsvox-mermaid-route target) :type 'user-error))
    (should (equal "A" (emacsvox-mermaid--view-current view)))
    (should-not emacsvox-mermaid--panels))
  (emacsvox-mermaid-test--with-view "flowchart TD\nA --> B --> C --> D\nA -->|short| D"
    (let ((steps (emacsvox-mermaid--route-steps "A" "D")))
      (should (= 1 (length steps)))
      (should (equal "short" (alist-get 'label (car (plist-get (car steps) :item)))))))
  (emacsvox-mermaid-test--with-view "flowchart TD\nB <-->|either| A"
    (emacsvox-mermaid--visit "A")
    (let ((panel (emacsvox-mermaid-route "B")))
      (with-current-buffer panel
        (should (string-match-p "either: A to B. Two-way connection" (buffer-string)))
        (emacsvox-mermaid-panel-step)
        (should (equal "B" (emacsvox-mermaid--view-current view)))))))

(ert-deftest emacsvox-mermaid-route-rejects-deviations-and-keeps-cancellation-local ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA --> B --> C\nA --> X"
    (let ((before (emacsvox-mermaid--location)))
      (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) (signal 'quit nil))))
        (should (eq 'cancelled (condition-case nil (emacsvox-mermaid-route) (quit 'cancelled)))))
      (should (equal before (emacsvox-mermaid--location)))
      (should-not emacsvox-mermaid--panels))
    (let ((panel (emacsvox-mermaid-route "C")))
      (with-current-buffer explorer (emacsvox-mermaid--visit "X"))
      (with-current-buffer panel (should-error (emacsvox-mermaid-panel-step) :type 'user-error))
      (should (equal "X" (emacsvox-mermaid--view-current view)))
      (with-current-buffer explorer (emacsvox-mermaid--visit "A"))
      ;; Returning to the same node through different history is still a deviation.
      (with-current-buffer panel (should-error (emacsvox-mermaid-panel-step) :type 'user-error)))))

(ert-deftest emacsvox-mermaid-deployment-tour-explains-validation-waits-and-rollback ()
  (emacsvox-mermaid-test--with-view
      (emacsvox-mermaid-test--fixture "deployment-pipeline")
    (emacsvox-mermaid--visit "Build")
    (emacsvox-mermaid-explain)
    (should (string-match-p "all 3 branches rejoin at All checks passed" (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid--visit "Gate")
    (emacsvox-mermaid-explain)
    (should (string-match-p "The yes path: Package release, then Deploy to staging, then Smoke tests passed" (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid--visit "Approval")
    (emacsvox-mermaid-explain)
    (should (string-match-p "wait leads to Wait for release window. That branch can loop back here" (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid--visit "Monitor")
    (emacsvox-mermaid-explain)
    (should (string-match-p "The no path: Restore previous release, then Correct the change" (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid--visit "Fix")
    (let ((before (emacsvox-mermaid--location)) (panel (emacsvox-mermaid-route "Done")))
      (with-current-buffer panel
        (should (string-match-p "conditions are not evaluated" (buffer-string)))
        (should (equal '("Build" "Unit" "Gate" "Package" "Stage" "Smoke" "Approval" "Production" "Monitor" "Done")
                       (mapcar (lambda (row) (cdr (plist-get row :item))) (plist-get emacsvox-mermaid--panel :items))))
        (dotimes (_ 10) (emacsvox-mermaid-panel-step))
        (should (equal "Done" (emacsvox-mermaid--view-current view)))
        (dotimes (_ 10) (emacsvox-mermaid-panel-back)))
      (with-current-buffer explorer (should (equal before (emacsvox-mermaid--location)))))))

(ert-deftest emacsvox-mermaid-panel-quit-restores-explorer-with-normal-feedback ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA --> B"
    (switch-to-buffer explorer)
    (let ((panel (emacsvox-mermaid-browse-explanation)) events)
      (cl-letf (((symbol-function 'tts-stop) (lambda (&rest _) (push 'stop events)))
                ((symbol-function 'emacsvox-icon) (lambda (icon) (push icon events)))
                ((symbol-function 'emacsvox-speak-mode-line) (lambda () (push (current-buffer) events))))
        (with-current-buffer panel (call-interactively (key-binding "q")))
        (should (eq explorer (window-buffer (selected-window))))
        (should (equal (nreverse events) (list 'stop 'close-object explorer)))))))

(ert-deftest emacsvox-mermaid-new-panel-keys-stay-local ()
  (with-temp-buffer
    (dolist (key '("E" "r" "+")) (should (eq 'self-insert-command (key-binding key)))))
  (emacsvox-mermaid-test--with-view "flowchart TD\nA --> B"
    (should (eq 'emacsvox-mermaid-browse-explanation (key-binding "E")))
    (should (eq 'emacsvox-mermaid-route (key-binding "r")))))

(ert-deftest emacsvox-mermaid-route-quit-keeps-the-updated-explorer-point ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA --> B --> C\nA --> X"
    (switch-to-buffer explorer)
    (emacsvox-mermaid-next)
    (let* ((display-buffer-overriding-action '(display-buffer-same-window))
           (panel (emacsvox-mermaid-route "C")) position)
      (with-current-buffer panel (emacsvox-mermaid-panel-step))
      (with-current-buffer explorer (setq position (point)))
      (cl-letf (((symbol-function 'tts-stop) #'ignore)
                ((symbol-function 'emacsvox-icon) #'ignore)
                ((symbol-function 'emacsvox-speak-mode-line) #'ignore))
        (with-current-buffer panel (emacsvox-mermaid-quit)))
      (should (eq explorer (window-buffer (selected-window))))
      (with-current-buffer explorer
        (should (equal "B" (emacsvox-mermaid--view-current view)))
        (should (= position (point)))
        (should (equal 0 (get-text-property (point) 'emacsvox-mermaid-item)))))))

(ert-deftest emacsvox-mermaid-panels-graphical-focus-wrapping-and-quit ()
  (skip-unless (display-graphic-p))
  (let ((width (frame-width)) (height (frame-height)))
    (unwind-protect
        (progn
          (set-frame-size (selected-frame) 60 32)
          (dolist (display '(display-buffer-same-window display-buffer-pop-up-window))
            (emacsvox-mermaid-test--with-view
                (format "flowchart TD\nA --> B[%s] --> C\nA --> X" (string-join (make-list 16 "Long review label") " "))
              (delete-other-windows)
              (switch-to-buffer explorer)
              (emacsvox-mermaid-next)
              (let* ((display-buffer-overriding-action (list display))
                     (before (emacsvox-mermaid--location))
                     (emacsvox-mermaid-explanation-path-limit 1)
                     (panel (emacsvox-mermaid-browse-explanation)))
                (with-current-buffer panel
                  (call-interactively (key-binding (kbd "<down>")))
                  (redisplay t)
                  (should (eq panel (window-buffer (selected-window))))
                  (should (pos-visible-in-window-p (point)))
                  (should (> (count-screen-lines (point) (line-end-position) nil (selected-window)) 1))
                  (call-interactively (key-binding "+"))
                  (redisplay t)
                  (should (pos-visible-in-window-p (point))))
                (cl-letf (((symbol-function 'tts-stop) #'ignore)
                          ((symbol-function 'emacsvox-icon) #'ignore)
                          ((symbol-function 'emacsvox-speak-mode-line) #'ignore))
                  (with-current-buffer panel (call-interactively (key-binding "q")))
                  (should (eq explorer (window-buffer (selected-window))))
                  (with-current-buffer explorer
                    (should (equal before (emacsvox-mermaid--location)))
                    (setq panel (emacsvox-mermaid-route "C")))
                  (with-current-buffer panel
                    (call-interactively (key-binding (kbd "<right>")))
                    (redisplay t)
                    (should (eq panel (window-buffer (selected-window))))
                    (should (pos-visible-in-window-p (point)))
                    (should (equal "B" (emacsvox-mermaid--view-current view)))
                    (call-interactively (key-binding "q")))
                  (should (eq explorer (window-buffer (selected-window))))
                  (with-current-buffer explorer
                    (should (equal 0 (get-text-property (point) 'emacsvox-mermaid-item)))
                    (emacsvox-mermaid-back)
                    (should (equal before (emacsvox-mermaid--location)))))))))
      (set-frame-size (selected-frame) width height))))

(ert-deftest emacsvox-mermaid-join-guarantee-agrees-with-independent-path-checks ()
  ;; Exhaust every set of arrows from B and C to the fork A, either branch,
  ;; or the proposed join D.  A separate path walk rejects endpoints, returns
  ;; and cycles before D; it does not use the implementation's reverse worklist.
  (dotimes (mask 256)
    (let ((out (make-hash-table :test #'equal))
          (in (make-hash-table :test #'equal))
          (bit 0))
      (dolist (from '("B" "C"))
        (dolist (to '("A" "B" "C" "D"))
          (unless (zerop (logand mask (ash 1 bit)))
            (push to (gethash from out))
            (push from (gethash to in)))
          (cl-incf bit)))
      (let ((certain (emacsvox-mermaid--must-reach "D" "A" (list :out out :in in))))
        (cl-labels ((avoids (id path)
                      (and (not (equal id "D"))
                           (or (equal id "A") (member id path) (null (gethash id out))
                               (cl-some (lambda (next) (avoids next (cons id path)))
                                        (gethash id out))))))
          (dolist (id '("B" "C"))
            (should (eq (gethash id certain) (not (avoids id nil))))))))))

(ert-deftest emacsvox-mermaid-summary-limit-includes-the-boundary ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA[Start] --> B[One]\nA --> C[Two]\nA --> D[Three]"
    (let ((emacsvox-mermaid-connection-speech-limit 3))
      (emacsvox-mermaid-outgoing)
      (should (equal "Outgoing: One; Two; Three." (caar emacsvox-mermaid-test--speech))))
    (let ((emacsvox-mermaid-connection-speech-limit 2))
      (emacsvox-mermaid-outgoing)
      (should (equal "3 outgoing." (caar emacsvox-mermaid-test--speech)))
      (emacsvox-mermaid-next)
      (should (equal "Two. 2 of 3." (caar emacsvox-mermaid-test--speech))))
    (let ((emacsvox-mermaid-connection-speech-limit 0))
      (emacsvox-mermaid--visit "B")
      (emacsvox-mermaid-current)
      (should (equal "One. square. No outgoing. 1 incoming." (caar emacsvox-mermaid-test--speech))))))

(ert-deftest emacsvox-mermaid-combined-list-keeps-distinct-connections ()
  (emacsvox-mermaid-test--with-view
      "flowchart TD\nA -->|first| B\nA -->|second| B\nC --> A\nA <--> D\nA --- E\nA --> A"
    (should (equal '("B" "B" "D" "A" "C" "E") (mapcar #'cdr (emacsvox-mermaid--items))))
    (goto-char (point-min))
    (emacsvox-mermaid-right)
    (should (equal "Outgoing. first: B. 1 of 5." (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid-next)
    (should (equal "second: B. 2 of 5." (caar emacsvox-mermaid-test--speech)))
    ;; Point movement outside the navigation commands must also be respected.
    (goto-char (text-property-any (point-min) (point-max) 'emacsvox-mermaid-item 2))
    (emacsvox-mermaid-right)
    (should (equal "D" (emacsvox-mermaid--view-current view)))
    (emacsvox-mermaid-back)
    (should (= 2 (get-text-property (point) 'emacsvox-mermaid-item)))
    (call-interactively (key-binding (kbd "C-g")))
    (should (equal "A" (emacsvox-mermaid--view-current view)))
    (should (eq 'connections (emacsvox-mermaid--view-section view)))
    (should (equal '("B" "B" "D" "A" "C" "E") (mapcar #'cdr (emacsvox-mermaid--items))))
    ;; A self link occurs once in the combined list and is still traversable.
    (goto-char (text-property-any (point-min) (point-max) 'emacsvox-mermaid-item 3))
    (emacsvox-mermaid-follow)
    (should (equal "A" (emacsvox-mermaid--view-current view)))
    (should (eq 'connections (emacsvox-mermaid--view-section view)))
    (emacsvox-mermaid-back)
    (should (= 3 (get-text-property (point) 'emacsvox-mermaid-item))))
  (emacsvox-mermaid-test--with-view "flowchart TD\nA --- B"
    (emacsvox-mermaid-right)
    (should (equal "B" (emacsvox-mermaid--view-current view)))
    (emacsvox-mermaid-left)
    (should (equal "A" (emacsvox-mermaid--view-current view)))))

(ert-deftest emacsvox-mermaid-example-model-and-navigation ()
  (emacsvox-mermaid-test--with-view
      (emacsvox-mermaid-test--fixture "monitoring")
    (should (string-match-p "13 nodes, 0 groups, 15 connections" (buffer-string)))
    (should (equal "P" (emacsvox-mermaid--view-current view)))
    (let ((sequence emacsvox-mermaid--sequence))
      (emacsvox-mermaid-outgoing)
      (emacsvox-mermaid-follow)
      (should (equal "G" (emacsvox-mermaid--view-current view)))
      (should (equal (mapcar #'cdr (emacsvox-mermaid--items)) '("H" "S" "K" "P")))
      (emacsvox-mermaid-next)
      (should (equal "G" (emacsvox-mermaid--view-current view)))
      (emacsvox-mermaid-follow)
      (should (equal "S" (emacsvox-mermaid--view-current view)))
      (emacsvox-mermaid-incoming)
      (should (equal (mapcar #'cdr (emacsvox-mermaid--items)) '("G" "H")))
      (emacsvox-mermaid-back)
      (should (equal "G" (emacsvox-mermaid--view-current view)))
      (should (= sequence emacsvox-mermaid--sequence)))
    (should buffer-read-only)
    (should (eq 'lane (plist-get (cdar emacsvox-mermaid-test--speech) :interruption-policy)))
    (should (eq 'replaceable (plist-get (cdar emacsvox-mermaid-test--speech) :delivery-policy)))))

(ert-deftest emacsvox-mermaid-cycles-and-self-links-remain-traversable ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA --> B\nB --> A\nA --> A"
    (emacsvox-mermaid-follow)
    (emacsvox-mermaid-follow)
    (should (equal "A" (emacsvox-mermaid--view-current view)))
    (should (string-prefix-p "Revisited." (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid-next)
    (should (string-match-p "self link" (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid-follow)
    (emacsvox-mermaid-back)
    (emacsvox-mermaid-back)
    (should (equal "B" (emacsvox-mermaid--view-current view)))))

(ert-deftest emacsvox-mermaid-undirected-and-two-way-connections ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA --- B\nB <--> C\nC --> D"
    (should (string-match-p "No outgoing. No incoming. Undirected: B" (emacsvox-mermaid--current-text)))
    (emacsvox-mermaid--visit "B")
    (emacsvox-mermaid-incoming)
    (should (equal (mapcar #'cdr (emacsvox-mermaid--items)) '("C" "A")))
    (should (string-match-p "Incoming: Both directions to C. Undirected: A" (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid-next)
    (should (string-match-p "Undirected connection" (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid-previous)
    (should (string-match-p "Both directions" (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid-follow)
    (emacsvox-mermaid-outgoing)
    (should (equal (mapcar #'cdr (emacsvox-mermaid--items)) '("B" "D")))))

(ert-deftest emacsvox-mermaid-duplicate-labels-and-disconnected-groups ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA[Same] --> B[Same]\nsubgraph G[Separate]\nC\nend"
    (emacsvox-mermaid-current)
    (should (string-prefix-p "Same, node A." (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid-outgoing)
    (should (equal "Outgoing: Same, node B." (caar emacsvox-mermaid-test--speech)))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_prompt choices &rest _)
                 (should (assoc "Same, node A" choices))
                 (should (assoc "Same, node B" choices))
                 "Same, node B")))
      (emacsvox-mermaid-find))
    (should (equal "B" (emacsvox-mermaid--view-current view)))
    (emacsvox-mermaid-all)
    (should (member "G" (mapcar #'cdr (emacsvox-mermaid--items))))
    (emacsvox-mermaid--visit "G")
    (emacsvox-mermaid-members)
    (emacsvox-mermaid-follow)
    (should (equal "C" (emacsvox-mermaid--view-current view)))
    (should (string-suffix-p "In Separate." (emacsvox-mermaid--current-text)))))

(ert-deftest emacsvox-mermaid-unique-labels-speak-without-identifiers ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA[Start] --> B[Finish]"
    (emacsvox-mermaid-current)
    (should (equal "Start. square. Outgoing: Finish. No incoming."
                   (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid-outgoing)
    (should (equal "Outgoing: Finish." (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid-follow)
    (should (equal "Finish. No outgoing."
                   (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid-incoming)
    (should (equal "Incoming: Start." (caar emacsvox-mermaid-test--speech)))
    ;; Searching remains an explicit way to inspect and match source IDs.
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_prompt choices &rest _)
                 (should (assoc "Start, node A" choices))
                 (should (assoc "Finish, node B" choices))
                 "Start, node A")))
      (emacsvox-mermaid-find))
    (should (equal "A" (emacsvox-mermaid--view-current view)))
    (should (equal "Revisited. Start. Outgoing: Finish."
                   (caar emacsvox-mermaid-test--speech)))))

(ert-deftest emacsvox-mermaid-shared-node-and-group-labels-remain-distinct ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA[Shared]\nsubgraph G[Shared]\nB\nend"
    (emacsvox-mermaid-current)
    (should (string-prefix-p "Shared, node A." (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid--visit "G")
    (should (string-prefix-p "Entering Shared, group G." (caar emacsvox-mermaid-test--speech)))))

(ert-deftest emacsvox-mermaid-branch-labels-precede-destinations ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA{Known solution?} -->|Yes| B[Follow guide]\nA -->|No| C[Investigate]"
    (should (equal "Known solution? Decision. Outgoing: Yes: Follow guide; No: Investigate." (emacsvox-mermaid--brief-text)))
    (emacsvox-mermaid-outgoing)
    (should (equal "Outgoing: Yes: Follow guide; No: Investigate." (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid-next)
    (should (equal "No: Investigate. 2 of 2." (caar emacsvox-mermaid-test--speech)))
    (should (equal "A" (emacsvox-mermaid--view-current view)))
    (emacsvox-mermaid-follow)
    (should (equal "Investigate. No outgoing." (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid-current)
    (should (equal "Investigate. square. No outgoing. Incoming: No: Known solution?" (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid-incoming)
    (should (equal "Incoming: No: Known solution?" (caar emacsvox-mermaid-test--speech)))))

(ert-deftest emacsvox-mermaid-back-restores-section-and-actual-selection ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA[Alpha] --> B[Beta]\nC[Charlie] --> B\nB --> D[Delta]"
    (emacsvox-mermaid--visit "B")
    (emacsvox-mermaid-incoming)
    ;; Ordinary Emacs search or point movement can select a different row.
    (goto-char (text-property-any (point-min) (point-max) 'emacsvox-mermaid-item 1))
    (emacsvox-mermaid-follow)
    (should (equal "C" (emacsvox-mermaid--view-current view)))
    (emacsvox-mermaid-back)
    (should (equal "B" (emacsvox-mermaid--view-current view)))
    (should (eq 'incoming (emacsvox-mermaid--view-section view)))
    (should (= 1 (get-text-property (point) 'emacsvox-mermaid-item)))
    (should (string-suffix-p "Incoming. From Charlie. 2 of 2." (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid-previous)
    (emacsvox-mermaid-follow)
    (should (equal "A" (emacsvox-mermaid--view-current view)))))

(ert-deftest emacsvox-mermaid-group-boundaries-parent-and-remembered-place ()
  (emacsvox-mermaid-test--with-view
      "flowchart TD\nOutside[Outside]\nsubgraph Site[Warehouse]\nsubgraph Work[Processing]\nA[Queue] --> B[Worker]\nend\nend\nOutside --> A\nB --> Outside"
    (emacsvox-mermaid-follow)
    (should (string-match-p "Entering Warehouse. Entering Processing. Queue" (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid-follow)
    (should-not (string-match-p "Entering\\|Leaving" (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid-where)
    (should (string-match-p "Worker. In Warehouse, Processing. Outgoing. Outside. 1 of 1." (caar emacsvox-mermaid-test--speech)))
    (emacsvox-mermaid-parent)
    (should (equal "Work" (emacsvox-mermaid--view-current view)))
    (should (eq 'members (emacsvox-mermaid--view-section view)))
    (should (equal "B" (cdr (nth (emacsvox-mermaid--view-selection view) (emacsvox-mermaid--items)))))
    (emacsvox-mermaid-follow)
    (emacsvox-mermaid-follow)
    (should (string-match-p "Leaving Processing. Leaving Warehouse." (caar emacsvox-mermaid-test--speech)))
    (should-error (emacsvox-mermaid-parent) :type 'user-error)
    ;; Revisiting a group remembers the member last selected there.
    (emacsvox-mermaid--visit "Work")
    (should (eq 'members (emacsvox-mermaid--view-section view)))
    (emacsvox-mermaid-follow)
    (should (equal "B" (emacsvox-mermaid--view-current view)))
    (emacsvox-mermaid-parent)
    (emacsvox-mermaid-parent)
    (should (equal "Site" (emacsvox-mermaid--view-current view)))
    (should (equal "Work" (cdr (nth (emacsvox-mermaid--view-selection view) (emacsvox-mermaid--items)))))))

(ert-deftest emacsvox-mermaid-filters-follow-arrows-and-distinguish-landmarks ()
  (emacsvox-mermaid-test--with-view
      "flowchart TD\nA --> B\nA --> C\nB --> D\nC --> D\nE\nF --- G\nH <--> I"
    (should (equal '("A") (emacsvox-mermaid--matching-ids 'entries)))
    (should (equal '("D") (emacsvox-mermaid--matching-ids 'exits)))
    (should (equal '("A") (emacsvox-mermaid--matching-ids 'branches)))
    (should (equal '("D") (emacsvox-mermaid--matching-ids 'joins)))
    (should (equal '("E") (emacsvox-mermaid--matching-ids 'disconnected)))
    (should (equal '("B" "C" "D") (emacsvox-mermaid--matching-ids 'downstream)))
    (emacsvox-mermaid--visit "D")
    (should (equal '("A" "B" "C") (emacsvox-mermaid--matching-ids 'upstream)))
    (should-not (member "A" (emacsvox-mermaid--matching-ids 'unvisited)))
    (should-not (member "D" (emacsvox-mermaid--matching-ids 'unvisited)))
    (emacsvox-mermaid--visit "F")
    (should-not (emacsvox-mermaid--matching-ids 'downstream))
    (emacsvox-mermaid--visit "H")
    (should (equal '("I") (emacsvox-mermaid--matching-ids 'upstream)))
    (should (equal '("I") (emacsvox-mermaid--matching-ids 'downstream)))))

(ert-deftest emacsvox-mermaid-filtered-find-does-not-move-until-a-match-is-chosen ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA[Start] --> B[Finish]\nC[Alone]"
    (cl-letf (((symbol-function 'completing-read)
               (lambda (prompt choices &rest _)
                 (should (equal "A" (emacsvox-mermaid--view-current view)))
                 (if (equal prompt "Find filter: ") "Disconnected nodes"
                   (should (equal '(("Alone, node C" . "C")) choices))
                   "Alone, node C"))))
      (emacsvox-mermaid-find-filtered))
    (should (equal "C" (emacsvox-mermaid--view-current view)))
    (let ((history (copy-tree (emacsvox-mermaid--view-history view))))
      (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "")))
        (emacsvox-mermaid-find-filtered)
        (emacsvox-mermaid--find 'all))
      (should-error (emacsvox-mermaid--find 'branches) :type 'user-error)
      (should (equal history (emacsvox-mermaid--view-history view)))
      (should (equal "C" (emacsvox-mermaid--view-current view))))))

(ert-deftest emacsvox-mermaid-overview-separates-containment-and-arrows ()
  (emacsvox-mermaid-test--with-view
      "flowchart TD\naccDescr: Author explanation.\nsubgraph G[Group]\nA --> B\nC\nend\nD --> E\nF"
    (emacsvox-mermaid-overview)
    (should (string-match-p "3 separate parts. 1 isolated node." (caar emacsvox-mermaid-test--speech)))
    (should (string-match-p "Author explanation" (caar emacsvox-mermaid-test--speech)))
    (should-not (string-match-p "cycle" (caar emacsvox-mermaid-test--speech)))
    (should (equal '("B") (emacsvox-mermaid--matching-ids 'downstream)))
    (should (equal '("F") (emacsvox-mermaid--matching-ids 'disconnected)))
    (should (equal '("G") (emacsvox-mermaid--matching-ids 'groups)))))

(ert-deftest emacsvox-mermaid-cycle-summary-distinguishes-return-links ()
  (dolist (case '(("A --> B\nB --> C" . nil)
                  ("A --> B\nA --> B" . nil)
                  ("A <--> B" . nil)
                  ("A <--> B\nB <--> C" . nil)
                  ("A --- B\nB --- C\nC --- A" . nil)
                  ("A --> A" . t)
                  ("A --> B\nB --> A" . t)
                  ("A --> B\nB --> C\nC --> A" . t)
                  ("A <--> B\nB --> C\nC --> A" . t)
                  ("A <--> B\nB <--> C\nC <--> A" . t)))
    (emacsvox-mermaid-test--with-view (concat "flowchart TD\n" (car case))
      (should (eq (cdr case) (plist-get (emacsvox-mermaid--view-analysis view) :cycle)))
      (when (cdr case) (should (string-match-p "Contains a directed cycle" (emacsvox-mermaid--overview-text)))))))

(ert-deftest emacsvox-mermaid-new-navigation-keys-stay-in-explorer ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA --> B"
    (should (eq (key-binding "u") 'emacsvox-mermaid-parent))
    (should (eq (key-binding "w") 'emacsvox-mermaid-where))
    (should (eq (key-binding "F") 'emacsvox-mermaid-find-filtered))
    (should (eq (key-binding "f") 'emacsvox-mermaid-find))
    (with-temp-buffer
      (should (eq (key-binding "u") 'self-insert-command))
      (should (eq (key-binding "w") 'self-insert-command))
      (should (eq (key-binding "F") 'self-insert-command)))))

(ert-deftest emacsvox-mermaid-source-jump-unicode-and-stale-protection ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA[\"😀\"] --> B[End]"
    (emacsvox-mermaid--visit "B")
    (emacsvox-mermaid-source)
    (should (eq source (current-buffer)))
    (should (looking-at-p "B\\[End\\]"))
    (goto-char (point-min)) (insert "%% changed\n")
    (with-current-buffer explorer
      (should-error (emacsvox-mermaid-source) :type 'user-error))))

(ert-deftest emacsvox-mermaid-empty-find-keeps-current-node-and-history ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA --> B"
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "")))
      (emacsvox-mermaid-find))
    (should (equal "A" (emacsvox-mermaid--view-current view)))
    (should-not (emacsvox-mermaid--view-history view))
    (emacsvox-mermaid-follow)
    (should (equal "B" (emacsvox-mermaid--view-current view)))))

(ert-deftest emacsvox-mermaid-native-submission-preserves-content-and-context ()
  (let (spoken)
    (cl-letf (((symbol-function 'tts-speak) (lambda (text) (setq spoken text))))
      (let ((submission (emacsvox-mermaid--say "Two connections.")))
        (should (equal (substring-no-properties spoken) "Two connections."))
        (should (eq 'mermaid (plist-get (emacsvox-aural-submission-context submission) :module)))
        (should (eq 'main (emacsvox-aural-submission-lane submission)))
        (should (eq 'replaceable (emacsvox-aural-submission-delivery-policy submission)))
        (should (eq 'lane (emacsvox-aural-submission-interruption-policy submission)))))))

(ert-deftest emacsvox-mermaid-block-extraction-and-region ()
  (with-temp-buffer
    (insert "Text\n```text\n```mermaid\nnot a diagram\n```\n\n~~~mermaid\nflowchart TD\nA-->B\n~~~~\nAfter\n")
    (goto-char (point-min)) (search-forward "A-->")
    (let ((bounds (emacsvox-mermaid--bounds)))
      (should (equal (buffer-substring-no-properties (car bounds) (cdr bounds)) "flowchart TD\nA-->B\n")))
    (erase-buffer) (insert "Before\n#+begin_src mermaid\nflowchart LR\nX-->Y\n#+end_src\n")
    (goto-char (point-min)) (search-forward "X-->")
    (let ((bounds (emacsvox-mermaid--bounds)))
      (should (equal (buffer-substring-no-properties (car bounds) (cdr bounds)) "flowchart LR\nX-->Y\n")))
    (let ((transient-mark-mode t))
      (set-mark (point-min)) (setq mark-active t)
      (should (equal (emacsvox-mermaid--bounds) (cons (point-min) (point)))))
    (erase-buffer) (insert "```mermaid\nflowchart TD\nA-->B")
    (should-error (emacsvox-mermaid--bounds) :type 'user-error)))

(ert-deftest emacsvox-mermaid-explicit-command-opens-and-parses-block ()
  (let ((source (generate-new-buffer " *mermaid-command-test*")) explorer)
    (unwind-protect
        (save-window-excursion
          (cl-letf (((symbol-function 'emacsvox-aural-submit) #'ignore))
            (switch-to-buffer source)
            (insert "Prose\n```mermaid\nflowchart TD\nA --> B\n```\nMore prose")
            (goto-char (point-min)) (search-forward "A -->")
            (emacsvox-mermaid-explore)
            (setq explorer (current-buffer))
            (should (derived-mode-p 'emacsvox-mermaid-mode))
            (emacsvox-mermaid-test--wait
             (lambda () (not (emacsvox-mermaid--view-request emacsvox-mermaid--view))))
            (should (equal "A" (emacsvox-mermaid--view-current emacsvox-mermaid--view)))
            (should (eq (key-binding (kbd "RET")) 'emacsvox-mermaid-follow))
            (emacsvox-mermaid-follow)
            (emacsvox-mermaid-source)
            (should (eq (current-buffer) source))
            (should (looking-at-p "B"))))
      (when (buffer-live-p explorer) (kill-buffer explorer))
      (kill-buffer source))))

(ert-deftest emacsvox-mermaid-errors-do-not-leave-a-navigable-partial-graph ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA --> B\nC[unfinished"
    (should-not (emacsvox-mermaid--view-current view))
    (should (string-match-p "Diagram line 3" (buffer-string)))
    (should-error (emacsvox-mermaid-outgoing) :type 'user-error)
    (should-error (emacsvox-mermaid-explain) :type 'user-error)))

(ert-deftest emacsvox-mermaid-stale-replies-and-closed-sources ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA --> B"
    (let ((reply (emacsvox-mermaid-test--parse text)))
      (with-current-buffer source (goto-char (point-max)) (insert "\nC"))
      (emacsvox-mermaid--accept explorer view text reply)
      (should-not (emacsvox-mermaid--view-current view))
      (should (string-match-p "Source changed" (buffer-string)))
      (kill-buffer source)
      (should-error (emacsvox-mermaid-refresh) :type 'user-error))))

(ert-deftest emacsvox-mermaid-newest-refresh-wins-and-keeps-current-node ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA --> B"
    (emacsvox-mermaid--visit "B")
    (emacsvox-mermaid-refresh)
    (should-error (emacsvox-mermaid-next) :type 'user-error)
    (with-current-buffer source (goto-char (point-max)) (insert "\nB --> C\nC --> B\nD"))
    (emacsvox-mermaid-refresh)
    (emacsvox-mermaid-test--wait (lambda () (zerop (hash-table-count emacsvox-mermaid--pending))))
    (should (equal "B" (emacsvox-mermaid--view-current emacsvox-mermaid--view)))
    (should (equal '("C" "A" "C") (mapcar #'cdr (emacsvox-mermaid--items))))
    (should-not (emacsvox-mermaid--view-history emacsvox-mermaid--view))
    (should (zerop (hash-table-count (emacsvox-mermaid--view-places emacsvox-mermaid--view))))
    (should (equal '("B") (emacsvox-mermaid--view-visited emacsvox-mermaid--view)))
    (should (equal '("C") (emacsvox-mermaid--matching-ids 'downstream)))
    (should (equal '("D") (emacsvox-mermaid--matching-ids 'disconnected)))
    (should (string-match-p "2 separate parts. 1 isolated node. Contains a directed cycle."
                            (emacsvox-mermaid--overview-text)))))

(ert-deftest emacsvox-mermaid-killing-explorer-cancels-delivery ()
  (emacsvox-mermaid-test--with-view "flowchart TD\nA --> B"
    (emacsvox-mermaid-refresh)
    (let ((id (emacsvox-mermaid--view-request emacsvox-mermaid--view)))
      (kill-buffer explorer)
      (should-not (gethash id emacsvox-mermaid--pending))
      (should (alist-get 'graph (emacsvox-mermaid-test--parse "flowchart TD\nC --> D"))))))

(ert-deftest emacsvox-mermaid-helper-crash-fails-pending-and-restarts ()
  (let (first second)
    (emacsvox-mermaid--request "flowchart TD\nA --> B" (lambda (r) (setq first r)))
    (emacsvox-mermaid--request "flowchart TD\nC --> D" (lambda (r) (setq second r)))
    (delete-process emacsvox-mermaid--process)
    (emacsvox-mermaid-test--wait (lambda () (and first second)))
    (should (alist-get 'error first))
    (should (alist-get 'error second))
    (should (zerop (hash-table-count emacsvox-mermaid--pending)))
    (should (alist-get 'graph (emacsvox-mermaid-test--parse "flowchart TD\nE --> F")))))

(ert-deftest emacsvox-mermaid-timeout-recovers-without-blocking-emacs ()
  (let ((emacsvox-mermaid-timeout 0.05) response)
    (cl-letf (((symbol-function 'process-send-string) #'ignore))
      (emacsvox-mermaid--request "flowchart TD\nA --> B" (lambda (r) (setq response r)))
      (emacsvox-mermaid-test--wait (lambda () response)))
    (should (string-match-p "timed out" (alist-get 'error response)))
    (should (zerop (hash-table-count emacsvox-mermaid--pending))))
  (should (alist-get 'graph (emacsvox-mermaid-test--parse "flowchart TD\nA --> B"))))

(provide 'emacsvox-mermaid-tests)
;;; emacsvox-mermaid-tests.el ends here
