;;; specflow-rules.el --- SpecFlow operational rules management -*- lexical-binding: t; -*-

;; Copyright (C) 2025 TRM LLC
;; Author: TRM LLC
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: tools, org

;;; Commentary:

;; This module provides operational rules discovery, parsing, filtering, and
;; formatting for the SpecFlow workflow system.  It reads rules from a
;; structured rules.org file and provides query functions for context-aware
;; rule loading.

;;; Code:

;;;; Requirements

(require 'cl-lib)

;;;; Error Conditions

;; Define base error if not already defined (for standalone use)
(unless (get 'specflow-error 'error-conditions)
  (define-error 'specflow-error "SpecFlow error"))

(define-error 'specflow-rules-error "SpecFlow rules error" 'specflow-error)
(define-error 'specflow-rules-file-not-found
  "Rules file not found" 'specflow-rules-error)
(define-error 'specflow-rules-malformed
  "Rules file malformed" 'specflow-rules-error)

;;;; Constants

(defconst specflow-rules-filename "rules.org"
  "Name of the rules file at project root.")

(defconst specflow-rules-valid-priorities '("mandatory" "recommended" "optional")
  "Valid values for PRIORITY property.")

(defconst specflow-rules-valid-phases
  '("all" "plan" "specify" "scaffold" "implement" "validate" "document")
  "Valid values for PHASE property.")

;;;; Discovery

(defun specflow-rules--project-root-p (dir)
  "Return non-nil if DIR is a project root.
A project root contains .git, .projectile, or .specflow-root."
  (or (file-exists-p (expand-file-name ".git" dir))
      (file-exists-p (expand-file-name ".projectile" dir))
      (file-exists-p (expand-file-name ".specflow-root" dir))))

(defun specflow-rules--filesystem-root-p (dir)
  "Return non-nil if DIR is the filesystem root."
  (string= dir (file-name-directory (directory-file-name dir))))

(defun specflow-rules-find-file (&optional start-dir)
  "Find the SpecFlow rules file.

Discovery algorithm:
1. Start from START-DIR (defaults to `default-directory').
2. Search upward for `specflow-rules-filename' (rules.org).
3. Stop if:
   - File found: return absolute path
   - Reached filesystem root: stop searching
   - Reached project root without finding file: stop searching
4. If not found, signal `specflow-rules-file-not-found'.

Returns absolute path to rules file (string)."
  (let* ((dir (expand-file-name (or start-dir default-directory)))
         (found nil))
    ;; Search upward
    (while (and (not found)
                (not (specflow-rules--filesystem-root-p dir)))
      (let ((candidate (expand-file-name specflow-rules-filename dir)))
        (if (file-exists-p candidate)
            (setq found candidate)
          ;; Check if we hit project root without finding file
          (if (specflow-rules--project-root-p dir)
              ;; Stop searching - we're at project root but file not found
              (setq dir "/")  ; Force exit from loop
            ;; Move up one directory
            (setq dir (file-name-directory (directory-file-name dir)))))))
    (if found
        found
      (signal 'specflow-rules-file-not-found
              (list (format "rules.org not found searching from %s"
                            (or start-dir default-directory)))))))

;;;; Parsing

(defun specflow-rules--get-heading-content ()
  "Get content of current heading, excluding property drawer.
Assumes point is at the heading line.
Returns the text content as a string, including any subsections."
  (save-excursion
    (let ((start nil)
          (end nil))
      ;; Move past the heading line
      (forward-line 1)
      ;; Skip property drawer if present
      (when (looking-at "^[ \t]*:PROPERTIES:")
        (re-search-forward "^[ \t]*:END:" nil t)
        (forward-line 1))
      (setq start (point))
      ;; Find end (next level-1 heading or end of buffer)
      ;; Only stop at ^* (single asterisk) to include subsections
      (if (re-search-forward "^\\* " nil t)
          (progn
            (beginning-of-line)
            (setq end (point)))
        (setq end (point-max)))
      ;; Get content, trim whitespace
      (string-trim (buffer-substring-no-properties start end)))))

(defun specflow-rules--parse-tags (tags-string)
  "Parse TAGS-STRING (space-separated) into a list of strings.
Returns nil if TAGS-STRING is nil or empty."
  (when (and tags-string (not (string-empty-p tags-string)))
    (split-string tags-string "[ \t]+" t)))

(defun specflow-rules--get-property (name)
  "Get property NAME from current heading's property drawer.
Assumes point is at or before the property drawer.
Returns nil if property not found."
  (save-excursion
    (let ((case-fold-search t)
          (bound (save-excursion
                   (forward-line 1)
                   (if (re-search-forward "^\\*+ " nil t)
                       (point)
                     (point-max)))))
      (when (re-search-forward
             (format "^[ \t]*:%s:[ \t]*\\(.+\\)$" (regexp-quote name))
             bound t)
        (string-trim (match-string 1))))))

(defun specflow-rules--parse-rule-at-point ()
  "Parse rule at point into a plist.
Assumes point is at a heading line.
Returns plist with :id, :title, :priority, :phase, :tags, :content.
Signals `specflow-rules-malformed' if required properties missing."
  (save-excursion
    (beginning-of-line)
    (when (looking-at "^\\*+ \\(.+\\)$")
      (let* ((title (string-trim (match-string 1)))
             (rule-id (specflow-rules--get-property "RULE_ID"))
             (priority (specflow-rules--get-property "PRIORITY"))
             (phase (specflow-rules--get-property "PHASE"))
             (tags-str (specflow-rules--get-property "TAGS"))
             (tags (specflow-rules--parse-tags tags-str))
             (content (specflow-rules--get-heading-content)))
        ;; Validate required properties
        (unless rule-id
          (signal 'specflow-rules-malformed
                  (list (format "Rule '%s' missing required property RULE_ID" title))))
        (unless priority
          (signal 'specflow-rules-malformed
                  (list (format "Rule '%s' missing required property PRIORITY" title))))
        (unless phase
          (signal 'specflow-rules-malformed
                  (list (format "Rule '%s' missing required property PHASE" title))))
        ;; Return plist
        (list :id rule-id
              :title title
              :priority (downcase priority)
              :phase (downcase phase)
              :tags tags
              :content content)))))

(defun specflow-rules-load (&optional rules-path)
  "Load all rules from rules.org.

RULES-PATH is optional path to rules file (defaults to discovery).

Returns list of rule plists in document order, each with:
- :id - unique identifier (string)
- :title - heading text (string)
- :priority - mandatory/recommended/optional (string, lowercase)
- :phase - all/plan/specify/scaffold/implement/validate/document (string, lowercase)
- :tags - list of tag strings (may be nil)
- :content - rule body text (string)

Signals:
- `specflow-rules-file-not-found' if rules.org not found
- `specflow-rules-malformed' if rule missing required properties"
  (let* ((path (or rules-path (specflow-rules-find-file)))
         (rules nil))
    (with-temp-buffer
      (insert-file-contents path)
      (goto-char (point-min))
      ;; Find all level-1 headings (rules are top-level)
      (while (re-search-forward "^\\* " nil t)
        (beginning-of-line)
        (let ((rule (specflow-rules--parse-rule-at-point)))
          (when rule
            (push rule rules)))
        (forward-line 1)))
    (nreverse rules)))

;;;; Filtering

(defun specflow-rules-for-phase (phase &optional rules-path)
  "Get rules applicable to PHASE.

PHASE is a string: plan, specify, scaffold, implement, validate, document.
RULES-PATH is optional path to rules file.

Returns list of rule plists where :phase matches PHASE or is \"all\".
Case-insensitive matching."
  (let ((phase-lower (downcase phase))
        (all-rules (specflow-rules-load rules-path)))
    (cl-remove-if-not
     (lambda (rule)
       (let ((rule-phase (plist-get rule :phase)))
         (or (string= rule-phase "all")
             (string= rule-phase phase-lower))))
     all-rules)))

(defun specflow-rules-mandatory (&optional rules-path)
  "Get mandatory rules only.

RULES-PATH is optional path to rules file.

Returns list of rule plists where :priority is \"mandatory\"."
  (let ((all-rules (specflow-rules-load rules-path)))
    (cl-remove-if-not
     (lambda (rule)
       (string= (plist-get rule :priority) "mandatory"))
     all-rules)))

(defun specflow-rules-all (&optional rules-path)
  "Get all rules.

RULES-PATH is optional path to rules file.

Returns list of all rule plists in document order.
Convenience alias for `specflow-rules-load'."
  (specflow-rules-load rules-path))

(defun specflow-rules-by-tag (tag &optional rules-path)
  "Get rules with TAG.

TAG is a string to match against rule tags.
RULES-PATH is optional path to rules file.

Returns list of rule plists where :tags contains TAG.
Case-insensitive matching."
  (let ((tag-lower (downcase tag))
        (all-rules (specflow-rules-load rules-path)))
    (cl-remove-if-not
     (lambda (rule)
       (let ((rule-tags (plist-get rule :tags)))
         (cl-some (lambda (t) (string= (downcase t) tag-lower))
                  rule-tags)))
     all-rules)))

;;;; Formatting

(defun specflow-rules-format-for-context (rules)
  "Format RULES for AI context inclusion.

RULES is a list of rule plists.

Returns a formatted string suitable for AI context, with each rule as:

## Rule Title [priority] [phase]

Rule content...

---"
  (mapconcat
   (lambda (rule)
     (format "## %s [%s] [%s]\n\n%s\n\n---"
             (plist-get rule :title)
             (plist-get rule :priority)
             (plist-get rule :phase)
             (plist-get rule :content)))
   rules
   "\n\n"))

(provide 'specflow-rules)

;;; specflow-rules.el ends here
