;;; specflow-hydrate.el --- SpecFlow conversation framing and headers -*- lexical-binding: t; -*-

;; Copyright (C) 2025 TRM LLC
;; Author: TRM LLC
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: tools, org

;;; Commentary:

;; This module provides conversation framing for AI sessions.
;; It generates headers with phase context, file pointers, and NEXT tasks.
;; It also provides navigation helpers and optional phase violation scanning.
;;
;; Dependencies: specflow-org-store and specflow-rules (no bundle dependency).

;;; Code:

;;;; Requirements

(require 'specflow-org-store)
(require 'specflow-rules)

;;;; Helper Functions

(defun specflow-hydrate--split-paths (value)
  "Split VALUE into a list of paths.
VALUE may be a single path or space-separated paths.
Returns a list of path strings, or nil if VALUE is nil or empty."
  (when (and value (not (string-empty-p (string-trim value))))
    (split-string value "[ \t]+" t)))

;;;; Phase Actions

(defun specflow-hydrate--phase-actions (phase)
  "Return allowed actions text for PHASE."
  (let ((phase-lower (downcase phase)))
    (cond
     ((string= phase-lower "plan")
      "- Summarize understanding of the task
- Identify constraints and open questions
- Propose options and approaches
- DO NOT write or modify code
- DO NOT write specs or TODOs")
     ((string= phase-lower "specify")
      "- Edit spec.org only
- Define outcomes and requirements
- DO NOT write implementation code")
     ((string= phase-lower "scaffold")
      "- Write todo.org (outcome-based tasks)
- DO NOT write implementation code")
     ((string= phase-lower "implement")
      "- Write code and tests strictly per spec
- Keep diffs minimal and focused
- Update tests for changed behavior")
     ((string= phase-lower "validate")
      "- Run tests and verify behavior
- Do NOT change behavior
- Report discrepancies")
     ((string= phase-lower "document")
      "- Write documentation only
- Do NOT change code or behavior")
     (t
      "- Follow phase-specific rules
- Ask for clarification if unclear"))))

;;;; NEXT Task Extraction

(defun specflow-hydrate--extract-next-task (&optional todo-path project-root)
  "Extract the first NEXT task from TODO-PATH.
PROJECT-ROOT is used to resolve relative paths.
Returns the heading and its immediate body, or a placeholder if not found."
  (let* ((root (or project-root (specflow-org-store--project-root-from-control-plane)))
         (path (or todo-path ".specflow/todo.org"))
         (full-path (expand-file-name path root)))
    (if (not (file-exists-p full-path))
        "<no root todo.org found>"
      (with-temp-buffer
        (insert-file-contents full-path)
        (goto-char (point-min))
        (if (not (re-search-forward "^\\*+[ \t]+NEXT[ \t]+" nil t))
            "<no NEXT task found>"
          ;; Found NEXT - extract heading and body
          (beginning-of-line)
          (let ((start (point))
                (end nil))
            ;; Find end - next heading or end of buffer
            (forward-line 1)
            (if (re-search-forward "^\\*" nil t)
                (progn
                  (beginning-of-line)
                  (setq end (point)))
              (setq end (point-max)))
            (string-trim-right (buffer-substring-no-properties start end))))))))

;;;; File Pointer Gathering

(defun specflow-hydrate--gather-file-pointers (unit-entry parent-chain project-root cp-path)
  "Gather file pointers for header from UNIT-ENTRY and PARENT-CHAIN.
PROJECT-ROOT is the project root directory.
CP-PATH is the control plane path."
  (let ((pointers nil))
    ;; 1. CLAUDE.md (project rules)
    (let ((claude-md (expand-file-name "CLAUDE.md" project-root)))
      (when (file-exists-p claude-md)
        (push (format "- %s (project rules)" claude-md) pointers)))
    ;; 2. Parent specs (authoritative constraints)
    (dolist (parent parent-chain)
      (let* ((parent-entry (specflow-org-store-read-unit parent cp-path))
             (parent-spec (plist-get parent-entry :spec)))
        (when parent-spec
          (dolist (spec-path (specflow-hydrate--split-paths parent-spec))
            (push (format "- %s (parent: %s)" spec-path parent) pointers)))))
    ;; 3. Control plane
    (push (format "- %s (control plane)" cp-path) pointers)
    ;; 4-5. Unit files
    (when unit-entry
      (let ((spec (plist-get unit-entry :spec))
            (todo (plist-get unit-entry :todo)))
        (when spec
          (push (format "- %s (unit SPEC)" spec) pointers))
        (when todo
          (push (format "- %s (unit TODO)" todo) pointers))))
    ;; 6. Root todo.org
    (let ((root-todo (expand-file-name ".specflow/todo.org" project-root)))
      (push (format "- %s (root todo)" root-todo) pointers))
    (nreverse pointers)))

;;;; Header Generation

(defun specflow-hydrate--generate-header (&optional unit-name)
  "Generate conversation header for UNIT-NAME or active unit.
Returns a multi-line string with phase context, files, and NEXT task."
  (let* ((cp-path (specflow-org-store-find-control-plane))
         (_ (unless cp-path
              (signal 'specflow-control-plane-not-found
                      (list "No control plane found"))))
         (state (specflow-org-store-read-project-state cp-path))
         (phase (plist-get state :phase))
         (active-unit (or unit-name (plist-get state :active-unit)))
         (unit-entry (specflow-org-store-read-unit active-unit cp-path))
         (parent-chain (specflow-org-store-validate-parent-chain active-unit cp-path))
         (project-root (specflow-org-store--project-root-from-control-plane cp-path))
         (file-pointers (specflow-hydrate--gather-file-pointers
                         unit-entry parent-chain project-root cp-path))
         (phase-actions (specflow-hydrate--phase-actions phase))
         (next-task (specflow-hydrate--extract-next-task ".specflow/todo.org" project-root)))
    (concat
     (format "Active unit: %s\n" active-unit)
     (format "Phase: %s\n" phase)
     (format "Parent chain: %s\n"
             (if parent-chain (mapconcat #'identity parent-chain " → ") "none"))
     "\nFiles to consult:\n"
     (mapconcat #'identity file-pointers "\n")
     "\n\nAllowed actions in this phase:\n"
     phase-actions
     "\n\nSTOP conditions:\n"
     "- If an action would violate the current phase, STOP and ask for confirmation.\n"
     "- If an interface change is required, STOP and ask for approval.\n"
     "\nCanonical NEXT task:\n"
     next-task
     "\n")))

;;;; Safe Buffer Detection

(defun specflow-hydrate--safe-buffer-p ()
  "Return non-nil if current buffer is safe for header insertion.
Safe buffers: *scratch*, buffers with gptel/claude/chat in name."
  (let ((name (buffer-name)))
    (or (string= name "*scratch*")
        (string-match-p "gptel\\|claude\\|chat" (downcase name)))))

;;;; Interactive Commands

(defun specflow-hydrate-copy-header ()
  "Generate header and copy to kill-ring."
  (interactive)
  (let ((header (specflow-hydrate--generate-header)))
    (kill-new header)
    (message "SpecFlow header copied to kill-ring (%d chars)" (length header))))

(defun specflow-hydrate-preview-header ()
  "Generate header and display in read-only buffer."
  (interactive)
  (let ((header (specflow-hydrate--generate-header)))
    (with-current-buffer (get-buffer-create "*SpecFlow Header*")
      (setq buffer-read-only nil)
      (erase-buffer)
      (insert header)
      (goto-char (point-min))
      (setq buffer-read-only t)
      (display-buffer (current-buffer)))
    (message "SpecFlow header displayed in *SpecFlow Header* buffer")))

(defun specflow-hydrate-insert-header ()
  "Insert header at point, with safety prompt for non-safe buffers."
  (interactive)
  (when (or (specflow-hydrate--safe-buffer-p)
            (yes-or-no-p "Insert SpecFlow header in this buffer? "))
    (let ((header (specflow-hydrate--generate-header)))
      (insert header)
      (message "SpecFlow header inserted"))))

(defun specflow-hydrate-insert-next ()
  "Insert NEXT task excerpt at point, with safety prompt for non-safe buffers."
  (interactive)
  (when (or (specflow-hydrate--safe-buffer-p)
            (yes-or-no-p "Insert NEXT task in this buffer? "))
    (let* ((cp-path (specflow-org-store-find-control-plane))
           (project-root (and cp-path (specflow-org-store--project-root-from-control-plane cp-path)))
           (next-task (specflow-hydrate--extract-next-task ".specflow/todo.org" project-root)))
      (insert next-task)
      (message "NEXT task inserted"))))

;;;; Navigation Helpers

(defun specflow-hydrate-open-control-plane ()
  "Open the control plane file."
  (interactive)
  (let ((cp-path (specflow-org-store-find-control-plane)))
    (unless cp-path
      (user-error "No control plane found"))
    (find-file cp-path)
    (goto-char (point-min))
    (when (re-search-forward "^\\* Project" nil t)
      (beginning-of-line))
    (message "Opened control plane: %s" cp-path)))

(defun specflow-hydrate-open-root-todo ()
  "Open the root todo.org file (.specflow/todo.org)."
  (interactive)
  (let* ((cp-path (specflow-org-store-find-control-plane))
         (project-root (and cp-path (specflow-org-store--project-root-from-control-plane cp-path)))
         (todo-path (and project-root (expand-file-name ".specflow/todo.org" project-root))))
    (unless todo-path
      (user-error "No project root found"))
    (unless (file-exists-p todo-path)
      (user-error "Root todo.org not found: %s" todo-path))
    (find-file todo-path)
    (goto-char (point-min))
    (when (re-search-forward "^\\*+[ \t]+NEXT" nil t)
      (beginning-of-line))
    (message "Opened root todo: %s" todo-path)))

(defun specflow-hydrate-open-active-unit-spec ()
  "Open the active unit's spec file."
  (interactive)
  (let* ((cp-path (specflow-org-store-find-control-plane))
         (state (and cp-path (specflow-org-store-read-project-state cp-path)))
         (active-unit (plist-get state :active-unit))
         (unit-entry (and active-unit (specflow-org-store-read-unit active-unit cp-path)))
         (spec (plist-get unit-entry :spec)))
    (unless spec
      (user-error "No SPEC found for unit: %s" active-unit))
    (let ((spec-path (car (specflow-hydrate--split-paths spec))))
      (find-file (expand-file-name spec-path (file-name-directory cp-path)))
      (message "Opened unit spec: %s" spec-path))))

(defun specflow-hydrate-open-active-unit-todo ()
  "Open the active unit's todo file."
  (interactive)
  (let* ((cp-path (specflow-org-store-find-control-plane))
         (state (and cp-path (specflow-org-store-read-project-state cp-path)))
         (active-unit (plist-get state :active-unit))
         (unit-entry (and active-unit (specflow-org-store-read-unit active-unit cp-path)))
         (todo (plist-get unit-entry :todo)))
    (unless todo
      (user-error "No TODO found for unit: %s" active-unit))
    (find-file (expand-file-name todo (file-name-directory cp-path)))
    (message "Opened unit todo: %s" todo)))

;;;; Violation Patterns

(defun specflow-hydrate--violation-patterns (phase)
  "Return regex patterns that indicate phase violations for PHASE."
  (let ((phase-lower (downcase phase)))
    (cond
     ((member phase-lower '("plan" "specify" "scaffold"))
      ;; In early phases, code and diffs are violations
      '("^```"                           ; Code blocks
        "^\\+\\+\\+\\|^---"               ; Diff headers
        "^@@.*@@"                         ; Diff hunks
        "I implemented\\|I changed\\|I committed\\|I wrote the"
        "\\bdef \\|\\bfunction \\|\\bclass \\|\\bconst \\|\\blet \\|\\bvar "))
     ((string= phase-lower "validate")
      ;; In validate, behavioral changes are violations
      '("I changed the behavior\\|I modified the implementation\\|I refactored"))
     ((string= phase-lower "document")
      ;; In document, code changes are violations
      '("I changed\\|I modified\\|I updated the code\\|I fixed"))
     (t nil))))  ; Implement phase has no warnings

(defun specflow-hydrate--scan-for-violations (text phase)
  "Scan TEXT for phase violations given PHASE.
Returns list of (line-num . matched-text) pairs."
  (let ((patterns (specflow-hydrate--violation-patterns phase))
        (violations nil)
        (line-num 0))
    (when patterns
      (with-temp-buffer
        (insert text)
        (goto-char (point-min))
        (while (not (eobp))
          (setq line-num (1+ line-num))
          (let ((line (buffer-substring-no-properties
                       (line-beginning-position) (line-end-position))))
            (dolist (pattern patterns)
              (when (string-match-p pattern line)
                (push (cons line-num (string-trim line)) violations))))
          (forward-line 1))))
    (nreverse violations)))

(defun specflow-hydrate-scan-buffer ()
  "Scan the current buffer for potential phase violations."
  (interactive)
  (let* ((cp-path (specflow-org-store-find-control-plane))
         (state (and cp-path (specflow-org-store-read-project-state cp-path)))
         (phase (plist-get state :phase))
         (text (buffer-substring-no-properties (point-min) (point-max)))
         (violations (specflow-hydrate--scan-for-violations text phase)))
    (if (not violations)
        (message "No phase violations detected (Phase: %s)" phase)
      (with-current-buffer (get-buffer-create "*SpecFlow Warnings*")
        (erase-buffer)
        (insert (format "Phase violations detected (Phase: %s)\n\n" phase))
        (dolist (v violations)
          (insert (format "Line %d: %s\n" (car v) (cdr v))))
        (display-buffer (current-buffer)))
      (message "%d potential violations found (see *SpecFlow Warnings*)" (length violations)))))

(defun specflow-hydrate-scan-region (start end)
  "Scan region from START to END for potential phase violations."
  (interactive "r")
  (let* ((cp-path (specflow-org-store-find-control-plane))
         (state (and cp-path (specflow-org-store-read-project-state cp-path)))
         (phase (plist-get state :phase))
         (text (buffer-substring-no-properties start end))
         (violations (specflow-hydrate--scan-for-violations text phase)))
    (if (not violations)
        (message "No phase violations in region (Phase: %s)" phase)
      (message "%d potential violations in region: %s"
               (length violations)
               (mapconcat (lambda (v) (format "L%d" (car v))) violations ", ")))))

;;;; CLAUDE.md Generation

(defun specflow-hydrate--format-rule-as-markdown (rule)
  "Format a single RULE plist as markdown.
Returns a string with ## heading and content."
  (let ((title (plist-get rule :title))
        (content (plist-get rule :content)))
    (format "## %s\n\n%s" title content)))

(defun specflow-hydrate--format-rules-as-markdown (rules)
  "Format RULES list as markdown for CLAUDE.md.
Returns a complete markdown string with header and all rules."
  (let ((header (concat
                 "# SpecFlow – AI Assistant Rules\n\n"
                 "<!-- AUTO-GENERATED from rules.org – DO NOT EDIT DIRECTLY -->\n"
                 "<!-- Regenerate with: M-x specflow-hydrate-rules -->\n"
                 (format "<!-- Generated: %s -->\n" (format-time-string "%Y-%m-%d"))
                 "\n---\n"))
        (body (mapconcat #'specflow-hydrate--format-rule-as-markdown
                         rules
                         "\n\n---\n\n")))
    (concat header "\n" body "\n")))

(defun specflow-hydrate-rules (&optional target-dir)
  "Generate CLAUDE.md from .specflow/rules.org.

TARGET-DIR is the directory to write CLAUDE.md to.
Defaults to the project root (from control plane).

Finds the project root via control plane discovery, loads all rules
from .specflow/rules.org, formats them as markdown, and writes to
CLAUDE.md in the target directory.

Signals `specflow-rules-file-not-found' if .specflow/rules.org does not exist."
  (interactive)
  (let* ((project-root (specflow-org-store--project-root-from-control-plane))
         (_ (unless project-root
              (user-error "Cannot determine project root")))
         (rules-path (expand-file-name ".specflow/rules.org" project-root))
         (_ (unless (file-exists-p rules-path)
              (signal 'specflow-rules-file-not-found
                      (list (format "rules.org not found: %s" rules-path)))))
         (rules (specflow-rules-load rules-path))
         (markdown (specflow-hydrate--format-rules-as-markdown rules))
         (target (or target-dir project-root))
         (output-path (expand-file-name "CLAUDE.md" target)))
    (with-temp-file output-path
      (insert markdown))
    (message "CLAUDE.md regenerated (%d rules)" (length rules))))

(provide 'specflow-hydrate)
;;; specflow-hydrate.el ends here
