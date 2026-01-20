;;; specflow.el --- Spec-driven, phase-gated development workflow -*- lexical-binding: t; -*-

;; Copyright (C) 2025 TRM LLC
;; Author: TRM LLC
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: tools, org
;; URL: https://github.com/tedmellors/specflow

;;; Commentary:

;; SpecFlow is an Org-native workflow and set of Emacs tools for
;; spec-driven, phase-gated, AI-assisted software development.
;;
;; This file is a facade that loads all SpecFlow modules.
;; Each module lives in its own unit directory under units/<module>/src/.
;;
;; Modules:
;; - specflow-org-store: Control plane discovery and access
;; - specflow-bundle: Context bundling for AI assistants
;; - specflow-hydrate: AI conversation framing
;; - specflow-compose: Task-specific prompt generation
;; - specflow-initiate: Project bootstrapping

;;; Code:

;; Set up load-path for unit modules relative to this file's location
(let ((specflow-root (file-name-directory
                      (directory-file-name
                       (file-name-directory
                        (or load-file-name buffer-file-name))))))
  (dolist (unit '("org-store" "bundle" "hydrate" "compose" "initiate" "rules"))
    (add-to-list 'load-path
                 (expand-file-name (format "units/%s/src" unit) specflow-root))))

(require 'specflow-org-store)
(require 'specflow-bundle)
(require 'specflow-hydrate)
(require 'specflow-compose)
(require 'specflow-initiate)
(require 'specflow-rules)

(provide 'specflow)
;;; specflow.el ends here
