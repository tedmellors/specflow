;;; specflow-compose.el --- SpecFlow task-specific prompt generation -*- lexical-binding: t; -*-

;; Copyright (C) 2025 TRM LLC
;; Author: TRM LLC
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: tools, org

;;; Commentary:

;; This module generates task-specific prompts for AI assistants.
;; It provides guided template buffers for common SpecFlow workflows:
;; - new-unit: Create a new SpecFlow unit
;; - edit-spec: Edit a unit's specification
;; - new-feature: Add a feature to an existing unit
;; - refactor: Plan code refactoring
;;
;; Dependencies: specflow-org-store only (no hydrate or bundle dependency).

;;; Code:

;;;; Requirements

(require 'specflow-org-store)

;;;; Minor Mode

(defvar specflow-compose-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'specflow-compose--generate)
    (define-key map (kbd "C-c C-k") #'specflow-compose--cancel)
    map)
  "Keymap for `specflow-compose-mode'.")

(define-minor-mode specflow-compose-mode
  "Minor mode for SpecFlow compose template buffers.

\\{specflow-compose-mode-map}"
  :lighter " Compose"
  :keymap specflow-compose-mode-map)

(defvar-local specflow-compose--task-type nil
  "The type of compose task for the current buffer.")

(defvar-local specflow-compose--unit-name nil
  "The target unit name for the current compose task.")

;;;; Phase Enforcement

(defun specflow-compose--check-plan-phase ()
  "Check if current phase is Plan. Return t if ok, nil and message if not."
  (condition-case err
      (let* ((state (specflow-org-store-read-project-state))
             (phase (plist-get state :phase)))
        (if (string= (downcase phase) "plan")
            t
          (message "Compose commands require Plan phase. Current phase: %s" phase)
          nil))
    (specflow-control-plane-not-found
     (message "Control plane not found. Cannot run compose commands.")
     nil)))

;;;; Template Definitions

(defun specflow-compose--template-new-unit ()
  "Return template structure for new-unit."
  '(("Unit Name" . t)
    ("Parent" . t)
    ("Purpose (one line)" . t)
    ("Problem it solves" . t)
    ("In Scope" . t)
    ("Out of Scope" . nil)
    ("Dependencies" . nil)
    ("Key Commands/Functions" . nil)))

(defun specflow-compose--template-edit-spec ()
  "Return template structure for edit-spec."
  '(("Which Unit" . t)
    ("What to Change" . t)
    ("Why (rationale)" . t)
    ("Constraints" . nil)))

(defun specflow-compose--template-new-feature ()
  "Return template structure for new-feature."
  '(("Which Unit" . t)
    ("Feature Description" . t)
    ("In Scope" . t)
    ("Out of Scope" . nil)
    ("Affects Parent Architecture? (yes/no/unsure)" . t)))

(defun specflow-compose--template-refactor ()
  "Return template structure for refactor."
  '(("Which Unit" . t)
    ("What to Refactor" . t)
    ("Why (rationale)" . t)
    ("Constraints" . nil)))

;;;; Template Buffer Creation

(defun specflow-compose--create-buffer (task-type title template &optional default-unit)
  "Create a compose template buffer.
TASK-TYPE is a symbol (new-unit, edit-spec, etc.).
TITLE is the buffer title.
TEMPLATE is an alist of (question . required-p).
DEFAULT-UNIT is optional default for unit fields."
  (let ((buf (get-buffer-create (format "*SpecFlow Compose: %s*" title))))
    (with-current-buffer buf
      (erase-buffer)
      (org-mode)
      (insert (format "#+TITLE: %s\n\n" title))
      ;; Insert template questions
      (dolist (item template)
        (let ((question (car item))
              (required (cdr item)))
          (insert (format "* %s%s\n"
                          question
                          (if required " (required)" "")))
          ;; Insert default for unit fields
          (when (and default-unit
                     (string-match-p "Which Unit" question))
            (insert default-unit))
          (insert "\n")))
      ;; Insert footer
      (insert "────────────────────────────────────────\n")
      (insert "C-c C-c  Generate prompt and copy to kill-ring\n")
      (insert "C-c C-k  Cancel\n")
      ;; Set up mode
      (specflow-compose-mode 1)
      (setq-local specflow-compose--task-type task-type)
      (setq-local specflow-compose--unit-name default-unit)
      (goto-char (point-min))
      (re-search-forward "^\\* " nil t)
      (forward-line 1))
    (switch-to-buffer buf)))

;;;; Buffer Content Extraction

