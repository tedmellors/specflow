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
;; SpecFlow runs from a control directory that sits OUTSIDE the repository.
;; The .specflow/ control plane and generated CLAUDE.md live at the control
;; directory root, while the actual repository lives one level down in a
;; REPO/ sub-directory (configurable via `specflow-initiate-repo-dirname').
;; This keeps SpecFlow artifacts out of the repository and lets you drive
;; development from the outside, including for repositories that already exist
;; (place the existing repo at REPO/ before running initiate).
;;
;; Structure created:
;;   control-dir/              - Where you run specflow-initiate (NOT the repo)
;;     .specflow/
;;       specflow.org          - Control plane
;;       todo.org              - Root unit tasks (the master TODO)
;;       units/
;;         root/
;;           spec.org          - Root unit specification (parent unit)
;;     CLAUDE.md               - Generated from the installed rules.org
;;     REPO/                   - The repository (git root); existing or new
;;       src/                  - Source code directory
;;       tests/                - Test directory
;;
;; rules.org is treated as source code in the SpecFlow installation; it is
;; never copied into the project.  CLAUDE.md is generated from it directly.

;;; Code:

(defcustom specflow-initiate-repo-dirname "REPO"
  "Name of the repository sub-directory created by `specflow-initiate'.
SpecFlow's control plane (.specflow/) and the generated CLAUDE.md stay at the
control-directory root, while source and tests live inside this sub-directory.
This keeps SpecFlow artifacts outside the repository itself.  If a directory
with this name already exists (e.g. an existing repository placed there),
`specflow-initiate' leaves its contents untouched instead of scaffolding
src/ and tests/."
  :type 'string
  :group 'specflow)

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

** root
   :PROPERTIES:
   :SPEC: .specflow/units/root/spec.org
   :TODO: .specflow/todo.org
   :END:

The root unit is the project-level parent unit. It owns the project
specification, architecture, and cross-cutting constraints. Its task list is
the master TODO at .specflow/todo.org. It has no source directory.
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

* Complete

(Move completed tasks here)
" project-name project-name))

(defun specflow-initiate--root-spec-template ()
  "Return root unit spec.org template."
  "#+TITLE: root – Specification
#+STARTUP: overview

* Purpose

The root unit is the parent unit for this project.
It owns project-level documentation that guides all other work.
This unit has no source code - its deliverables are this spec and the
master TODO at .specflow/todo.org.

* Scope

**In scope**
- spec.org: Project purpose, architecture, constraints, success criteria

**Out of scope**
- Implementation code (belongs in implementation units)
- Unit-specific specifications (belong in each unit's spec.org)
")

(defun specflow-initiate ()
  "Initialize a new SpecFlow project in the current directory.
Creates scaffolding in .specflow/ directory with control plane, todos,
rules, and a root unit for project documentation."
  (interactive)
  ;; Check preconditions
  (let ((error-msg (specflow-initiate--check-preconditions)))
    (when error-msg
      (user-error "%s" error-msg)))
  ;; Derive project name
  (let ((project-name (specflow-initiate--derive-project-name)))
    ;; Create directories. The control plane (.specflow/) stays at the
    ;; control-directory root; source/tests live inside the REPO/ sub-directory
    ;; so SpecFlow artifacts remain outside the repository itself.
    (make-directory (expand-file-name ".specflow/units/root") t)
    ;; Scaffold src/ and tests/ inside the repo dir, but leave an existing
    ;; repository (already placed at REPO/) untouched.
    (let ((repo-dir (expand-file-name specflow-initiate-repo-dirname)))
      (unless (file-directory-p repo-dir)
        (make-directory (expand-file-name "src" repo-dir) t)
        (make-directory (expand-file-name "tests" repo-dir) t)))
    ;; Write .specflow/specflow.org (control plane)
    (write-region (specflow-initiate--control-plane-template project-name)
                  nil (expand-file-name ".specflow/specflow.org"))
    ;; Write .specflow/todo.org (root tasks)
    (write-region (specflow-initiate--todo-template project-name)
                  nil (expand-file-name ".specflow/todo.org"))
    ;; Note: rules.org is NOT copied into the project. It is treated as source
    ;; code in the SpecFlow installation and used directly to generate CLAUDE.md.
    ;; Write .specflow/units/root/spec.org
    ;; The root unit's task list is the master TODO at .specflow/todo.org,
    ;; so no separate unit todo.org is created here.
    (write-region (specflow-initiate--root-spec-template)
                  nil (expand-file-name ".specflow/units/root/spec.org"))
    ;; Generate CLAUDE.md via specflow-hydrate-rules if available, then report.
    (let* ((repo specflow-initiate-repo-dirname)
           (claude-status
            (if (fboundp 'specflow-hydrate-rules)
                (condition-case err
                    (progn (specflow-hydrate-rules) 'ok)
                  (error (cons 'failed (error-message-string err))))
              'unavailable)))
      (message "SpecFlow project \"%s\" initialized%s.

Created:
  .specflow/specflow.org       (control plane)
  .specflow/todo.org           (root tasks)
  .specflow/units/root/        (root unit)
  %s/src/                      (source directory)
  %s/tests/                    (test directory)%s

%sNext steps:
  1. Review .specflow/specflow.org
  2. Start with root: Plan phase
  3. Draft spec.org"
               project-name
               (pcase claude-status
                 ('ok "")
                 ('unavailable " (CLAUDE.md not generated)")
                 (_ (format " (CLAUDE.md not generated: %s)" (cdr claude-status))))
               repo repo
               (if (eq claude-status 'ok)
                   "\n  CLAUDE.md                    (generated from rules.org)"
                 "")
               (if (eq claude-status 'ok)
                   ""
                 "Run M-x specflow-hydrate-rules to generate CLAUDE.md.\n\n")))))

(provide 'specflow-initiate)
;;; specflow-initiate.el ends here
