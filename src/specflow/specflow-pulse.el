;;; specflow-pulse.el --- Real-time visual indicators for SpecFlow -*- lexical-binding: t; -*-

;; Copyright (C) 2026 TRM LLC
;; Author: TRM LLC
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: tools, org

;;; Commentary:

;; This module provides real-time visual indicators in the Emacs tab-bar
;; showing SpecFlow project state: active unit, current phase, and Claude status.
;;
;; Enable with: (specflow-pulse-mode 1)

;;; Code:

;;;; Requirements

(require 'cl-lib)
(require 'json)
(require 'filenotify)
(require 'specflow-org-store)

;;;; Customization

(defgroup specflow-pulse nil
  "Real-time visual indicators for SpecFlow."
  :group 'specflow
  :prefix "specflow-pulse-")

(defcustom specflow-pulse-refresh-interval 10
  "Fallback polling interval in seconds when file-watch unavailable."
  :type 'integer
  :group 'specflow-pulse)

(defcustom specflow-pulse-stale-threshold 300
  "Seconds after which Claude status file is considered stale."
  :type 'integer
  :group 'specflow-pulse)

(defcustom specflow-pulse-show-unit t
  "Whether to show unit name in addition to phase."
  :type 'boolean
  :group 'specflow-pulse)

;;;; Faces

(defface specflow-pulse-phase-plan
  '((t :foreground "#6699cc"))
  "Face for Plan phase."
  :group 'specflow-pulse)

(defface specflow-pulse-phase-specify
  '((t :foreground "#66cccc"))
  "Face for Specify phase."
  :group 'specflow-pulse)

(defface specflow-pulse-phase-scaffold
  '((t :foreground "#cc99cc"))
  "Face for Scaffold phase."
  :group 'specflow-pulse)

(defface specflow-pulse-phase-implement
  '((t :foreground "#99cc99"))
  "Face for Implement phase."
  :group 'specflow-pulse)

(defface specflow-pulse-phase-validate
  '((t :foreground "#cccc66"))
  "Face for Validate phase."
  :group 'specflow-pulse)

(defface specflow-pulse-phase-document
  '((t :foreground "#999999"))
  "Face for Document phase."
  :group 'specflow-pulse)

(defface specflow-pulse-claude-working
  '((t :foreground "#99cc99"))
  "Face for Claude working status."
  :group 'specflow-pulse)

(defface specflow-pulse-claude-idle
  '((t :foreground "#999999"))
  "Face for Claude idle status."
  :group 'specflow-pulse)

(defface specflow-pulse-claude-disconnected
  '((t :foreground "#cc6666"))
  "Face for Claude disconnected status."
  :group 'specflow-pulse)

(defface specflow-pulse-claude-unknown
  '((t :foreground "#cccc66"))
  "Face for Claude unknown status."
  :group 'specflow-pulse)

;;;; Internal State

(defvar specflow-pulse--file-watches nil
  "Alist of (project-root . watch-descriptor) for active file watches.")

(defvar specflow-pulse--poll-timer nil
  "Timer for fallback polling refresh.")

(defvar specflow-pulse--status-cache nil
  "Alist of (project-root . (timestamp . status)) for caching.")

(defvar specflow-pulse--original-tab-bar-format nil
  "Original `tab-bar-format' before pulse mode was enabled.")

;;;; Phase Face Mapping

(defconst specflow-pulse--phase-faces
  '(("Plan" . specflow-pulse-phase-plan)
    ("Specify" . specflow-pulse-phase-specify)
    ("Scaffold" . specflow-pulse-phase-scaffold)
    ("Implement" . specflow-pulse-phase-implement)
    ("Validate" . specflow-pulse-phase-validate)
    ("Document" . specflow-pulse-phase-document))
  "Alist mapping phase names to faces.")

;;;; Claude Status Icons

(defconst specflow-pulse--claude-icons
  '((working . "●")
    (idle . "○")
    (disconnected . "✕")
    (unknown . "?"))
  "Alist mapping Claude status to icon characters.")

;;;; Core Status Reading

(defun specflow-pulse--read-claude-status-file (project-root)
  "Read Claude status from .specflow/.claude-status in PROJECT-ROOT.
Returns a symbol: working, idle, error, or unknown."
  (let ((status-file (expand-file-name ".specflow/.claude-status" project-root)))
    (if (not (file-exists-p status-file))
        'unknown
      (condition-case nil
          (let* ((content (with-temp-buffer
                            (insert-file-contents status-file)
                            (buffer-string)))
                 (json-object-type 'alist)
                 (json-array-type 'list)
                 (data (json-read-from-string content))
                 (status (alist-get 'status data))
                 (timestamp (alist-get 'timestamp data))
                 (age (when timestamp
                        (float-time
                         (time-subtract (current-time)
                                        (date-to-time timestamp))))))
            (cond
             ((and age (> age specflow-pulse-stale-threshold)) 'unknown)
             ((equal status "working") 'working)
             ((equal status "idle") 'idle)
             ((equal status "error") 'error)
             (t 'unknown)))
        (error 'unknown)))))

(defun specflow-pulse--check-mcp-connection (project-root)
  "Check MCP connection state for PROJECT-ROOT if claude-code-ide is available.
Returns 'connected, 'disconnected, or nil if not available."
  (when (featurep 'claude-code-ide-mcp)
    (condition-case nil
        (let ((sessions (and (boundp 'claude-code-ide-mcp--sessions)
                             claude-code-ide-mcp--sessions)))
          (when sessions
            (let ((session (gethash project-root sessions)))
              (if (and session
                       (slot-boundp session 'client)
                       (slot-value session 'client))
                  'connected
                'disconnected))))
      (error nil))))

(defun specflow-pulse--determine-claude-status (project-root)
  "Determine Claude status for PROJECT-ROOT using file and MCP sources."
  (let ((file-status (specflow-pulse--read-claude-status-file project-root))
        (mcp-status (specflow-pulse--check-mcp-connection project-root)))
    (cond
     ;; File says working - trust it
     ((eq file-status 'working) 'working)
     ;; File says idle - trust it
     ((eq file-status 'idle) 'idle)
     ;; File says error - trust it
     ((eq file-status 'error) 'error)
     ;; File unknown, but MCP says connected - idle
     ((and (eq file-status 'unknown) (eq mcp-status 'connected)) 'idle)
     ;; File unknown, MCP says disconnected - disconnected
     ((and (eq file-status 'unknown) (eq mcp-status 'disconnected)) 'disconnected)
     ;; Everything unknown
     (t 'unknown))))

(defun specflow-pulse-status (&optional directory)
  "Return SpecFlow status for DIRECTORY as a plist.
Returns nil if DIRECTORY is not a SpecFlow project.

The returned plist has keys:
  :phase - Current phase string
  :unit - Active unit string
  :claude - Claude status symbol (working, idle, disconnected, unknown)
  :project-name - Project directory name"
  (let* ((dir (or directory default-directory))
         (control-plane (condition-case nil
                            (specflow-org-store-find-control-plane dir)
                          (error nil))))
    (when control-plane
      (let* ((project-root (file-name-directory
                            (directory-file-name
                             (file-name-directory control-plane))))
             (state (condition-case nil
                        (specflow-org-store-read-project-state control-plane)
                      (error nil))))
        (when state
          (list :phase (plist-get state :phase)
                :unit (plist-get state :active-unit)
                :claude (specflow-pulse--determine-claude-status project-root)
                :project-name (file-name-nondirectory
                               (directory-file-name project-root))))))))

;;;; Per-Tab Project Detection

(defun specflow-pulse--current-project ()
  "Return the project root for the current tab's buffer.
Returns nil if not in a SpecFlow project."
  (let* ((buffer (window-buffer (selected-window)))
         (dir (buffer-local-value 'default-directory buffer))
         (control-plane (condition-case nil
                            (specflow-org-store-find-control-plane dir)
                          (error nil))))
    (when control-plane
      (file-name-directory
       (directory-file-name
        (file-name-directory control-plane))))))

;;;; Tab-Bar Segment Rendering

(defun specflow-pulse--phase-face (phase)
  "Return the face for PHASE."
  (or (cdr (assoc phase specflow-pulse--phase-faces))
      'default))

(defun specflow-pulse--claude-face (status)
  "Return the face for Claude STATUS."
  (pcase status
    ('working 'specflow-pulse-claude-working)
    ('idle 'specflow-pulse-claude-idle)
    ('disconnected 'specflow-pulse-claude-disconnected)
    (_ 'specflow-pulse-claude-unknown)))

(defun specflow-pulse--claude-icon (status)
  "Return the icon for Claude STATUS."
  (or (cdr (assoc status specflow-pulse--claude-icons)) "?"))

(defun specflow-pulse--format-segment (status)
  "Format the tab-bar segment string from STATUS plist."
  (let* ((phase (plist-get status :phase))
         (unit (plist-get status :unit))
         (claude (plist-get status :claude))
         (icon (specflow-pulse--claude-icon claude))
         (icon-face (specflow-pulse--claude-face claude))
         (phase-face (specflow-pulse--phase-face phase))
         (text (if specflow-pulse-show-unit
                   (format "%s:%s" phase unit)
                 phase)))
    (concat " "
            (propertize icon 'face icon-face)
            " "
            (propertize text 'face phase-face)
            " ")))

(defun specflow-pulse--tab-bar-segment ()
  "Return the SpecFlow status segment for the tab-bar."
  (let ((status (specflow-pulse-status)))
    (if status
        (specflow-pulse--format-segment status)
      "")))

;;;; File-Watch Refresh Mechanism

(defun specflow-pulse--refresh-tab-bar ()
  "Force refresh of the tab-bar display."
  (when (bound-and-true-p tab-bar-mode)
    (force-mode-line-update t)))

(defun specflow-pulse--on-file-change (_event)
  "Handle file change EVENT by refreshing the tab-bar."
  (specflow-pulse--refresh-tab-bar))

(defun specflow-pulse--setup-watch (project-root)
  "Setup file watches for PROJECT-ROOT."
  (let ((specflow-dir (expand-file-name ".specflow" project-root)))
    (when (file-directory-p specflow-dir)
      (condition-case nil
          (let ((descriptor (file-notify-add-watch
                             specflow-dir
                             '(change)
                             #'specflow-pulse--on-file-change)))
            (push (cons project-root descriptor) specflow-pulse--file-watches)
            descriptor)
        (error nil)))))

(defun specflow-pulse--remove-watch (project-root)
  "Remove file watch for PROJECT-ROOT."
  (let ((entry (assoc project-root specflow-pulse--file-watches)))
    (when entry
      (condition-case nil
          (file-notify-rm-watch (cdr entry))
        (error nil))
      (setq specflow-pulse--file-watches
            (assoc-delete-all project-root specflow-pulse--file-watches)))))

(defun specflow-pulse--setup-watches-for-open-projects ()
  "Setup file watches for all open SpecFlow projects."
  (let ((seen-roots nil))
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (let ((root (specflow-pulse--current-project)))
          (when (and root (not (member root seen-roots)))
            (push root seen-roots)
            (unless (assoc root specflow-pulse--file-watches)
              (specflow-pulse--setup-watch root))))))))

(defun specflow-pulse--cleanup-watches ()
  "Remove all file watches."
  (dolist (entry specflow-pulse--file-watches)
    (condition-case nil
        (file-notify-rm-watch (cdr entry))
      (error nil)))
  (setq specflow-pulse--file-watches nil))

;;;; Polling Fallback

(defun specflow-pulse--poll-refresh ()
  "Polling fallback to refresh tab-bar."
  (specflow-pulse--refresh-tab-bar))

(defun specflow-pulse--start-poll-timer ()
  "Start the fallback polling timer."
  (unless specflow-pulse--poll-timer
    (setq specflow-pulse--poll-timer
          (run-with-timer specflow-pulse-refresh-interval
                          specflow-pulse-refresh-interval
                          #'specflow-pulse--poll-refresh))))

(defun specflow-pulse--stop-poll-timer ()
  "Stop the fallback polling timer."
  (when specflow-pulse--poll-timer
    (cancel-timer specflow-pulse--poll-timer)
    (setq specflow-pulse--poll-timer nil)))

;;;; Public Interface

(defun specflow-pulse-refresh ()
  "Force refresh of the SpecFlow pulse display."
  (interactive)
  (specflow-pulse--refresh-tab-bar))

;;;; Global Minor Mode

(defun specflow-pulse--enable ()
  "Enable specflow-pulse-mode."
  ;; Save original tab-bar-format
  (setq specflow-pulse--original-tab-bar-format tab-bar-format)
  ;; Add our segment to tab-bar-format
  (unless (memq 'specflow-pulse--tab-bar-segment tab-bar-format)
    (setq tab-bar-format
          (append tab-bar-format '(specflow-pulse--tab-bar-segment))))
  ;; Ensure tab-bar-mode is enabled
  (unless (bound-and-true-p tab-bar-mode)
    (tab-bar-mode 1))
  ;; Setup file watches
  (specflow-pulse--setup-watches-for-open-projects)
  ;; Start polling timer
  (specflow-pulse--start-poll-timer)
  ;; Initial refresh
  (specflow-pulse--refresh-tab-bar))

(defun specflow-pulse--disable ()
  "Disable specflow-pulse-mode."
  ;; Restore original tab-bar-format
  (when specflow-pulse--original-tab-bar-format
    (setq tab-bar-format specflow-pulse--original-tab-bar-format)
    (setq specflow-pulse--original-tab-bar-format nil))
  ;; Cleanup file watches
  (specflow-pulse--cleanup-watches)
  ;; Stop polling timer
  (specflow-pulse--stop-poll-timer)
  ;; Refresh to remove our segment
  (specflow-pulse--refresh-tab-bar))

;;;###autoload
(define-minor-mode specflow-pulse-mode
  "Global minor mode for SpecFlow visual indicators in tab-bar.

When enabled, displays the current phase, active unit, and Claude
status in the Emacs tab-bar. Each tab shows the status for its
own project."
  :global t
  :lighter nil
  :group 'specflow-pulse
  (if specflow-pulse-mode
      (specflow-pulse--enable)
    (specflow-pulse--disable)))

(provide 'specflow-pulse)
;;; specflow-pulse.el ends here