(defun specflow-compose--extract-answers ()
  "Extract answers from the current compose buffer.
Returns an alist of (question . answer)."
  (save-excursion
    (goto-char (point-min))
    (let ((answers nil))
      (while (re-search-forward "^\\* \\([^(\n]+\\)" nil t)
        (let* ((question (string-trim (match-string 1)))
               (start (progn (forward-line 1) (point)))
               (end (or (save-excursion
                          (if (re-search-forward "^\\*\\|^─" nil t)
                              (line-beginning-position)
                            (point-max)))
                        (point-max)))
               (answer (string-trim (buffer-substring-no-properties start end))))
          (push (cons question answer) answers)))
      (nreverse answers))))

;;;; Context File Selection

(defun specflow-compose--context-files-new-unit ()
  "Return context files for new-unit task."
  (let* ((cp-path (specflow-org-store-find-control-plane))
         (project-root (specflow-org-store--project-root-from-control-plane cp-path)))
    (list
     (cons "units/core/architecture.org" "architecture")
     (cons (file-relative-name cp-path project-root) "control plane")
     (cons ".specflow/todo.org" "root tasks"))))

(defun specflow-compose--context-files-edit-spec (unit-name)
  "Return context files for edit-spec task on UNIT-NAME."
  (condition-case nil
      (let* ((cp-path (specflow-org-store-find-control-plane))
             (unit-entry (specflow-org-store-read-unit unit-name cp-path))
             (parent-chain (specflow-org-store-validate-parent-chain unit-name cp-path))
             (files nil))
        ;; Unit spec
        (push (cons (plist-get unit-entry :spec) "unit spec") files)
        ;; Parent specs
        (dolist (parent parent-chain)
          (let ((parent-entry (specflow-org-store-read-unit parent cp-path)))
            (push (cons (plist-get parent-entry :spec)
                        (format "parent: %s" parent))
                  files)))
        ;; Control plane
        (let ((project-root (specflow-org-store--project-root-from-control-plane cp-path)))
          (push (cons (file-relative-name cp-path project-root) "control plane") files))
        (nreverse files))
    (error
     (list (cons ".specflow/specflow.org" "control plane")))))

