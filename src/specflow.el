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
;; This file contains the MVP implementation.  As the codebase grows,
;; it may be split into specflow-org-store.el, specflow-core.el,
;; specflow-bundle.el, and specflow-hydrate.el.

;;; Code:

;;;; Requirements

(require 'cl-lib)

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

(defcustom specflow-control-plane-filename "docs/specflow.org"
  "Relative path to control plane file from project root."
  :type 'string
  :group 'specflow)

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

;;;; org-store: Control Plane Discovery

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

;;;; org-store: Property Parsing Helpers

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

;;;; org-store: Project State

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

;;;; org-store: Unit Reading

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
   :dir \"src/\"
   :spec \"units/org-store/spec.org\"
   :todo \"units/org-store/todo.org\"
   :rules \"units/org-store/CLAUDE.md\"
   :parent \"core\"
   :children nil
   :context-refs nil)

All paths are relative to project root.

Signals `specflow-unit-not-found' if unit not in registry.
Signals `specflow-unit-malformed' if required properties (SPEC, TODO, RULES) missing."
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
                (todo (cdr (assoc "TODO" props)))
                (rules (cdr (assoc "RULES" props))))
            ;; Validate required properties
            (unless spec
              (signal 'specflow-unit-malformed
                      (list (format "Unit '%s' missing required property SPEC in %s"
                                    unit-name cp-path))))
            (unless todo
              (signal 'specflow-unit-malformed
                      (list (format "Unit '%s' missing required property TODO in %s"
                                    unit-name cp-path))))
            (unless rules
              (signal 'specflow-unit-malformed
                      (list (format "Unit '%s' missing required property RULES in %s"
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
                    :rules rules
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

;;;; org-store: Property Writing

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

;;;; org-store: Validation

(defun specflow-org-store--project-root-from-control-plane (&optional control-plane-path)
  "Get project root directory from CONTROL-PLANE-PATH.
Control plane is expected at docs/specflow.org, so project root
is the grandparent directory.  If CONTROL-PLANE-PATH is nil,
discovers it via `specflow-org-store-find-control-plane'."
  (let ((cp-path (or control-plane-path
                     (specflow-org-store-find-control-plane))))
    ;; Control plane is at <project-root>/docs/specflow.org
    ;; So we go up two directories: specflow.org -> docs -> project-root
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
- :rules

Returns t if all required files exist.

Signals `specflow-unit-pointer-invalid' with list of missing files
if any required file does not exist."
  (let* ((root (or project-root
                   (specflow-org-store--project-root-from-control-plane)))
         (unit-name (plist-get unit-entry :name))
         (spec-path (plist-get unit-entry :spec))
         (todo-path (plist-get unit-entry :todo))
         (rules-path (plist-get unit-entry :rules))
         (missing nil))
    ;; Check each required pointer
    (unless (and spec-path
                 (file-exists-p (expand-file-name spec-path root)))
      (push (cons :spec spec-path) missing))
    (unless (and todo-path
                 (file-exists-p (expand-file-name todo-path root)))
      (push (cons :todo todo-path) missing))
    (unless (and rules-path
                 (file-exists-p (expand-file-name rules-path root)))
      (push (cons :rules rules-path) missing))
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

;;;; bundle: Helper Functions

(defun specflow-bundle--split-paths (value)
  "Split VALUE into a list of paths.
VALUE may be a single path or space-separated paths.
Returns a list of path strings, or nil if VALUE is nil or empty."
  (when (and value (not (string-empty-p (string-trim value))))
    (split-string value "[ \t]+" t)))

(defun specflow-bundle--read-file-content (file-path &optional project-root)
  "Read content of FILE-PATH, returning string or placeholder if missing.
FILE-PATH may be absolute or relative to PROJECT-ROOT.
If PROJECT-ROOT is nil, it is discovered from the control plane.
Returns file content as string, or placeholder if file not found."
  (let* ((root (or project-root
                   (specflow-org-store--project-root-from-control-plane)))
         (abs-path (if (file-name-absolute-p file-path)
                       file-path
                     (expand-file-name file-path root))))
    (if (file-exists-p abs-path)
        (with-temp-buffer
          (insert-file-contents abs-path)
          (buffer-string))
      (message "Warning: File not found: %s" abs-path)
      (format "<file not found: %s>" file-path))))

(defun specflow-bundle--extract-next-task (&optional todo-path project-root)
  "Extract the first NEXT task from TODO-PATH.
TODO-PATH defaults to 'todo.org' at PROJECT-ROOT.
Returns the NEXT heading and its content as a string.
Returns placeholder if no NEXT task found."
  (let* ((root (or project-root
                   (specflow-org-store--project-root-from-control-plane)))
         (path (expand-file-name (or todo-path "todo.org") root)))
    (if (not (file-exists-p path))
        "<no root todo.org found>"
      (with-temp-buffer
        (insert-file-contents path)
        (goto-char (point-min))
        ;; Find first NEXT heading
        (if (re-search-forward "^\\(\\*+\\)[ \t]+NEXT[ \t]+\\(.*\\)$" nil t)
            (let* ((level (length (match-string 1)))
                   (title (match-string 2))
                   (start (line-beginning-position))
                   (end nil))
              ;; Find end: next heading of same or higher level, or EOF
              (forward-line 1)
              (if (re-search-forward (format "^\\*\\{1,%d\\}[ \t]" level) nil t)
                  (setq end (line-beginning-position))
                (setq end (point-max)))
              ;; Extract content
              (string-trim (buffer-substring-no-properties start end)))
          "<no NEXT task found>")))))

;;;; bundle: Formatting

(defun specflow-bundle--format-section (header content)
  "Format a section with HEADER and CONTENT."
  (format "## %s\n%s\n" header content))

(defun specflow-bundle--format-file-section (label path content)
  "Format a file subsection with LABEL, PATH, and CONTENT."
  (format "### %s: %s\n%s\n" label path content))

(defun specflow-bundle--format-output-text (project-state next-task parent-chain-content unit-content &optional timestamp)
  "Format the complete bundle output with full file contents (text mode).
PROJECT-STATE is a plist with :phase and :active-unit.
NEXT-TASK is the extracted NEXT task string.
PARENT-CHAIN-CONTENT is a list of (name . sections-alist) for each ancestor.
UNIT-CONTENT is a (name . sections-alist) for the active unit.
TIMESTAMP is optional; if nil, current time is used."
  (let ((ts (or timestamp (format-time-string "%Y-%m-%dT%H:%M:%S"))))
    (with-temp-buffer
      ;; Header
      (insert (format "# SpecFlow Context Bundle (Text)\n# Generated: %s\n\n" ts))
      ;; Project State
      (insert (specflow-bundle--format-section
               "Project State"
               (format "Phase: %s\nActive Unit: %s"
                       (plist-get project-state :phase)
                       (plist-get project-state :active-unit))))
      ;; NEXT Task
      (insert (specflow-bundle--format-section "NEXT Task" next-task))
      ;; Parent chain (root-to-leaf order - list is already in this order)
      (dolist (parent parent-chain-content)
        (let ((name (car parent))
              (sections (cdr parent)))
          (insert (format "## Parent: %s\n\n" name))
          (dolist (section sections)
            (let ((label (car section))
                  (path (cadr section))
                  (content (caddr section)))
              (insert (specflow-bundle--format-file-section label path content))))))
      ;; Active unit
      (let ((name (car unit-content))
            (sections (cdr unit-content)))
        (insert (format "## Unit: %s\n\n" name))
        (dolist (section sections)
          (let ((label (car section))
                (path (cadr section))
                (content (caddr section)))
            (insert (specflow-bundle--format-file-section label path content)))))
      (buffer-string))))

(defun specflow-bundle--format-output-paths (project-state next-task parent-chain-content unit-content &optional timestamp)
  "Format the bundle output with file paths only (paths mode).
PROJECT-STATE is a plist with :phase and :active-unit.
NEXT-TASK is the extracted NEXT task string.
PARENT-CHAIN-CONTENT is a list of (name . sections-alist) for each ancestor.
UNIT-CONTENT is a (name . sections-alist) for the active unit.
TIMESTAMP is optional; if nil, current time is used."
  (let ((ts (or timestamp (format-time-string "%Y-%m-%dT%H:%M:%S"))))
    (with-temp-buffer
      ;; Header
      (insert (format "# SpecFlow Context Bundle (Paths)\n# Generated: %s\n\n" ts))
      ;; Project State
      (insert (specflow-bundle--format-section
               "Project State"
               (format "Phase: %s\nActive Unit: %s"
                       (plist-get project-state :phase)
                       (plist-get project-state :active-unit))))
      ;; NEXT Task (include full content - typically short)
      (insert (specflow-bundle--format-section "NEXT Task" next-task))
      ;; Parent chain (paths only)
      (dolist (parent parent-chain-content)
        (let ((name (car parent))
              (sections (cdr parent)))
          (insert (format "## Parent: %s\n" name))
          (dolist (section sections)
            (let ((label (car section))
                  (path (cadr section)))
              (insert (format "- %s: %s\n" label path))))
          (insert "\n")))
      ;; Active unit (paths only)
      (let ((name (car unit-content))
            (sections (cdr unit-content)))
        (insert (format "## Unit: %s\n" name))
        (dolist (section sections)
          (let ((label (car section))
                (path (cadr section)))
            (insert (format "- %s: %s\n" label path))))
        (insert "\n"))
      ;; Footer
      (insert "Read the files above for full context.\n")
      (buffer-string))))

;;;; bundle: Core Functions

(defun specflow-bundle--gather-unit-content (unit-entry project-root)
  "Gather content for UNIT-ENTRY, returning (name . sections-list).
Each section is (LABEL PATH CONTENT)."
  (let* ((name (plist-get unit-entry :name))
         (spec-value (plist-get unit-entry :spec))
         (todo-value (plist-get unit-entry :todo))
         (rules-value (plist-get unit-entry :rules))
         (sections nil))
    ;; Gather SPEC files
    (dolist (path (specflow-bundle--split-paths spec-value))
      (push (list "SPEC" path (specflow-bundle--read-file-content path project-root))
            sections))
    ;; Gather TODO files
    (dolist (path (specflow-bundle--split-paths todo-value))
      (push (list "TODO" path (specflow-bundle--read-file-content path project-root))
            sections))
    ;; Gather RULES files
    (dolist (path (specflow-bundle--split-paths rules-value))
      (push (list "RULES" path (specflow-bundle--read-file-content path project-root))
            sections))
    (cons name (nreverse sections))))

(defun specflow-bundle--gather-context (&optional unit-name)
  "Gather all context data for UNIT-NAME (or active unit if nil).
Returns a plist with :project-state, :next-task, :parent-chain-content, :unit-content."
  (let* ((cp-path (specflow-org-store-find-control-plane))
         (project-root (specflow-org-store--project-root-from-control-plane cp-path))
         (project-state (specflow-org-store-read-project-state cp-path))
         (active-unit (or unit-name (plist-get project-state :active-unit)))
         (unit-entry (specflow-org-store-read-unit active-unit cp-path))
         (parent-names (specflow-org-store-validate-parent-chain active-unit cp-path))
         (next-task (specflow-bundle--extract-next-task nil project-root))
         (parent-chain-content nil)
         (unit-content nil))
    ;; Gather parent chain content (in root-to-leaf order)
    ;; parent-names is already in order from immediate parent to root
    ;; We need to reverse it for root-to-leaf presentation
    (dolist (parent-name (reverse parent-names))
      (let ((parent-entry (specflow-org-store-read-unit parent-name cp-path)))
        (push (specflow-bundle--gather-unit-content parent-entry project-root)
              parent-chain-content)))
    (setq parent-chain-content (nreverse parent-chain-content))
    ;; Gather active unit content
    (setq unit-content (specflow-bundle--gather-unit-content unit-entry project-root))
    ;; Return context plist
    (list :project-state project-state
          :next-task next-task
          :parent-chain-content parent-chain-content
          :unit-content unit-content)))

(defun specflow-bundle-context (&optional unit-name)
  "Generate a context bundle for UNIT-NAME in paths mode (default).
If UNIT-NAME is nil, uses the active unit from the control plane.
Returns a compact string with file paths for Claude Code to read.
For full file contents, use `specflow-bundle-context-text'."
  (let ((ctx (specflow-bundle--gather-context unit-name)))
    (specflow-bundle--format-output-paths
     (plist-get ctx :project-state)
     (plist-get ctx :next-task)
     (plist-get ctx :parent-chain-content)
     (plist-get ctx :unit-content))))

(defun specflow-bundle-context-text (&optional unit-name)
  "Generate a context bundle for UNIT-NAME in text mode (full content).
If UNIT-NAME is nil, uses the active unit from the control plane.
Returns a comprehensive string with full file contents.
For compact output with paths only, use `specflow-bundle-context'."
  (let ((ctx (specflow-bundle--gather-context unit-name)))
    (specflow-bundle--format-output-text
     (plist-get ctx :project-state)
     (plist-get ctx :next-task)
     (plist-get ctx :parent-chain-content)
     (plist-get ctx :unit-content))))

(defun specflow-bundle-context-no-timestamp (&optional unit-name)
  "Like `specflow-bundle-context' but with fixed timestamp for testing.
Uses paths mode (default)."
  (let ((ctx (specflow-bundle--gather-context unit-name)))
    (specflow-bundle--format-output-paths
     (plist-get ctx :project-state)
     (plist-get ctx :next-task)
     (plist-get ctx :parent-chain-content)
     (plist-get ctx :unit-content)
     "2025-01-01T00:00:00")))

(defun specflow-bundle-context-text-no-timestamp (&optional unit-name)
  "Like `specflow-bundle-context-text' but with fixed timestamp for testing.
Uses text mode (full content)."
  (let ((ctx (specflow-bundle--gather-context unit-name)))
    (specflow-bundle--format-output-text
     (plist-get ctx :project-state)
     (plist-get ctx :next-task)
     (plist-get ctx :parent-chain-content)
     (plist-get ctx :unit-content)
     "2025-01-01T00:00:00")))

;;;; bundle: Interactive Commands

(defun specflow-bundle ()
  "Generate and display a context bundle in paths mode (default).
Uses compact output with file paths for Claude Code to read.
Copies the bundle to the kill-ring and displays it in a buffer.
For full file contents, use `specflow-bundle-text'."
  (interactive)
  (let ((bundle (specflow-bundle-context)))
    ;; Copy to kill-ring
    (kill-new bundle)
    ;; Display in buffer
    (with-current-buffer (get-buffer-create "*SpecFlow Bundle*")
      (erase-buffer)
      (insert bundle)
      (goto-char (point-min))
      (display-buffer (current-buffer)))
    (message "SpecFlow bundle (paths) copied to kill-ring and displayed in *SpecFlow Bundle* buffer")))

(defun specflow-bundle-text ()
  "Generate and display a context bundle in text mode (full content).
Uses comprehensive output with full file contents for gptel or web Claude.
Copies the bundle to the kill-ring and displays it in a buffer.
For compact output with paths only, use `specflow-bundle'."
  (interactive)
  (let ((bundle (specflow-bundle-context-text)))
    ;; Copy to kill-ring
    (kill-new bundle)
    ;; Display in buffer
    (with-current-buffer (get-buffer-create "*SpecFlow Bundle*")
      (erase-buffer)
      (insert bundle)
      (goto-char (point-min))
      (display-buffer (current-buffer)))
    (message "SpecFlow bundle (text) copied to kill-ring and displayed in *SpecFlow Bundle* buffer")))

;;;; hydrate: Phase Actions

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
      "- Write CLAUDE.md (unit rules)
- Write todo.org (outcome-based tasks)
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

;;;; hydrate: NEXT Task Extraction

(defun specflow-hydrate--extract-next-task (&optional todo-path project-root)
  "Extract the first NEXT task from TODO-PATH.
PROJECT-ROOT is used to resolve relative paths.
Returns the heading and its immediate body, or a placeholder if not found."
  (let* ((root (or project-root (specflow-org-store--project-root-from-control-plane)))
         (path (or todo-path "todo.org"))
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

;;;; hydrate: File Pointer Gathering

(defun specflow-hydrate--gather-file-pointers (unit-entry parent-chain project-root cp-path)
  "Gather file pointers for header from UNIT-ENTRY and PARENT-CHAIN.
PROJECT-ROOT is the project root directory.
CP-PATH is the control plane path."
  (let ((pointers nil))
    ;; Control plane (always include)
    (push (format "- %s (control plane)" cp-path) pointers)
    ;; Root todo.org
    (let ((root-todo (expand-file-name "todo.org" project-root)))
      (push (format "- %s (root todo)" root-todo) pointers))
    ;; Unit files
    (when unit-entry
      (let ((spec (plist-get unit-entry :spec))
            (todo (plist-get unit-entry :todo))
            (rules (plist-get unit-entry :rules)))
        (when spec
          (push (format "- %s (unit SPEC)" spec) pointers))
        (when todo
          (push (format "- %s (unit TODO)" todo) pointers))
        (when rules
          (push (format "- %s (unit RULES)" rules) pointers))))
    ;; Parent specs
    (dolist (parent parent-chain)
      (let* ((parent-entry (specflow-org-store-read-unit parent cp-path))
             (parent-spec (plist-get parent-entry :spec)))
        (when parent-spec
          (dolist (spec-path (specflow-bundle--split-paths parent-spec))
            (push (format "- %s (parent: %s)" spec-path parent) pointers)))))
    (nreverse pointers)))

;;;; hydrate: Header Generation

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
         (next-task (specflow-hydrate--extract-next-task "todo.org" project-root)))
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

;;;; hydrate: Safe Buffer Detection

(defun specflow-hydrate--safe-buffer-p ()
  "Return non-nil if current buffer is safe for header insertion.
Safe buffers: *scratch*, buffers with gptel/claude/chat in name."
  (let ((name (buffer-name)))
    (or (string= name "*scratch*")
        (string-match-p "gptel\\|claude\\|chat" (downcase name)))))

;;;; hydrate: Interactive Commands

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
           (next-task (specflow-hydrate--extract-next-task "todo.org" project-root)))
      (insert next-task)
      (message "NEXT task inserted"))))

;;;; hydrate: Navigation Helpers

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
  "Open the root todo.org file."
  (interactive)
  (let* ((cp-path (specflow-org-store-find-control-plane))
         (project-root (and cp-path (specflow-org-store--project-root-from-control-plane cp-path)))
         (todo-path (and project-root (expand-file-name "todo.org" project-root))))
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
    (let ((spec-path (car (specflow-bundle--split-paths spec))))
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

(defun specflow-hydrate-open-active-unit-rules ()
  "Open the active unit's rules file (CLAUDE.md)."
  (interactive)
  (let* ((cp-path (specflow-org-store-find-control-plane))
         (state (and cp-path (specflow-org-store-read-project-state cp-path)))
         (active-unit (plist-get state :active-unit))
         (unit-entry (and active-unit (specflow-org-store-read-unit active-unit cp-path)))
         (rules (plist-get unit-entry :rules)))
    (unless rules
      (user-error "No RULES found for unit: %s" active-unit))
    (find-file (expand-file-name rules (file-name-directory cp-path)))
    (message "Opened unit rules: %s" rules)))

;;;; hydrate: Violation Patterns

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

;;;; compose: Minor Mode

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

;;;; compose: Phase Enforcement

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

;;;; compose: Template Definitions

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

;;;; compose: Template Buffer Creation

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

;;;; compose: Buffer Content Extraction

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

;;;; compose: Context File Selection

(defun specflow-compose--context-files-new-unit ()
  "Return context files for new-unit task."
  (let* ((cp-path (specflow-org-store-find-control-plane))
         (project-root (specflow-org-store--project-root-from-control-plane cp-path)))
    (list
     (cons "units/core/architecture.org" "architecture")
     (cons (file-relative-name cp-path project-root) "control plane")
     (cons "todo.org" "root tasks"))))

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
     (list (cons "docs/specflow.org" "control plane")))))

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
     (list (cons "docs/specflow.org" "control plane")))))

