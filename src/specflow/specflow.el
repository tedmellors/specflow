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
;; All modules live in src/specflow/ alongside this file.
;;
;; Modules:
;; - specflow-org-store: Control plane discovery and access
;; - specflow-bundle: Context bundling for AI assistants
;; - specflow-hydrate: AI conversation framing
;; - specflow-compose: Task-specific prompt generation
;; - specflow-initiate: Project bootstrapping
;; - specflow-rules: Operational rules management

;;; Code:

(require 'specflow-org-store)
(require 'specflow-bundle)
(require 'specflow-hydrate)
(require 'specflow-compose)
(require 'specflow-initiate)
(require 'specflow-rules)

(provide 'specflow)
;;; specflow.el ends here