(defun specflow-compose--context-files-new-feature (unit-name affects-parent)
  "Return context files for new-feature task.
UNIT-NAME is the target unit.
AFFECTS-PARENT is \"yes\", \"no\", or \"unsure\"."
  (condition-case nil
      (let* ((cp-path (specflow-org-store-find-control-plane))
             (unit-entry (specflow-org-store-read-unit unit-name cp-path))
             (parent-chain (specflow-org-store-validate-parent-chain unit-name cp-path))
             (files nil))
        ;; Unit spec and todo
        (push (cons (plist-get unit-entry :spec) "unit spec") files)
        (push (cons (plist-get unit-entry :todo) "unit todo") files)
        ;; Parent specs if affects parent or unsure
        (when (member (downcase affects-parent) '("yes" "unsure"))
          (dolist (parent parent-chain)
            (let ((parent-entry (specflow-org-store-read-unit parent cp-path)))
              (push (cons (plist-get parent-entry :spec)
                          (format "parent: %s" parent))
                    files))))
        (nreverse files))
    (error
     (list (cons ".specflow/specflow.org" "control plane")))))

(defun specflow-compose--context-files-refactor (unit-name)
  "Return context files for refactor task on UNIT-NAME."
  (condition-case nil
      (let* ((cp-path (specflow-org-store-find-control-plane))
             (unit-entry (specflow-org-store-read-unit unit-name cp-path)))
        (list
         (cons (plist-get unit-entry :spec) "unit spec")
         (cons (plist-get unit-entry :todo) "unit todo")))
    (error
     (list (cons ".specflow/specflow.org" "control plane")))))

;;;; Prompt Generation

(defun specflow-compose--format-requirements (answers)
  "Format ANSWERS alist as requirements section."
  (with-temp-buffer
    (dolist (item answers)
      (let ((question (car item))
            (answer (cdr item)))
        (unless (string-empty-p answer)
          (if (string-match-p "\n" answer)
              (progn
                (insert (format "- %s:\n" question))
                (dolist (line (split-string answer "\n" t))
                  (insert (format "  - %s\n" (string-trim line)))))
            (insert (format "- %s: %s\n" question answer))))))
    (buffer-string)))

(defun specflow-compose--format-context-files (files)
  "Format FILES alist as context section."
  (with-temp-buffer
    (insert "Read these files for context:\n")
    (dolist (item files)
      (let ((path (car item))
            (desc (cdr item)))
        (insert (format "- %s (%s)\n" path desc))))
    (buffer-string)))

(defun specflow-compose--instructions-new-unit (unit-name parent)
  "Return instructions for creating UNIT-NAME with PARENT."
  (format "You are in Plan phase. Create this new unit by:
1. Update .specflow/units/core/architecture.org with %s unit description
2. Add %s entry to Units section in control plane (.specflow/specflow.org)
3. Create .specflow/units/%s/ directory
4. Draft spec.org based on requirements above
5. Update .specflow/todo.org with NEXT task for %s

Phase rules: Do NOT write implementation code. Planning only."
          unit-name unit-name unit-name unit-name))

(defun specflow-compose--instructions-edit-spec (unit-name)
  "Return instructions for editing spec of UNIT-NAME."
  (format "You are in Plan phase. Edit the specification for %s:
1. Read the current spec at .specflow/units/%s/spec.org
2. Make the requested changes
3. Ensure changes are consistent with parent constraints
4. Update any affected sections

Phase rules: Only edit spec.org. Do NOT write implementation code."
          unit-name unit-name))

(defun specflow-compose--instructions-new-feature (unit-name affects-parent)
  "Return instructions for adding feature to UNIT-NAME.
AFFECTS-PARENT is yes/no/unsure."
  (let ((parent-note
         (cond
          ((string= (downcase affects-parent) "yes")
           "This affects parent architecture. Start by updating parent specs first.")
          ((string= (downcase affects-parent) "no")
           "This is contained within the child unit. Work only in the child unit.")
          (t
           "Determine if this affects parent architecture. If unsure, review parent specs first."))))
    (format "You are in Plan phase. Add a new feature to %s:

%s

Steps:
1. Review the relevant specs
2. Design the feature within scope
3. Update .specflow/units/%s/spec.org with new requirements
4. Update .specflow/units/%s/todo.org with implementation tasks

Phase rules: Do NOT write implementation code. Planning and spec updates only."
            unit-name parent-note unit-name unit-name)))

(defun specflow-compose--instructions-refactor (unit-name)
  "Return instructions for refactoring UNIT-NAME."
  (format "You are in Plan phase. Plan a refactor for %s:
1. Review the current spec and implementation
2. Document the refactoring approach
3. Identify files that will change
4. Ensure behavior is preserved (per spec)

Phase rules: Do NOT make code changes yet. Planning only."
          unit-name))

(defun specflow-compose--artifact-preservation-section (unit-name)
  "Return artifact preservation instructions for UNIT-NAME."
  (format "### Artifact Preservation

Save planning discussions and design decisions to:
  units/%s/temp-planning-artifacts.org

This preserves context across sessions. Delete after official docs are finalized."
          unit-name))

(defun specflow-compose--next-phase (phase)
  "Return the phase after PHASE, or nil if Document."
  (pcase (downcase phase)
    ("plan" "Specify")
    ("specify" "Scaffold")
    ("scaffold" "Implement")
    ("implement" "Validate")
    ("validate" "Document")
    (_ nil)))

(defun specflow-compose--phase-completion-section (phase unit-name)
  "Return phase completion checklist for PHASE and UNIT-NAME."
  (let ((next-phase (specflow-compose--next-phase phase)))
    (format "### Phase Completion Checklist

When this phase is complete:

1. Update .specflow/todo.org:
   - Mark \"** NEXT %s: %s phase\" as DONE with summary
   - Create \"** NEXT %s: %s phase\"%s

2. Update control plane (.specflow/specflow.org):
   - Change SPEC_FLOW_PHASE to %s

3. Commit: \"%s: complete %s phase\""
            unit-name phase
            unit-name (or next-phase "")
            (if next-phase "" " (unit complete)")
            (or next-phase "Document")
            unit-name phase)))

(defun specflow-compose--generate-prompt (task-type answers)
  "Generate prompt for TASK-TYPE with ANSWERS."
  (let* ((state (specflow-org-store-read-project-state))
         (phase (plist-get state :phase))
         (active-unit (plist-get state :active-unit))
         (parent-chain (condition-case nil
                           (specflow-org-store-validate-parent-chain active-unit)
                         (error nil)))
         ;; Extract key fields
         (unit-name (or (cdr (assoc "Unit Name" answers))
                        (cdr (assoc "Which Unit" answers))
                        active-unit))
         (parent (or (cdr (assoc "Parent" answers)) "core"))
         (affects-parent (or (cdr (assoc "Affects Parent Architecture? (yes/no/unsure)" answers))
                             "unsure"))
         ;; Get context files and instructions based on task type
         (context-files
          (pcase task-type
            ('new-unit (specflow-compose--context-files-new-unit))
            ('edit-spec (specflow-compose--context-files-edit-spec unit-name))
            ('new-feature (specflow-compose--context-files-new-feature unit-name affects-parent))
            ('refactor (specflow-compose--context-files-refactor unit-name))
            (_ (list (cons ".specflow/specflow.org" "control plane")))))
         (instructions
          (pcase task-type
            ('new-unit (specflow-compose--instructions-new-unit unit-name parent))
            ('edit-spec (specflow-compose--instructions-edit-spec unit-name))
            ('new-feature (specflow-compose--instructions-new-feature unit-name affects-parent))
            ('refactor (specflow-compose--instructions-refactor unit-name))
            (_ "Follow phase-specific rules.")))
         (task-desc
          (pcase task-type
            ('new-unit (format "Create new unit \"%s\"" unit-name))
            ('edit-spec (format "Edit specification for \"%s\"" unit-name))
            ('new-feature (format "Add new feature to \"%s\"" unit-name))
            ('refactor (format "Refactor \"%s\"" unit-name))
            (_ "SpecFlow task"))))
    ;; Build prompt
    (with-temp-buffer
      (insert (format "## Task: %s\n\n" task-desc))
      (insert "### Current State\n")
      (insert (format "- Active unit: %s\n" active-unit))
      (insert (format "- Phase: %s\n" phase))
      (insert (format "- Parent chain: %s\n\n"
                      (if parent-chain
                          (mapconcat #'identity parent-chain " → ")
                        "none")))
      (insert "### Context Files\n")
      (insert (specflow-compose--format-context-files context-files))
      (insert "\n### Requirements\n")
      (insert (specflow-compose--format-requirements answers))
      (insert "\n### Instructions\n")
      (insert instructions)
      (insert "\n\n")
      (insert (specflow-compose--artifact-preservation-section
               (if (eq task-type 'new-unit) unit-name active-unit)))
      (insert "\n\n")
      (insert (specflow-compose--phase-completion-section
               phase
               (if (eq task-type 'new-unit) unit-name active-unit)))
      (insert "\n")
      (buffer-string))))

;;;; Interactive Commands

(defun specflow-compose--generate ()
  "Generate prompt from current compose buffer."
  (interactive)
  (let* ((task-type specflow-compose--task-type)
         (answers (specflow-compose--extract-answers))
         (prompt (specflow-compose--generate-prompt task-type answers)))
    ;; Copy to kill-ring
    (kill-new prompt)
    ;; Display in buffer
    (let ((preview-buf (get-buffer-create "*SpecFlow Compose Output*")))
      (with-current-buffer preview-buf
        (erase-buffer)
        (insert prompt)
        (goto-char (point-min))
        (display-buffer preview-buf)))
    ;; Kill compose buffer
    (kill-buffer (current-buffer))
    (message "Prompt generated and copied to kill-ring (%d chars)" (length prompt))))

(defun specflow-compose--cancel ()
  "Cancel compose and kill buffer."
  (interactive)
  (kill-buffer (current-buffer))
  (message "Compose cancelled"))

(defun specflow-compose ()
  "Dispatcher for compose commands."
  (interactive)
  (unless (specflow-compose--check-plan-phase)
    (user-error "Compose requires Plan phase"))
  (let ((choice (read-char-choice
                 "What do you want to do? [1] New unit [2] Edit spec [3] New feature [4] Refactor: "
                 '(?1 ?2 ?3 ?4))))
    (pcase choice
      (?1 (specflow-compose-new-unit))
      (?2 (specflow-compose-edit-spec))
      (?3 (specflow-compose-new-feature))
      (?4 (specflow-compose-refactor)))))

(defun specflow-compose-new-unit ()
  "Compose prompt for creating a new unit."
  (interactive)
  (unless (specflow-compose--check-plan-phase)
    (user-error "Compose requires Plan phase"))
  (specflow-compose--create-buffer
   'new-unit
   "New Unit"
   (specflow-compose--template-new-unit)))

(defun specflow-compose-edit-spec ()
  "Compose prompt for editing a specification."
  (interactive)
  (unless (specflow-compose--check-plan-phase)
    (user-error "Compose requires Plan phase"))
  (let* ((state (specflow-org-store-read-project-state))
         (active-unit (plist-get state :active-unit)))
    (specflow-compose--create-buffer
     'edit-spec
     "Edit Specification"
     (specflow-compose--template-edit-spec)
     active-unit)))

(defun specflow-compose-new-feature ()
  "Compose prompt for adding a new feature."
  (interactive)
  (unless (specflow-compose--check-plan-phase)
    (user-error "Compose requires Plan phase"))
  (let* ((state (specflow-org-store-read-project-state))
         (active-unit (plist-get state :active-unit)))
    (specflow-compose--create-buffer
     'new-feature
     "New Feature"
     (specflow-compose--template-new-feature)
     active-unit)))

(defun specflow-compose-refactor ()
  "Compose prompt for refactoring."
  (interactive)
  (unless (specflow-compose--check-plan-phase)
    (user-error "Compose requires Plan phase"))
  (let* ((state (specflow-org-store-read-project-state))
         (active-unit (plist-get state :active-unit)))
    (specflow-compose--create-buffer
     'refactor
     "Refactor"
     (specflow-compose--template-refactor)
     active-unit)))

(provide 'specflow-compose)
;;; specflow-compose.el ends here