(defun specflow-compose--context-files-refactor (unit-name)
  "Return context files for refactor task on UNIT-NAME."
  (condition-case nil
      (let* ((cp-path (specflow-org-store-find-control-plane))
             (unit-entry (specflow-org-store-read-unit unit-name cp-path)))
        (list
         (cons (plist-get unit-entry :spec) "unit spec")
         (cons (plist-get unit-entry :rules) "unit rules")))
    (error
     (list (cons "docs/specflow.org" "control plane")))))

;;;; compose: Prompt Generation

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
1. Update units/core/architecture.org with %s unit description
2. Add %s entry to Units section in control plane (docs/specflow.org)
3. Create units/%s/ directory
4. Draft spec.org based on requirements above
5. Update root todo.org with NEXT task for %s

Phase rules: Do NOT write implementation code. Planning only."
          unit-name unit-name unit-name unit-name))

(defun specflow-compose--instructions-edit-spec (unit-name)
  "Return instructions for editing spec of UNIT-NAME."
  (format "You are in Plan phase. Edit the specification for %s:
1. Read the current spec at units/%s/spec.org
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
3. Update spec.org with new requirements
4. Update todo.org with implementation tasks

Phase rules: Do NOT write implementation code. Planning and spec updates only."
            unit-name parent-note)))

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

1. Update root todo.org:
   - Mark \"** NEXT %s: %s phase\" as DONE with summary
   - Create \"** NEXT %s: %s phase\"%s

2. Update control plane (docs/specflow.org):
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
            (_ (list (cons "docs/specflow.org" "control plane")))))
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

;;;; compose: Interactive Commands

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

;;;; initiate: Project Bootstrapping

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

(provide 'specflow)
;;; specflow.el ends here
