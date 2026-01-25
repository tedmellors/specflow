;;; specflow-org-store.el --- SpecFlow control plane discovery and access -*- lexical-binding: t; -*-

;; Copyright (C) 2025 TRM LLC
;; Author: TRM LLC
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: tools, org

;;; Commentary:

;; This module provides control plane discovery, reading, writing, and validation
;; for the SpecFlow workflow system.  It is the foundational module that other
;; SpecFlow modules depend on.

;;; Code:

;;;; Requirements

(require 'cl-lib)

;;;; Error Conditions

(define-error 'specflow-error "SpecFlow error")
(define-error 'specflow-control-plane-not-found
  "Control plane not found" 'specflow-error)
(define-error 'specflow-control-plane-malformed
  "Control plane malformed" 'specflow-error)
(define-error 'specflow-unit-not-found
  "Unit not found" 'specflow-error)
(define-error 'specflow-unit-malformed
  "Unit malformed" 'specflow-error)
(define-error 'specflow-heading-not-found
  "Heading not found" 'specflow-error)
(define-error 'specflow-file-not-writable
  "File not writable" 'specflow-error)
(define-error 'specflow-unit-pointer-invalid
  "Unit pointer invalid" 'specflow-error)
(define-error 'specflow-parent-not-found
  "Parent not found" 'specflow-error)

;;;; Customization

(defgroup specflow nil
  "Spec-driven, phase-gated development workflow."
  :group 'tools
  :prefix "specflow-")

(defcustom specflow-control-plane-path nil
  "Explicit path to SpecFlow control plane file.
Used as fallback when automatic discovery fails."
  :type '(choice (const nil) file)
  :group 'specflow)

(defcustom specflow-control-plane-filename ".specflow/specflow.org"
  "Relative path to control plane file from project root."
  :type 'string
  :group 'specflow)

;;;; Control Plane Discovery

(defun specflow-org-store--project-root-p (dir)
  "Return non-nil if DIR is a project root.
A project root contains .git, .projectile, or .specflow-root."
  (or (file-exists-p (expand-file-name ".git" dir))
      (file-exists-p (expand-file-name ".projectile" dir))
      (file-exists-p (expand-file-name ".specflow-root" dir))))

(defun specflow-org-store--filesystem-root-p (dir)
  "Return non-nil if DIR is the filesystem root."
  (string= dir (file-name-directory (directory-file-name dir))))

(defun specflow-org-store-find-control-plane (&optional start-dir)
  "Find the SpecFlow control plane file.

Discovery algorithm:
1. Start from START-DIR (defaults to `default-directory').
2. Search upward for `specflow-control-plane-filename' (docs/specflow.org).
3. Stop if:
   - File found: return absolute path
   - Reached filesystem root: stop searching
   - Reached project root without finding file: stop searching
4. If not found, check `specflow-control-plane-path' variable.
5. If variable set and file exists: return path.
6. Otherwise: signal `specflow-control-plane-not-found'.

Returns absolute path to control plane file (string)."
  (let* ((dir (expand-file-name (or start-dir default-directory)))
         (control-plane-filename specflow-control-plane-filename)
         (found nil))
    ;; Search upward
    (while (and (not found)
                (not (specflow-org-store--filesystem-root-p dir)))
      (let ((candidate (expand-file-name control-plane-filename dir)))
        (if (file-exists-p candidate)
            (setq found candidate)
          ;; Check if we hit project root without finding file
          (if (specflow-org-store--project-root-p dir)
              ;; Stop searching - we're at project root but file not found
              (setq dir "/")  ; Force exit from loop
            ;; Move up one directory
            (setq dir (file-name-directory (directory-file-name dir)))))))
    ;; If not found via upward search, try fallback variable
    (unless found
      (when (and specflow-control-plane-path
                 (file-exists-p specflow-control-plane-path))
        (setq found (expand-file-name specflow-control-plane-path))))
    ;; Return or signal error
    (if found
        found
      (signal 'specflow-control-plane-not-found
              (list (format "Control plane not found. Searched from: %s. Set `specflow-control-plane-path' or create %s"
                            (or start-dir default-directory)
                            control-plane-filename))))))

(defun specflow-org-store-find-root-todo (&optional control-plane-path)
  "Find the root todo file (.specflow/todo.org).

CONTROL-PLANE-PATH is optional; if nil, discovered via
`specflow-org-store-find-control-plane'.

Returns absolute path to .specflow/todo.org.

Note: This function returns the path without checking if the file exists.
Callers should handle missing file if needed.

Signals `specflow-control-plane-not-found' if control plane not found."
  (let* ((cp-path (or control-plane-path
                      (specflow-org-store-find-control-plane)))
         (project-root (specflow-org-store--project-root-from-control-plane cp-path)))
    (expand-file-name ".specflow/todo.org" project-root)))

;;;; Property Parsing Helpers

(defun specflow-org-store--get-property-drawer-contents (buffer heading-name)
  "Get property drawer contents for HEADING-NAME in BUFFER.
Returns an alist of (PROPERTY . VALUE) pairs, or nil if not found."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      ;; Find heading with given name (level 1)
      (let ((heading-re (format "^\\*[ \t]+%s[ \t]*$" (regexp-quote heading-name))))
        (when (re-search-forward heading-re nil t)
          ;; Look for property drawer immediately after heading
          (forward-line 1)
          (when (looking-at "[ \t]*:PROPERTIES:[ \t]*$")
            (let ((props nil)
                  (drawer-end nil))
              ;; Find end of drawer
              (save-excursion
                (when (re-search-forward "^[ \t]*:END:[ \t]*$" nil t)
                  (setq drawer-end (point))))
              (when drawer-end
                (forward-line 1)
                ;; Parse properties
                (while (and (< (point) drawer-end)
                            (looking-at "[ \t]*:\\([^:]+\\):[ \t]*\\(.*\\)[ \t]*$"))
                  (let ((prop-name (match-string 1))
                        (prop-value (string-trim (match-string 2))))
                    (push (cons prop-name prop-value) props))
                  (forward-line 1)))
              (nreverse props))))))))

(defun specflow-org-store--read-file-to-temp-buffer (file-path)
  "Read FILE-PATH into a temporary buffer and return the buffer.
Caller is responsible for killing the buffer."
  (let ((buf (generate-new-buffer " *specflow-temp*")))
    (with-current-buffer buf
      (insert-file-contents file-path))
    buf))

(defun specflow-org-store--get-unit-property-drawer (buffer unit-name)
  "Get property drawer contents for UNIT-NAME under Units heading in BUFFER.
Looks for a level-2 heading matching UNIT-NAME under the level-1 Units heading.
Returns an alist of (PROPERTY . VALUE) pairs, or nil if not found."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      ;; Find "* Units" heading
      (when (re-search-forward "^\\*[ \t]+Units[ \t]*$" nil t)
        (let ((units-start (point))
              (units-end nil))
          ;; Find end of Units section (next level-1 heading or EOF)
          (save-excursion
            (if (re-search-forward "^\\*[ \t]" nil t)
                (setq units-end (match-beginning 0))
              (setq units-end (point-max))))
          ;; Search for unit heading within Units section
          (let ((unit-re (format "^\\*\\*[ \t]+%s[ \t]*$" (regexp-quote unit-name))))
            (when (re-search-forward unit-re units-end t)
              ;; Look for property drawer immediately after heading
              (forward-line 1)
              (when (looking-at "[ \t]*:PROPERTIES:[ \t]*$")
                (let ((props nil)
                      (drawer-end nil))
                  ;; Find end of drawer
                  (save-excursion
                    (when (re-search-forward "^[ \t]*:END:[ \t]*$" nil t)
                      (setq drawer-end (point))))
                  (when drawer-end
                    (forward-line 1)
                    ;; Parse properties
                    (while (and (< (point) drawer-end)
                                (looking-at "[ \t]*:\\([^:]+\\):[ \t]*\\(.*\\)[ \t]*$"))
                      (let ((prop-name (match-string 1))
                            (prop-value (string-trim (match-string 2))))
                        (push (cons prop-name prop-value) props))
                      (forward-line 1)))
                  (nreverse props))))))))))

(defun specflow-org-store--split-space-separated (str)
  "Split STR on whitespace, returning a list of strings.
Returns nil if STR is nil or empty."
  (when (and str (not (string-empty-p str)))
    (split-string str "[ \t]+" t)))

;;;; Project State

(defun specflow-org-store-read-project-state (&optional control-plane-path)
  "Read project state from the control plane.

CONTROL-PLANE-PATH is optional; if nil, discovered via
`specflow-org-store-find-control-plane'.

Returns a plist:
  (:phase \"Plan\"
   :active-unit \"org-store\"
   :control-plane-path \"/path/to/docs/specflow.org\")

Signals `specflow-control-plane-not-found' if file missing.
Signals `specflow-control-plane-malformed' if required properties missing."
  (let* ((cp-path (or control-plane-path
                      (specflow-org-store-find-control-plane)))
         (buf (specflow-org-store--read-file-to-temp-buffer cp-path))
         (props nil)
         (phase nil)
         (active-unit nil))
    (unwind-protect
        (progn
          ;; Get properties from Project heading
          (setq props (specflow-org-store--get-property-drawer-contents buf "Project"))
          (when props
            (setq phase (cdr (assoc "SPEC_FLOW_PHASE" props)))
            (setq active-unit (cdr (assoc "SPEC_FLOW_ACTIVE_UNIT" props))))
          ;; Validate required properties
          (unless phase
            (signal 'specflow-control-plane-malformed
                    (list (format "Missing required property SPEC_FLOW_PHASE in %s" cp-path))))
          (unless active-unit
            (signal 'specflow-control-plane-malformed
                    (list (format "Missing required property SPEC_FLOW_ACTIVE_UNIT in %s" cp-path))))
          ;; Return plist
          (list :phase phase
                :active-unit active-unit
                :control-plane-path cp-path))
      ;; Cleanup
      (kill-buffer buf))))

;;;; Unit Reading

(defun specflow-org-store--list-unit-names (buffer)
  "Return list of unit names from BUFFER in document order.
Finds all level-2 headings under the level-1 Units heading."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (let ((unit-names nil))
        ;; Find "* Units" heading
        (when (re-search-forward "^\\*[ \t]+Units[ \t]*$" nil t)
          (let ((units-end nil))
            ;; Find end of Units section (next level-1 heading or EOF)
            (save-excursion
              (if (re-search-forward "^\\*[ \t]" nil t)
                  (setq units-end (match-beginning 0))
                (setq units-end (point-max))))
            ;; Find all level-2 headings within Units section
            (while (re-search-forward "^\\*\\*[ \t]+\\([^ \t\n]+\\)[ \t]*$" units-end t)
              (push (match-string 1) unit-names))))
        (nreverse unit-names)))))

(defun specflow-org-store-read-unit (unit-name &optional control-plane-path)
  "Read unit entry for UNIT-NAME from the control plane.

CONTROL-PLANE-PATH is optional; if nil, discovered via
`specflow-org-store-find-control-plane'.

Returns a plist:
  (:name \"org-store\"
   :dir \"src/my_project/org-store/\"
   :spec \".specflow/units/org-store/spec.org\"
   :todo \".specflow/units/org-store/todo.org\"
   :parent \"core\"
   :children nil
   :context-refs nil)

All paths are relative to project root.

Signals `specflow-unit-not-found' if unit not in registry.
Signals `specflow-unit-malformed' if required properties (SPEC, TODO) missing."
  (let* ((cp-path (or control-plane-path
                      (specflow-org-store-find-control-plane)))
         (buf (specflow-org-store--read-file-to-temp-buffer cp-path))
         (props nil))
    (unwind-protect
        (progn
          ;; Get properties for the unit
          (setq props (specflow-org-store--get-unit-property-drawer buf unit-name))
          ;; Check if unit was found
          (unless props
            (signal 'specflow-unit-not-found
                    (list (format "Unit '%s' not found in %s" unit-name cp-path))))
          ;; Extract required properties
          (let ((spec (cdr (assoc "SPEC" props)))
                (todo (cdr (assoc "TODO" props))))
            ;; Validate required properties
            (unless spec
              (signal 'specflow-unit-malformed
                      (list (format "Unit '%s' missing required property SPEC in %s"
                                    unit-name cp-path))))
            (unless todo
              (signal 'specflow-unit-malformed
                      (list (format "Unit '%s' missing required property TODO in %s"
                                    unit-name cp-path))))
            ;; Extract optional properties
            (let ((dir (cdr (assoc "DIR" props)))
                  (parent (cdr (assoc "PARENT" props)))
                  (children-str (cdr (assoc "CHILDREN" props)))
                  (context-refs-str (cdr (assoc "CONTEXT_REFS" props))))
              ;; Return plist
              (list :name unit-name
                    :dir dir
                    :spec spec
                    :todo todo
                    :parent parent
                    :children (specflow-org-store--split-space-separated children-str)
                    :context-refs (specflow-org-store--split-space-separated context-refs-str)))))
      ;; Cleanup
      (kill-buffer buf))))

(defun specflow-org-store-read-unit-registry (&optional control-plane-path)
  "Read all unit entries from the control plane.

CONTROL-PLANE-PATH is optional; if nil, discovered via
`specflow-org-store-find-control-plane'.

Returns a list of unit entry plists in document order:
  ((:name \"core\" :spec \"...\" ...)
   (:name \"org-store\" :spec \"...\" ...)
   ...)

Returns an empty list if no units are defined.
Signals `specflow-unit-malformed' if any unit is missing required properties."
  (let* ((cp-path (or control-plane-path
                      (specflow-org-store-find-control-plane)))
         (buf (specflow-org-store--read-file-to-temp-buffer cp-path))
         (unit-names nil)
         (units nil))
    (unwind-protect
        (progn
          ;; Get list of unit names
          (setq unit-names (specflow-org-store--list-unit-names buf))
          ;; Read each unit (this validates required properties)
          (dolist (name unit-names)
            (push (specflow-org-store-read-unit name cp-path) units))
          (nreverse units))
      ;; Cleanup
      (kill-buffer buf))))

;;;; Property Writing

(defun specflow-org-store--goto-heading (heading-path)
  "Navigate to heading specified by HEADING-PATH in current buffer.
HEADING-PATH is a list of heading titles, e.g., (\"Project\") or (\"Units\" \"org-store\").
Returns point at beginning of heading line, or nil if not found."
  (goto-char (point-min))
  (let ((level 1)
        (found t))
    (dolist (heading heading-path)
      (when found
        (let ((heading-re (format "^%s[ \t]+%s[ \t]*$"
                                  (make-string level ?*)
                                  (regexp-quote heading))))
          (if (re-search-forward heading-re nil t)
              (progn
                (beginning-of-line)
                (setq level (1+ level)))
            (setq found nil)))))
    (when found
      (point))))

(defun specflow-org-store--find-property-in-drawer (property)
  "Find PROPERTY in the property drawer at point.
Point should be at the start of a heading line.
Returns (START . END) of the property line if found, nil otherwise.
START is the position at the beginning of the line.
END is the position at the end of the line (before newline)."
  (save-excursion
    (forward-line 1)
    (when (looking-at "[ \t]*:PROPERTIES:[ \t]*$")
      (let ((drawer-start (point))
            (drawer-end nil)
            (prop-re (format "^\\([ \t]*:%s:[ \t]*\\)\\(.*\\)$"
                             (regexp-quote property))))
        ;; Find drawer end
        (save-excursion
          (when (re-search-forward "^[ \t]*:END:[ \t]*$" nil t)
            (setq drawer-end (match-beginning 0))))
        (when drawer-end
          (forward-line 1)
          (while (and (< (point) drawer-end)
                      (not (looking-at prop-re)))
            (forward-line 1))
          (when (and (< (point) drawer-end)
                     (looking-at prop-re))
            (cons (line-beginning-position) (line-end-position))))))))

(defun specflow-org-store--get-drawer-end ()
  "Get position of :END: line for property drawer at current heading.
Point should be at the start of a heading line.
Returns position at beginning of :END: line, or nil if no drawer."
  (save-excursion
    (forward-line 1)
    (when (looking-at "[ \t]*:PROPERTIES:[ \t]*$")
      (when (re-search-forward "^[ \t]*:END:[ \t]*$" nil t)
        (match-beginning 0)))))

(defun specflow-org-store--has-property-drawer-p ()
  "Check if heading at point has a property drawer.
Point should be at the start of a heading line."
  (save-excursion
    (forward-line 1)
    (looking-at "[ \t]*:PROPERTIES:[ \t]*$")))

(defun specflow-org-store--get-heading-indent ()
  "Get the indentation string for properties under current heading.
Point should be at the start of a heading line.
Returns appropriate whitespace string."
  (save-excursion
    (let ((level (if (looking-at "^\\(\\*+\\)")
                     (length (match-string 1))
                   1)))
      ;; Standard org indentation: level + 1 spaces
      (make-string (1+ level) ?\s))))

(defun specflow-org-store-write-property (file-path heading-path property value)
  "Write PROPERTY with VALUE to FILE-PATH at HEADING-PATH.

FILE-PATH is the absolute path to the Org file.
HEADING-PATH is a list of heading titles, e.g., (\"Project\") or (\"Units\" \"org-store\").
PROPERTY is the property name (string), e.g., \"SPEC_FLOW_PHASE\".
VALUE is the new value (string).

Returns t on success.

Signals `specflow-heading-not-found' if heading path is invalid.
Signals `specflow-file-not-writable' if file cannot be saved.

Uses minimal-diff write strategy:
- Only the property line is modified
- Existing property: value replaced in-place
- Missing property: inserted at end of drawer
- Missing drawer: drawer created with property
- No other content is reformatted or modified"
  (let ((buf (generate-new-buffer " *specflow-write*")))
    (unwind-protect
        (progn
          ;; Read file into buffer
          (with-current-buffer buf
            (insert-file-contents file-path)
            ;; Navigate to heading
            (unless (specflow-org-store--goto-heading heading-path)
              (signal 'specflow-heading-not-found
                      (list (format "Heading path %S not found in %s"
                                    heading-path file-path))))
            ;; Now we're at the heading - handle property drawer
            (let ((prop-bounds (specflow-org-store--find-property-in-drawer property))
                  (indent (specflow-org-store--get-heading-indent)))
              (cond
               ;; Case 1: Property exists - replace value
               (prop-bounds
                (goto-char (car prop-bounds))
                (delete-region (car prop-bounds) (cdr prop-bounds))
                (insert (format "%s:%s: %s" indent property value)))
               ;; Case 2: Drawer exists but property doesn't - insert at end
               ((specflow-org-store--has-property-drawer-p)
                (let ((end-pos (specflow-org-store--get-drawer-end)))
                  (goto-char end-pos)
                  (insert (format "%s:%s: %s\n" indent property value))))
               ;; Case 3: No drawer - create one
               (t
                (forward-line 1)
                (insert (format "%s:PROPERTIES:\n%s:%s: %s\n%s:END:\n"
                                indent indent property value indent)))))
            ;; Write buffer to file
            (condition-case err
                (write-region (point-min) (point-max) file-path nil 'quiet)
              (error
               (signal 'specflow-file-not-writable
                       (list (format "Cannot write to %s: %s"
                                     file-path (error-message-string err)))))))
          t)
      ;; Cleanup
      (kill-buffer buf))))

;;;; Validation

(defun specflow-org-store--project-root-from-control-plane (&optional control-plane-path)
  "Get project root directory from CONTROL-PLANE-PATH.
Control plane is expected at .specflow/specflow.org, so project root
is the parent directory.  If CONTROL-PLANE-PATH is nil,
discovers it via `specflow-org-store-find-control-plane'."
  (let ((cp-path (or control-plane-path
                     (specflow-org-store-find-control-plane))))
    ;; Control plane is at <project-root>/.specflow/specflow.org
    ;; So we go up one directory: specflow.org -> .specflow -> project-root
    (file-name-directory
     (directory-file-name
      (file-name-directory cp-path)))))

(defun specflow-org-store-validate-unit-pointers (unit-entry &optional project-root)
  "Validate that required file pointers in UNIT-ENTRY exist.

UNIT-ENTRY is a unit plist (as returned by `specflow-org-store-read-unit').
PROJECT-ROOT is optional; if nil, discovered from control plane.

Checks that the following files exist (relative to PROJECT-ROOT):
- :spec
- :todo

Returns t if all required files exist.

Signals `specflow-unit-pointer-invalid' with list of missing files
if any required file does not exist."
  (let* ((root (or project-root
                   (specflow-org-store--project-root-from-control-plane)))
         (unit-name (plist-get unit-entry :name))
         (spec-path (plist-get unit-entry :spec))
         (todo-path (plist-get unit-entry :todo))
         (missing nil))
    ;; Check each required pointer
    (unless (and spec-path
                 (file-exists-p (expand-file-name spec-path root)))
      (push (cons :spec spec-path) missing))
    (unless (and todo-path
                 (file-exists-p (expand-file-name todo-path root)))
      (push (cons :todo todo-path) missing))
    ;; Return t or signal error
    (if missing
        (signal 'specflow-unit-pointer-invalid
                (list (format "Unit '%s' has invalid file pointers: %s"
                              unit-name
                              (mapconcat (lambda (m)
                                           (format "%s=%s" (car m) (or (cdr m) "nil")))
                                         (nreverse missing)
                                         ", "))))
      t)))

(defun specflow-org-store-validate-parent-chain (unit-name &optional control-plane-path)
  "Validate and return the parent chain for UNIT-NAME.

UNIT-NAME is the name of the unit to validate.
CONTROL-PLANE-PATH is optional; if nil, discovered via
`specflow-org-store-find-control-plane'.

Returns a list of ancestor unit names in order from immediate parent
to root ancestor.  For example, if unit-A has parent unit-B, and unit-B
has parent unit-C, calling this on unit-A returns (\"unit-B\" \"unit-C\").

Returns an empty list if the unit has no parent.

Signals `specflow-parent-not-found' if any parent in the chain
references a nonexistent unit.
Signals `specflow-unit-not-found' if UNIT-NAME itself does not exist."
  (let* ((cp-path (or control-plane-path
                      (specflow-org-store-find-control-plane)))
         (ancestors nil)
         (visited nil)
         (current-name unit-name))
    ;; First, verify the unit itself exists (will signal specflow-unit-not-found if not)
    (specflow-org-store-read-unit current-name cp-path)
    ;; Walk the parent chain
    (catch 'done
      (while t
        (let* ((unit-entry (specflow-org-store-read-unit current-name cp-path))
               (parent-name (plist-get unit-entry :parent)))
          (if (or (null parent-name) (string-empty-p parent-name))
              ;; No parent - we're done
              (throw 'done nil)
            ;; Check for circular reference
            (when (member parent-name visited)
              (signal 'specflow-parent-not-found
                      (list (format "Circular parent reference detected: %s -> %s"
                                    current-name parent-name))))
            ;; Try to read the parent unit
            (condition-case nil
                (specflow-org-store-read-unit parent-name cp-path)
              (specflow-unit-not-found
               (signal 'specflow-parent-not-found
                       (list (format "Unit '%s' references nonexistent parent '%s'"
                                     current-name parent-name)))))
            ;; Parent exists - add to ancestors and continue
            (push current-name visited)
            (push parent-name ancestors)
            (setq current-name parent-name)))))
    ;; Return ancestors in order (immediate parent first)
    (nreverse ancestors)))

;;;; Utility Function (shared with bundle/hydrate)

(defun specflow-org-store--split-paths (value)
  "Split VALUE into a list of paths.
VALUE may be a single path or space-separated paths.
Returns a list of path strings, or nil if VALUE is nil or empty."
  (when (and value (not (string-empty-p (string-trim value))))
    (split-string value "[ \t]+" t)))

;;;; Interactive Commands

(defconst specflow-valid-phases
  '("Plan" "Specify" "Scaffold" "Implement" "Validate" "Document")
  "List of valid SpecFlow phase names.")

(defun specflow-phase-shift (phase unit)
  "Change the current SpecFlow phase to PHASE and active unit to UNIT.

PHASE must be one of: Plan, Specify, Scaffold, Implement, Validate, Document.
UNIT must be a unit name from the control plane registry.

Interactively, prompts with `completing-read' for both values, with current
values as defaults.

Updates both SPEC_FLOW_PHASE and SPEC_FLOW_ACTIVE_UNIT properties in the
control plane's Project heading.
Returns t on success."
  (interactive
   (let* ((cp-path (specflow-org-store-find-control-plane))
          (state (specflow-org-store-read-project-state cp-path))
          (current-phase (plist-get state :phase))
          (current-unit (plist-get state :active-unit))
          (registry (specflow-org-store-read-unit-registry cp-path))
          (unit-names (mapcar (lambda (u) (plist-get u :name)) registry))
          (selected-phase (completing-read
                           (format "Phase [%s]: " current-phase)
                           specflow-valid-phases nil t nil nil current-phase))
          (selected-unit (completing-read
                          (format "Unit [%s]: " current-unit)
                          unit-names nil t nil nil current-unit)))
     (list selected-phase selected-unit)))
  ;; Validate phase
  (unless (member phase specflow-valid-phases)
    (user-error "Invalid phase: %s. Must be one of: %s"
                phase (mapconcat #'identity specflow-valid-phases ", ")))
  ;; Validate unit
  (let* ((cp-path (specflow-org-store-find-control-plane))
         (registry (specflow-org-store-read-unit-registry cp-path))
         (unit-names (mapcar (lambda (u) (plist-get u :name)) registry)))
    (unless (member unit unit-names)
      (user-error "Invalid unit: %s. Must be one of: %s"
                  unit (mapconcat #'identity unit-names ", ")))
    ;; Write both properties
    (specflow-org-store-write-property cp-path '("Project") "SPEC_FLOW_PHASE" phase)
    (specflow-org-store-write-property cp-path '("Project") "SPEC_FLOW_ACTIVE_UNIT" unit)
    (message "Phase: %s, Unit: %s" phase unit)
    t))

(defun specflow-add-root-task (headline)
  "Add a TODO task with HEADLINE to .specflow/todo.org under Backlog section.

Interactively, prompts for headline string.

The task is inserted as a level-2 TODO heading at the end of the Backlog
section (before the next level-1 heading or end of file).

Returns t on success.

Signals `specflow-heading-not-found' if Backlog heading not found in .specflow/todo.org.
Signals `specflow-file-not-writable' if .specflow/todo.org cannot be saved."
  (interactive "sTask headline: ")
  (let* ((cp-path (specflow-org-store-find-control-plane))
         (project-root (specflow-org-store--project-root-from-control-plane cp-path))
         (todo-file (expand-file-name ".specflow/todo.org" project-root))
         (buf (generate-new-buffer " *specflow-add-task*")))
    (unwind-protect
        (progn
          ;; Read todo.org into buffer
          (with-current-buffer buf
            (insert-file-contents todo-file)
            (goto-char (point-min))
            ;; Find "* Backlog" heading (matches "Backlog" or "Backlog (future enhancements)" etc.)
            (unless (re-search-forward "^\\*[ \t]+Backlog\\b" nil t)
              (signal 'specflow-heading-not-found
                      (list (format "Heading 'Backlog' not found in %s" todo-file))))
            ;; Find end of Backlog section (next level-1 heading or EOF)
            (let ((backlog-start (point))
                  (backlog-end nil))
              (if (re-search-forward "^\\*[ \t]" nil t)
                  (setq backlog-end (match-beginning 0))
                (setq backlog-end (point-max)))
              ;; Go to end of Backlog section
              (goto-char backlog-end)
              ;; Ensure we're on a new line
              (unless (bolp)
                (insert "\n"))
              ;; Insert the new task
              (insert (format "** TODO %s\n" headline)))
            ;; Write buffer to file
            (condition-case err
                (write-region (point-min) (point-max) todo-file nil 'quiet)
              (error
               (signal 'specflow-file-not-writable
                       (list (format "Cannot write to %s: %s"
                                     todo-file (error-message-string err)))))))
          (message "Task added: %s" headline)
          t)
      ;; Cleanup
      (kill-buffer buf))))

;;;; Task Management Commands

(defun specflow-org-store--parse-backlog-tasks (todo-file)
  "Parse backlog tasks from TODO-FILE.
Returns a list of (HEADLINE . BODY) cons cells for each level-2 heading
in the Backlog section."
  (let ((buf (generate-new-buffer " *specflow-parse-backlog*"))
        (tasks nil))
    (unwind-protect
        (with-current-buffer buf
          (insert-file-contents todo-file)
          (goto-char (point-min))
          ;; Find "* Backlog" heading (with optional suffix like "future enhancements")
          (unless (re-search-forward "^\\*[ \t]+Backlog\\b" nil t)
            (signal 'specflow-heading-not-found
                    (list (format "Heading 'Backlog' not found in %s" todo-file))))
          ;; Find end of Backlog section
          (let ((backlog-end nil))
            (save-excursion
              (if (re-search-forward "^\\*[ \t]" nil t)
                  (setq backlog-end (match-beginning 0))
                (setq backlog-end (point-max))))
            ;; Parse level-2 headings within Backlog
            (while (re-search-forward "^\\*\\*[ \t]+\\(TODO\\|NEXT\\|WAITING\\)?[ \t]*\\(.+\\)$" backlog-end t)
              (let* ((headline (string-trim (match-string 2)))
                     (body-start (1+ (line-end-position)))
                     (body-end nil)
                     (body nil))
                ;; Find body end (next heading or section end)
                (save-excursion
                  (if (re-search-forward "^\\*\\*[ \t]" backlog-end t)
                      (setq body-end (match-beginning 0))
                    (setq body-end backlog-end)))
                ;; Extract body
                (when (< body-start body-end)
                  (setq body (string-trim
                              (buffer-substring-no-properties body-start body-end))))
                (push (cons headline (or body "")) tasks)))))
      (kill-buffer buf))
    (nreverse tasks)))

(defun specflow-org-store--format-refine-prompt (headline body unit-hint user-context)
  "Format a prompt for refining a task.
HEADLINE is the task headline.
BODY is the task body text.
UNIT-HINT is the optional related unit (may be empty string).
USER-CONTEXT is the user's additional context."
  (concat
   "## Task to Refine\n\n"
   "** TODO " headline "\n"
   (if (and body (not (string-empty-p body)))
       (concat body "\n")
     "")
   "\n## Context\n\n"
   "Related unit: " (if (and unit-hint (not (string-empty-p unit-hint)))
                        unit-hint
                      "Not specified") "\n"
   "Notes: " (if (and user-context (not (string-empty-p user-context)))
                 user-context
               "None") "\n"
   "\n## Guidelines\n\n"
   "Rewrite this task to be actionable and outcome-based:\n"
   "- Use Given/When/Then format where appropriate\n"
   "- Be specific about expected outcomes\n"
   "- If unit placement is unclear, recommend where it should live\n"
   "- Keep it concise (3-5 bullets max)\n\n"
   "Refine this task and update it in .specflow/todo.org.\n"))

(defun specflow-refine-task ()
  "Generate a prompt for Claude to improve a backlog task.

Interactively:
1. Select a task from the Backlog section
2. Optionally specify a related unit
3. Add additional context for Claude

The generated prompt is copied to the kill-ring.
This command does NOT modify .specflow/todo.org - the prompt instructs Claude to make changes.

Signals `specflow-heading-not-found' if Backlog section not found."
  (interactive)
  (let* ((cp-path (specflow-org-store-find-control-plane))
         (project-root (specflow-org-store--project-root-from-control-plane cp-path))
         (todo-file (expand-file-name ".specflow/todo.org" project-root))
         (tasks (specflow-org-store--parse-backlog-tasks todo-file))
         (headlines (mapcar #'car tasks))
         (selected-headline (completing-read "Select task to refine: " headlines nil t))
         (selected-task (assoc selected-headline tasks))
         (body (cdr selected-task))
         (unit-hint (read-string "Related unit (optional, RET to skip): "))
         (user-context (read-string "Additional context for Claude: "))
         (prompt (specflow-org-store--format-refine-prompt
                  selected-headline body unit-hint user-context)))
    (kill-new prompt)
    (message "Task prompt copied to kill-ring")
    prompt))

(defun specflow-activate-task ()
  "Generate a prompt for Claude to refine and activate a backlog task.

Interactively:
1. Select a task from the Backlog section
2. Optionally specify a related unit
3. Add additional context for Claude

The generated prompt is copied to the kill-ring.
This command does NOT modify .specflow/todo.org - the prompt instructs Claude to:
- Refine the task
- Move it from Backlog to Active section as NEXT
- Demote any existing NEXT task to TODO

Signals `specflow-heading-not-found' if Backlog section not found."
  (interactive)
  (let* ((cp-path (specflow-org-store-find-control-plane))
         (project-root (specflow-org-store--project-root-from-control-plane cp-path))
         (todo-file (expand-file-name ".specflow/todo.org" project-root))
         (tasks (specflow-org-store--parse-backlog-tasks todo-file))
         (headlines (mapcar #'car tasks))
         (selected-headline (completing-read "Select task to activate: " headlines nil t))
         (selected-task (assoc selected-headline tasks))
         (body (cdr selected-task))
         (unit-hint (read-string "Related unit (optional, RET to skip): "))
         (user-context (read-string "Additional context for Claude: "))
         (base-prompt (specflow-org-store--format-refine-prompt
                       selected-headline body unit-hint user-context))
         ;; Append activation instructions
         (prompt (concat base-prompt
                         "\nAfter refining, move this task from Backlog to Active section as NEXT.\n"
                         "If there is an existing NEXT task in Active, demote it to TODO.\n")))
    (kill-new prompt)
    (message "Task prompt copied to kill-ring")
    prompt))

(provide 'specflow-org-store)
;;; specflow-org-store.el ends here
