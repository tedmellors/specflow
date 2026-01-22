;;; specflow-initiate.el --- SpecFlow project bootstrapping -*- lexical-binding: t; -*-

;; Author: SpecFlow
;; Version: 2.0.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: tools, convenience
;; URL: https://github.com/specflow/specflow

;;; Commentary:

;; This module provides project bootstrapping for SpecFlow.
;; It creates the minimal file structure needed to begin
;; SpecFlow-driven development in a new project directory.
;;
;; Structure created:
;;   .specflow/
;;     specflow.org          - Control plane
;;     todo.org              - Root tasks
;;     rules.org             - Full rules (copied from specflow installation)
;;     units/
;;       docs/
;;         spec.org          - Docs unit specification
;;         todo.org          - Docs unit tasks
;;   src/<project>/          - Base for future unit source
;;   tests/                  - Test directory
;;   CLAUDE.md               - Generated from .specflow/rules.org

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
   ((file-exists-p (expand-file-name ".specflow/specflow.org"))
    "SpecFlow project already exists (.specflow/specflow.org found)")
   (t nil)))

(defun specflow-initiate--control-plane-template (project-name)
  "Return control plane template for PROJECT-NAME."
  (format "#+TITLE: %s – Control Plane
#+STARTUP: overview
#+SEQ_TODO: TODO NEXT WAITING | DONE

* Project
  :PROPERTIES:
  :SPEC_FLOW_PHASE: Plan
  :SPEC_FLOW_ACTIVE_UNIT: root
  :END:

This is the SpecFlow control plane for %s.

* Units

** docs
   :PROPERTIES:
   :SPEC: .specflow/units/docs/spec.org
   :TODO: .specflow/units/docs/todo.org
   :END:

The docs unit defines project-level documentation: overview, architecture,
and cross-cutting constraints. It has no source directory.
" project-name project-name))

(defun specflow-initiate--todo-template (project-name)
  "Return root todo.org template for PROJECT-NAME."
  (format "#+TITLE: %s – Master TODO
#+STARTUP: overview
#+SEQ_TODO: TODO NEXT WAITING | DONE

* About

This is the canonical task driver for %s.
Only ONE task is marked NEXT at a time.

* Active

** NEXT root: Plan phase
   Define the project scope and initial structure.

   - Clarify project purpose and goals
   - Identify key constraints and success criteria
   - Determine initial unit structure

* Backlog

(Add future tasks here)

* Completed

(Move completed tasks here)
" project-name project-name))

(defun specflow-initiate--find-rules-org ()
  "Find the full rules.org in the specflow installation directory.
Returns the path to rules.org, or nil if not found."
  (let* ((lib-file (locate-library "specflow-initiate"))
         (install-dir (and lib-file (file-name-directory lib-file)))
         (rules-path (and install-dir (expand-file-name "rules.org" install-dir))))
    (when (and rules-path (file-exists-p rules-path))
      rules-path)))

(defun specflow-initiate--docs-spec-template ()
  "Return docs unit spec.org template."
  "#+TITLE: docs – Specification
#+STARTUP: overview

* Purpose

The docs unit produces project-level documentation that guides all other work.
This unit has no source code - its deliverables are Org files.

* Scope

**In scope**
- overview.org: Project purpose, goals, success criteria, non-goals
- architecture.org: System structure, components, data flow, dependencies

**Out of scope**
- Implementation code (belongs in implementation units)
- Unit-specific specifications (belong in each unit's spec.org)

* Deliverables

| File | Purpose |
|------|---------+
| overview.org | What the project is, why it exists, what success looks like |
| architecture.org | How the system is structured, component relationships |
")

(defun specflow-initiate--docs-todo-template ()
  "Return docs unit todo.org template."
  "#+TITLE: docs – Unit TODO
#+STARTUP: overview
#+SEQ_TODO: TODO NEXT WAITING | DONE

* About

Tasks for the docs unit. Complete these before starting implementation units.

* Active

** NEXT Draft overview.org
   Define what this project is and why it exists.

   - Purpose and goals
   - Target users
   - Success criteria
   - Non-goals and scope boundaries

* Backlog

** TODO Draft architecture.org
   Define how the system will be structured.

   - Components and their responsibilities
   - Data flow
   - Dependencies
   - Implementation order

* Completed
")

(defun specflow-initiate ()
  "Initialize a new SpecFlow project in the current directory.
Creates scaffolding in .specflow/ directory with control plane, todos,
rules, and a docs unit for project documentation."
  (interactive)
  ;; Check preconditions
  (let ((error-msg (specflow-initiate--check-preconditions)))
    (when error-msg
      (user-error "%s" error-msg)))
  ;; Derive project name
  (let ((project-name (specflow-initiate--derive-project-name)))
    ;; Create directories
    (make-directory (expand-file-name ".specflow/units/docs") t)
    (make-directory (expand-file-name (format "src/%s" project-name)) t)
    (make-directory (expand-file-name "tests") t)
    ;; Write .specflow/specflow.org (control plane)
    (write-region (specflow-initiate--control-plane-template project-name)
                  nil (expand-file-name ".specflow/specflow.org"))
    ;; Write .specflow/todo.org (root tasks)
    (write-region (specflow-initiate--todo-template project-name)
                  nil (expand-file-name ".specflow/todo.org"))
    ;; Copy full rules.org from specflow installation
    (let ((source-rules (specflow-initiate--find-rules-org)))
      (if source-rules
          (copy-file source-rules (expand-file-name ".specflow/rules.org"))
        (user-error "Cannot find rules.org in specflow installation")))
    ;; Write .specflow/units/docs/spec.org
    (write-region (specflow-initiate--docs-spec-template)
                  nil (expand-file-name ".specflow/units/docs/spec.org"))
    ;; Write .specflow/units/docs/todo.org
    (write-region (specflow-initiate--docs-todo-template)
                  nil (expand-file-name ".specflow/units/docs/todo.org"))
    ;; Generate CLAUDE.md via specflow-hydrate-rules if available
    (if (fboundp 'specflow-hydrate-rules)
        (condition-case err
            (progn
              (specflow-hydrate-rules)
              (message "SpecFlow project \"%s\" initialized.

Created:
  .specflow/specflow.org       (control plane)
  .specflow/todo.org           (root tasks)
  .specflow/rules.org          (operational rules)
  .specflow/units/docs/        (docs unit)
  src/%s/                      (source base)
  tests/                       (test directory)
  CLAUDE.md                    (generated from rules.org)

Next steps:
  1. Review .specflow/specflow.org
  2. Start with root: Plan phase
  3. Draft overview.org and architecture.org" project-name project-name))
          (error
           (message "SpecFlow project \"%s\" initialized (CLAUDE.md not generated: %s).

Created:
  .specflow/specflow.org       (control plane)
  .specflow/todo.org           (root tasks)
  .specflow/rules.org          (operational rules)
  .specflow/units/docs/        (docs unit)
  src/%s/                      (source base)
  tests/                       (test directory)

Run M-x specflow-hydrate-rules to generate CLAUDE.md.

Next steps:
  1. Review .specflow/specflow.org
  2. Start with root: Plan phase
  3. Draft overview.org and architecture.org" project-name (error-message-string err) project-name)))
      ;; specflow-hydrate-rules not available
      (message "SpecFlow project \"%s\" initialized (CLAUDE.md not generated).

Created:
  .specflow/specflow.org       (control plane)
  .specflow/todo.org           (root tasks)
  .specflow/rules.org          (operational rules)
  .specflow/units/docs/        (docs unit)
  src/%s/                      (source base)
  tests/                       (test directory)

Run M-x specflow-hydrate-rules to generate CLAUDE.md.

Next steps:
  1. Review .specflow/specflow.org
  2. Start with root: Plan phase
  3. Draft overview.org and architecture.org" project-name project-name))))

(provide 'specflow-initiate)
;;; specflow-initiate.el ends here
