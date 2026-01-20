;;; specflow-initiate.el --- SpecFlow project bootstrapping -*- lexical-binding: t; -*-

;; Author: SpecFlow
;; Version: 1.0.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: tools, convenience
;; URL: https://github.com/specflow/specflow

;;; Commentary:

;; This module provides project bootstrapping for SpecFlow.
;; It creates the minimal file structure needed to begin
;; SpecFlow-driven development in a new project directory.

;;; Code:

(defun specflow-initiate--derive-project-name ()
  "Derive project name from current directory.
Converts to lowercase, replaces spaces with hyphens."
  (let ((dir-name (file-name-nondirectory
                   (directory-file-name default-directory))))
    (downcase (replace-regexp-in-string " " "-" dir-name))))

(defun specflow-initiate--check-preconditions ()
  "Check if directory is suitable for initialization.
Returns nil if OK, or an error message string."
  (cond
   ((file-exists-p (expand-file-name "docs/specflow.org"))
    "SpecFlow project already exists (docs/specflow.org found)")
   ((file-exists-p (expand-file-name ".specflow"))
    "SpecFlow project already exists (.specflow marker found)")
   (t nil)))

(defun specflow-initiate--control-plane-template (project-name)
  "Return control plane template for PROJECT-NAME."
  (format "#+TITLE: %s – Control Plane
#+STARTUP: overview
#+SEQ_TODO: TODO NEXT WAITING | DONE

* Project
  :PROPERTIES:
  :SPEC_FLOW_PHASE: Plan
  :SPEC_FLOW_ACTIVE_UNIT: core
  :END:

This is the SpecFlow control plane for %s.

* Units

** core
   :PROPERTIES:
   :DIR: src/
   :SPEC: units/core/spec.org
   :TODO: units/core/todo.org
   :RULES: units/core/CLAUDE.md
   :END:

The core unit defines project-level architecture and constraints.
" project-name project-name))

(defun specflow-initiate--claude-md-template (project-name)
  "Return root CLAUDE.md template for PROJECT-NAME."
  (format "# %s – AI Assistant Rules

## SpecFlow Project

This repository uses SpecFlow: a spec-driven, phase-gated workflow
for AI-assisted software development.

## Control Plane

The current operational state is defined in:
- `docs/specflow.org` (control plane)

Before starting any work:
1. Read the control plane
2. Identify the active unit and phase
3. Follow the phase rules

## Phase Enforcement

Phases: Plan → Specify → Scaffold → Implement → Validate → Document

- **Plan**: Design only. No code, no specs.
- **Specify**: Edit spec.org only.
- **Scaffold**: Write CLAUDE.md and todo.org only.
- **Implement**: Write code and tests per spec.
- **Validate**: Verify behavior. No changes.
- **Document**: Write documentation only.

## Task Discovery

The canonical NEXT task is in `todo.org` at the repo root.

## Stop Conditions

STOP and ask for confirmation if:
- Action would violate the current phase
- Interface change is required
- Scope creep is detected
" project-name))

(defun specflow-initiate--todo-template (project-name)
  "Return root todo.org template for PROJECT-NAME."
  (format "#+TITLE: %s – Master TODO
#+STARTUP: overview
#+SEQ_TODO: TODO NEXT WAITING | DONE

* About

This is the canonical task driver for %s.
Only ONE task is marked NEXT at a time.

* Active

** NEXT core: Plan phase
   Define the project architecture and initial unit structure.

   - Draft overview.org (purpose, constraints, success criteria)
   - Draft architecture.org (components, data flow, dependencies)
   - Identify first implementation unit

* Backlog

(Add future tasks here)

* Completed

(Move completed tasks here)
" project-name project-name))

(defun specflow-initiate ()
  "Initialize a new SpecFlow project in the current directory.
Creates minimal scaffolding: control plane, root CLAUDE.md, root todo.org,
.specflow marker, and units/core/ directory."
  (interactive)
  ;; Check preconditions
  (let ((error-msg (specflow-initiate--check-preconditions)))
    (when error-msg
      (user-error "%s" error-msg)))
  ;; Derive project name
  (let ((project-name (specflow-initiate--derive-project-name)))
    ;; Create directories
    (make-directory (expand-file-name "docs") t)
    (make-directory (expand-file-name "units/core") t)
    ;; Write control plane
    (write-region (specflow-initiate--control-plane-template project-name)
                  nil (expand-file-name "docs/specflow.org"))
    ;; Write root CLAUDE.md
    (write-region (specflow-initiate--claude-md-template project-name)
                  nil (expand-file-name "CLAUDE.md"))
    ;; Write root todo.org
    (write-region (specflow-initiate--todo-template project-name)
                  nil (expand-file-name "todo.org"))
    ;; Create .specflow marker
    (write-region "" nil (expand-file-name ".specflow"))
    ;; Success message
    (message "SpecFlow project \"%s\" initialized.

Created:
  docs/specflow.org  (control plane)
  CLAUDE.md          (AI assistant rules)
  todo.org           (root tasks)
  .specflow          (project marker)
  units/core/        (core unit directory)

Next steps:
  1. Review docs/specflow.org
  2. Start with core: Plan phase
  3. Draft overview.org and architecture.org" project-name)))

(provide 'specflow-initiate)
;;; specflow-initiate.el ends here
