;;; specflow-bundle.el --- SpecFlow context bundling for AI assistants -*- lexical-binding: t; -*-

;; Copyright (C) 2025 TRM LLC
;; Author: TRM LLC
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: tools, org

;;; Commentary:

;; This module provides context bundling for AI assistants working on SpecFlow
;; projects.  It gathers project state, parent chain specs, and unit files
;; into a formatted bundle that can be copied to the clipboard or displayed.

;;; Code:

;;;; Requirements

(require 'specflow-org-store)

;;;; Helper Functions

(defun specflow-bundle--split-paths (value)
  "Split VALUE into a list of paths.
VALUE may be a single path or space-separated paths.
Returns a list of path strings, or nil if VALUE is nil or empty."
  (specflow-org-store--split-paths value))

(defun specflow-bundle--read-file-content (file-path &optional project-root)
  "Read content of FILE-PATH, returning string or placeholder if missing.
FILE-PATH may be absolute or relative to PROJECT-ROOT.
If PROJECT-ROOT is nil, it is discovered from the control plane.
Returns file content as string, or placeholder if file not found."
  (let* ((root (or project-root
                   (specflow-org-store--project-root-from-control-plane)))
         (abs-path (if (file-name-absolute-p file-path)
                       file-path
                     (expand-file-name file-path root))))
    (if (file-exists-p abs-path)
        (with-temp-buffer
          (insert-file-contents abs-path)
          (buffer-string))
      (message "Warning: File not found: %s" abs-path)
      (format "<file not found: %s>" file-path))))

(defun specflow-bundle--extract-next-task (&optional todo-path project-root)
  "Extract the first NEXT task from TODO-PATH.
TODO-PATH defaults to 'todo.org' at PROJECT-ROOT.
Returns the NEXT heading and its content as a string.
Returns placeholder if no NEXT task found."
  (let* ((root (or project-root
                   (specflow-org-store--project-root-from-control-plane)))
         (path (expand-file-name (or todo-path "todo.org") root)))
    (if (not (file-exists-p path))
        "<no root todo.org found>"
      (with-temp-buffer
        (insert-file-contents path)
        (goto-char (point-min))
        ;; Find first NEXT heading
        (if (re-search-forward "^\\(\\*+\\)[ \t]+NEXT[ \t]+\\(.*\\)$" nil t)
            (let* ((level (length (match-string 1)))
                   (title (match-string 2))
                   (start (line-beginning-position))
                   (end nil))
              ;; Find end: next heading of same or higher level, or EOF
              (forward-line 1)
              (if (re-search-forward (format "^\\*\\{1,%d\\}[ \t]" level) nil t)
                  (setq end (line-beginning-position))
                (setq end (point-max)))
              ;; Extract content
              (string-trim (buffer-substring-no-properties start end)))
          "<no NEXT task found>")))))

;;;; Formatting

(defun specflow-bundle--format-section (header content)
  "Format a section with HEADER and CONTENT."
  (format "## %s\n%s\n" header content))

(defun specflow-bundle--format-file-section (label path content)
  "Format a file subsection with LABEL, PATH, and CONTENT."
  (format "### %s: %s\n%s\n" label path content))

(defun specflow-bundle--format-output-text (project-state next-task parent-chain-content unit-content &optional timestamp)
  "Format the complete bundle output with full file contents (text mode).
PROJECT-STATE is a plist with :phase and :active-unit.
NEXT-TASK is the extracted NEXT task string.
PARENT-CHAIN-CONTENT is a list of (name . sections-alist) for each ancestor.
UNIT-CONTENT is a (name . sections-alist) for the active unit.
TIMESTAMP is optional; if nil, current time is used."
  (let ((ts (or timestamp (format-time-string "%Y-%m-%dT%H:%M:%S"))))
    (with-temp-buffer
      ;; Header
      (insert (format "# SpecFlow Context Bundle (Text)\n# Generated: %s\n\n" ts))
      ;; Project State
      (insert (specflow-bundle--format-section
               "Project State"
               (format "Phase: %s\nActive Unit: %s"
                       (plist-get project-state :phase)
                       (plist-get project-state :active-unit))))
      ;; NEXT Task
      (insert (specflow-bundle--format-section "NEXT Task" next-task))
      ;; Parent chain (root-to-leaf order - list is already in this order)
      (dolist (parent parent-chain-content)
        (let ((name (car parent))
              (sections (cdr parent)))
          (insert (format "## Parent: %s\n\n" name))
          (dolist (section sections)
            (let ((label (car section))
                  (path (cadr section))
                  (content (caddr section)))
              (insert (specflow-bundle--format-file-section label path content))))))
      ;; Active unit
      (let ((name (car unit-content))
            (sections (cdr unit-content)))
        (insert (format "## Unit: %s\n\n" name))
        (dolist (section sections)
          (let ((label (car section))
                (path (cadr section))
                (content (caddr section)))
            (insert (specflow-bundle--format-file-section label path content)))))
      (buffer-string))))

(defun specflow-bundle--format-output-paths (project-state next-task parent-chain-content unit-content &optional timestamp)
  "Format the bundle output with file paths only (paths mode).
PROJECT-STATE is a plist with :phase and :active-unit.
NEXT-TASK is the extracted NEXT task string.
PARENT-CHAIN-CONTENT is a list of (name . sections-alist) for each ancestor.
UNIT-CONTENT is a (name . sections-alist) for the active unit.
TIMESTAMP is optional; if nil, current time is used."
  (let ((ts (or timestamp (format-time-string "%Y-%m-%dT%H:%M:%S"))))
    (with-temp-buffer
      ;; Header
      (insert (format "# SpecFlow Context Bundle (Paths)\n# Generated: %s\n\n" ts))
      ;; Project State
      (insert (specflow-bundle--format-section
               "Project State"
               (format "Phase: %s\nActive Unit: %s"
                       (plist-get project-state :phase)
                       (plist-get project-state :active-unit))))
      ;; NEXT Task (include full content - typically short)
      (insert (specflow-bundle--format-section "NEXT Task" next-task))
      ;; Parent chain (paths only)
      (dolist (parent parent-chain-content)
        (let ((name (car parent))
              (sections (cdr parent)))
          (insert (format "## Parent: %s\n" name))
          (dolist (section sections)
            (let ((label (car section))
                  (path (cadr section)))
              (insert (format "- %s: %s\n" label path))))
          (insert "\n")))
      ;; Active unit (paths only)
      (let ((name (car unit-content))
            (sections (cdr unit-content)))
        (insert (format "## Unit: %s\n" name))
        (dolist (section sections)
          (let ((label (car section))
                (path (cadr section)))
            (insert (format "- %s: %s\n" label path))))
        (insert "\n"))
      ;; Footer
      (insert "Read the files above for full context.\n")
      (buffer-string))))

;;;; Core Functions

(defun specflow-bundle--gather-unit-content (unit-entry project-root)
  "Gather content for UNIT-ENTRY, returning (name . sections-list).
Each section is (LABEL PATH CONTENT)."
  (let* ((name (plist-get unit-entry :name))
         (spec-value (plist-get unit-entry :spec))
         (todo-value (plist-get unit-entry :todo))
         (rules-value (plist-get unit-entry :rules))
         (sections nil))
    ;; Gather SPEC files
    (dolist (path (specflow-bundle--split-paths spec-value))
      (push (list "SPEC" path (specflow-bundle--read-file-content path project-root))
            sections))
    ;; Gather TODO files
    (dolist (path (specflow-bundle--split-paths todo-value))
      (push (list "TODO" path (specflow-bundle--read-file-content path project-root))
            sections))
    ;; Gather RULES files
    (dolist (path (specflow-bundle--split-paths rules-value))
      (push (list "RULES" path (specflow-bundle--read-file-content path project-root))
            sections))
    (cons name (nreverse sections))))

(defun specflow-bundle--gather-context (&optional unit-name)
  "Gather all context data for UNIT-NAME (or active unit if nil).
Returns a plist with :project-state, :next-task, :parent-chain-content, :unit-content."
  (let* ((cp-path (specflow-org-store-find-control-plane))
         (project-root (specflow-org-store--project-root-from-control-plane cp-path))
         (project-state (specflow-org-store-read-project-state cp-path))
         (active-unit (or unit-name (plist-get project-state :active-unit)))
         (unit-entry (specflow-org-store-read-unit active-unit cp-path))
         (parent-names (specflow-org-store-validate-parent-chain active-unit cp-path))
         (next-task (specflow-bundle--extract-next-task nil project-root))
         (parent-chain-content nil)
         (unit-content nil))
    ;; Gather parent chain content (in root-to-leaf order)
    ;; parent-names is already in order from immediate parent to root
    ;; We need to reverse it for root-to-leaf presentation
    (dolist (parent-name (reverse parent-names))
      (let ((parent-entry (specflow-org-store-read-unit parent-name cp-path)))
        (push (specflow-bundle--gather-unit-content parent-entry project-root)
              parent-chain-content)))
    (setq parent-chain-content (nreverse parent-chain-content))
    ;; Gather active unit content
    (setq unit-content (specflow-bundle--gather-unit-content unit-entry project-root))
    ;; Return context plist
    (list :project-state project-state
          :next-task next-task
          :parent-chain-content parent-chain-content
          :unit-content unit-content)))

(defun specflow-bundle-context (&optional unit-name)
  "Generate a context bundle for UNIT-NAME in paths mode (default).
If UNIT-NAME is nil, uses the active unit from the control plane.
Returns a compact string with file paths for Claude Code to read.
For full file contents, use `specflow-bundle-context-text'."
  (let ((ctx (specflow-bundle--gather-context unit-name)))
    (specflow-bundle--format-output-paths
     (plist-get ctx :project-state)
     (plist-get ctx :next-task)
     (plist-get ctx :parent-chain-content)
     (plist-get ctx :unit-content))))

(defun specflow-bundle-context-text (&optional unit-name)
  "Generate a context bundle for UNIT-NAME in text mode (full content).
If UNIT-NAME is nil, uses the active unit from the control plane.
Returns a comprehensive string with full file contents.
For compact output with paths only, use `specflow-bundle-context'."
  (let ((ctx (specflow-bundle--gather-context unit-name)))
    (specflow-bundle--format-output-text
     (plist-get ctx :project-state)
     (plist-get ctx :next-task)
     (plist-get ctx :parent-chain-content)
     (plist-get ctx :unit-content))))

(defun specflow-bundle-context-no-timestamp (&optional unit-name)
  "Like `specflow-bundle-context' but with fixed timestamp for testing.
Uses paths mode (default)."
  (let ((ctx (specflow-bundle--gather-context unit-name)))
    (specflow-bundle--format-output-paths
     (plist-get ctx :project-state)
     (plist-get ctx :next-task)
     (plist-get ctx :parent-chain-content)
     (plist-get ctx :unit-content)
     "2025-01-01T00:00:00")))

(defun specflow-bundle-context-text-no-timestamp (&optional unit-name)
  "Like `specflow-bundle-context-text' but with fixed timestamp for testing.
Uses text mode (full content)."
  (let ((ctx (specflow-bundle--gather-context unit-name)))
    (specflow-bundle--format-output-text
     (plist-get ctx :project-state)
     (plist-get ctx :next-task)
     (plist-get ctx :parent-chain-content)
     (plist-get ctx :unit-content)
     "2025-01-01T00:00:00")))

;;;; Interactive Commands

(defun specflow-bundle ()
  "Generate and display a context bundle in paths mode (default).
Uses compact output with file paths for Claude Code to read.
Copies the bundle to the kill-ring and displays it in a buffer.
For full file contents, use `specflow-bundle-text'."
  (interactive)
  (let ((bundle (specflow-bundle-context)))
    ;; Copy to kill-ring
    (kill-new bundle)
    ;; Display in buffer
    (with-current-buffer (get-buffer-create "*SpecFlow Bundle*")
      (erase-buffer)
      (insert bundle)
      (goto-char (point-min))
      (display-buffer (current-buffer)))
    (message "SpecFlow bundle (paths) copied to kill-ring and displayed in *SpecFlow Bundle* buffer")))

(defun specflow-bundle-text ()
  "Generate and display a context bundle in text mode (full content).
Uses comprehensive output with full file contents for gptel or web Claude.
Copies the bundle to the kill-ring and displays it in a buffer.
For compact output with paths only, use `specflow-bundle'."
  (interactive)
  (let ((bundle (specflow-bundle-context-text)))
    ;; Copy to kill-ring
    (kill-new bundle)
    ;; Display in buffer
    (with-current-buffer (get-buffer-create "*SpecFlow Bundle*")
      (erase-buffer)
      (insert bundle)
      (goto-char (point-min))
      (display-buffer (current-buffer)))
    (message "SpecFlow bundle (text) copied to kill-ring and displayed in *SpecFlow Bundle* buffer")))

(provide 'specflow-bundle)
;;; specflow-bundle.el ends here
