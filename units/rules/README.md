# specflow-rules

Operational rules management for SpecFlow.

## Overview

The rules unit provides structured access to SpecFlow operational rules. Rules are stored in `rules.org` using org-mode format with properties for filtering by phase, priority, and tags.

## Installation

```elisp
(add-to-list 'load-path "/path/to/specflow/units/rules/src")
(require 'specflow-rules)
```

## Usage

### Load all rules

```elisp
(specflow-rules-load "/path/to/rules.org")
;; Returns list of plists:
;; ((:id "scope" :title "Scope" :priority "mandatory" :phase "all" :tags ("philosophy" "overview") :content "...")
;;  (:id "control-plane-authority" :title "Control Plane Authority" ...))
```

### Filter by phase

```elisp
;; Get rules for "implement" phase (includes "all" phase rules)
(specflow-rules-for-phase "implement" "/path/to/rules.org")
;; => 16 rules
```

### Filter by priority

```elisp
;; Get mandatory rules only
(specflow-rules-mandatory "/path/to/rules.org")
;; => 14 rules
```

### Filter by tag

```elisp
;; Get rules tagged with "phase"
(specflow-rules-by-tag "phase" "/path/to/rules.org")
;; => (Phase Transition Protocol, Phase Enforcement)
```

### Format for AI context

```elisp
(let ((rules (specflow-rules-for-phase "plan" "/path/to/rules.org")))
  (specflow-rules-format-for-context rules))
;; Returns:
;; ## Scope [mandatory] [all]
;;
;; <content>
;;
;; ---
;;
;; ## Control Plane Authority [mandatory] [all]
;; ...
```

## Rule Format

Rules are defined in `rules.org` as level-1 headings with properties:

```org
* Rule Title
  :PROPERTIES:
  :RULE_ID: rule-id
  :PRIORITY: mandatory
  :PHASE: all
  :TAGS: tag1 tag2
  :END:

  Rule content goes here.
```

### Required Properties

| Property | Values | Description |
|----------|--------|-------------|
| RULE_ID | string | Unique identifier |
| PRIORITY | mandatory, recommended, optional | Rule importance |
| PHASE | all, plan, specify, scaffold, implement, validate, document | When rule applies |

### Optional Properties

| Property | Values | Description |
|----------|--------|-------------|
| TAGS | space-separated | Searchable tags |

## API Reference

| Function | Description |
|----------|-------------|
| `specflow-rules-load` | Load all rules from file |
| `specflow-rules-all` | Alias for load (convenience) |
| `specflow-rules-for-phase` | Filter by phase (includes "all") |
| `specflow-rules-mandatory` | Filter by mandatory priority |
| `specflow-rules-by-tag` | Filter by tag |
| `specflow-rules-format-for-context` | Format rules for AI context |

## Error Handling

| Condition | Error |
|-----------|-------|
| File not found | `specflow-rules-file-not-found` |
| Missing required property | `specflow-rules-malformed` |

## Tests

Run tests with:

```bash
emacs --batch \
  -L units/rules/src \
  -L units/rules/tests \
  -l specflow-rules.el \
  -l test-specflow-rules.el \
  -f ert-run-tests-batch-and-exit
```

25 tests covering discovery, parsing, filtering, and formatting.
