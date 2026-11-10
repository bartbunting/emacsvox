;;; omnivox-native-guard.el --- Independent native cleanup control -*- lexical-binding: t; -*-

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
;; Experimental, opt-in local control for a native cleanup authority.  Speech
;; remains on the owner's existing pipe.  Retain uncertain authorities and
;; require exact tree AND I/O proof before explicit minimal replacement.

;;; Code:
(require 'cl-lib)
(require 'json)
(require 'subr-x)

(defvar omnivox-native-guard--enabled nil
  "Opt in to experimental guarded owners on a qualified native runtime.")
(defvar omnivox-native-guard--owners nil
  "At most four guarded owners whose cleanup has not been confirmed.")
(declare-function tts--diagnostic-buffer "tts-speak" (name &optional clear))

(defun omnivox-native-guard--capacity ()
  "Bound native authorities retained across failed startup attempts."
  ;; Generic speech teardown may have ended its owner after we last ran.  Ask
  ;; the original surviving guard; owner exit alone never releases this slot.
  (dolist (owner (copy-sequence omnivox-native-guard--owners))
    (when (and (not (process-live-p owner)) (process-get owner 'omnivox-native-guard))
      (condition-case nil
          (let ((reply (omnivox-native-guard--request owner "status")))
            (when (and (eq (plist-get reply :tree_retired) t)
                       (eq (plist-get reply :io_retired) t))
              ;; Retain this exact, monotonic observation for explicit minimal
              ;; recovery even after releasing the already retired control link.
              (process-put owner 'omnivox-native-guard-proof reply)
              (let ((bridge (process-get owner 'omnivox-native-guard)))
                (when (process-live-p bridge) (delete-process bridge)))
              (setq omnivox-native-guard--owners (delq owner omnivox-native-guard--owners))))
        (error nil))))
  (when (>= (length omnivox-native-guard--owners) 4)
    (error "Four native guards remain retained; confirm their cleanup before retrying")))

(defun omnivox-native-guard--filter (bridge text)
  "Accept bounded, exactly correlated cleanup replies from BRIDGE in TEXT."
  (condition-case err
      (let ((pending (concat (or (process-get bridge 'guard-fragment) "") text)))
        (while (string-match "\n" pending)
          (let* ((end (match-end 0))
                 (line (substring pending 0 end))
                 (endpoint (process-get bridge 'guard-endpoint)))
            (when (> (string-bytes line) 8192) (error "Oversized native guard response"))
            (let ((reply (json-parse-string line :object-type 'plist :array-type 'list
                                            :null-object nil :false-object :false)))
              (unless (and (equal (plist-get reply :type) "guard_status")
                           (equal (plist-get reply :guard) (plist-get endpoint :guard))
                           (equal (plist-get reply :worker) (plist-get endpoint :worker)))
                (error "Foreign native guard response"))
              (when (equal (plist-get reply :request_id) (process-get bridge 'guard-pending))
                (process-put bridge 'guard-reply reply)))
            (setq pending (substring pending end))))
        (when (> (string-bytes pending) 8192) (error "Oversized incomplete native guard response"))
        (process-put bridge 'guard-fragment pending))
    (error (process-put bridge 'guard-failure (error-message-string err)))))

(defun omnivox-native-guard--request (process command)
  "Ask PROCESS's original native guard for COMMAND and validate its reply."
  (let* ((bridge (process-get process 'omnivox-native-guard))
         (endpoint (process-get process 'omnivox-native-guard-endpoint))
         (id (1+ (or (and bridge (process-get bridge 'guard-sequence)) 0)))
         (deadline (+ (float-time) 6)))
    (unless (and (processp bridge) (process-live-p bridge))
      (error "Native cleanup authority is unavailable; replacement is blocked"))
    (when (process-get bridge 'guard-busy) (error "Native guard operation already in progress"))
    (process-put bridge 'guard-busy t)
    (process-put bridge 'guard-sequence id)
    (process-put bridge 'guard-pending id)
    (process-put bridge 'guard-reply nil)
    (unwind-protect
        (progn
          (process-send-string
           bridge (concat (json-serialize
                           (append (list :command command :request_id id
                                         :guard (plist-get endpoint :guard)
                                         :worker (plist-get endpoint :worker))
                                   (when (equal command "attach")
                                     (list :token (plist-get endpoint :token))))) "\n"))
          (while (and (not (process-get bridge 'guard-reply))
                      (not (process-get bridge 'guard-failure))
                      (process-live-p bridge) (< (float-time) deadline))
            (accept-process-output bridge 0.01))
          (when-let* ((failure (process-get bridge 'guard-failure))) (error "%s" failure))
          (let ((reply (process-get bridge 'guard-reply)))
            (unless reply (error "Native guard reply remains unconfirmed"))
            (when-let* ((failure (plist-get reply :error))) (error "%s" failure))
            reply))
      (process-put bridge 'guard-busy nil)
      (process-put bridge 'guard-pending nil))))

(defun omnivox-native-guard--attach (process owner)
  "Retain OWNER's independent control link before PROCESS can start speech."
  (when-let* ((endpoint (plist-get owner :guard)))
    (unless (process-get process 'omnivox-native-guard)
      (omnivox-native-guard--capacity)
      (unless (and (equal (plist-get endpoint :version) 1)
                   (equal (plist-get endpoint :transport) "linux-abstract")
                   (equal (plist-get endpoint :worker) (plist-get owner :worker))
                   (string-match-p "\\`[a-f0-9-]\\{36\\}\\'" (or (plist-get endpoint :guard) ""))
                   (equal (plist-get endpoint :address)
                          (concat "omnivox-guard-" (plist-get endpoint :guard)))
                   (string-match-p "\\`[a-f0-9]\\{64\\}\\'" (or (plist-get endpoint :token) "")))
        (error "Unsupported native guard descriptor"))
      ;; Retain identity before any fallible connection, including bridge spawn.
      (process-put process 'omnivox-native-guard-endpoint endpoint)
      (cl-pushnew process omnivox-native-guard--owners)
      (let* ((context (process-get process 'omnivox-library-launch-context))
             (process-environment (copy-sequence (plist-get context :environment)))
             (default-directory (plist-get context :directory))
             (bridge (make-process :name "Omnivox native guard" :noquery t
                                   :command (list (plist-get context :program) "--native-guard-control")
                                   :connection-type 'pipe :coding 'utf-8-unix
                                   :filter #'omnivox-native-guard--filter :sentinel #'ignore
                                   :stderr (tts--diagnostic-buffer "Native guard" t))))
        (process-put process 'omnivox-native-guard bridge)
        (process-put bridge 'guard-endpoint endpoint)
        (process-send-string bridge (concat (json-serialize endpoint) "\n"))
        (omnivox-native-guard--request process "attach")))))

(defun omnivox-native-guard--forget-confirmed (process)
  "Close PROCESS's control link only after its native retirement proof."
  (when (and (process-get process 'omnivox-library-retired)
             (not (when-let* ((bridge (process-get process 'omnivox-native-guard)))
                    (process-get bridge 'guard-busy))))
    (when-let* ((bridge (process-get process 'omnivox-native-guard)))
      (when (process-live-p bridge) (delete-process bridge)))
    (setq omnivox-native-guard--owners (delq process omnivox-native-guard--owners))))

(defun omnivox-native-guard--retire (process)
  "Confirm PROCESS's native tree and actual forwarding I/O are retired.
This transient proof permits emergency speech, never release of asset claims."
  (let ((proof (process-get process 'omnivox-native-guard-proof)))
    (when (and (eq (plist-get proof :tree_retired) t)
               (eq (plist-get proof :io_retired) t))
      (process-put process 'omnivox-library-retired t)))
  (unless (process-get process 'omnivox-library-retired)
    (let ((deadline (+ (float-time) 6))
          (reply (omnivox-native-guard--request process "retire")))
      (while (not (eq (plist-get reply :tree_retired) t))
        (when (>= (float-time) deadline) (error "Native tree retirement remains unconfirmed"))
        (setq reply (omnivox-native-guard--request process "status")))
      ;; The guard signals the actual retained owner handle.  A PID in Emacs
      ;; or saved management records is never signalling authority.
      (omnivox-native-guard--request process "retire-owner")
      (setq reply (omnivox-native-guard--request process "status"))
      (while (not (and (eq (plist-get reply :tree_retired) t)
                      (eq (plist-get reply :io_retired) t)))
        (when (>= (float-time) deadline) (error "Native I/O retirement remains unconfirmed"))
        (setq reply (omnivox-native-guard--request process "status")))
      (process-put process 'omnivox-native-guard-proof reply)
      (process-put process 'omnivox-library-retired t)))
  (omnivox-native-guard--forget-confirmed process))

(provide 'omnivox-native-guard)
;;; omnivox-native-guard.el ends here
