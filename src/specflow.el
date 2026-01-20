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

(defun specflow-bundle--format-output (project-state next-task parent-chain-content unit-content &optional timestamp)
  "Format the complete bundle output.
PROJECT-STATE is a plist with :phase and :active-unit.
NEXT-TASK is the extracted NEXT task string.
PARENT-CHAIN-CONTENT is a list of (name . sections-alist) for each ancestor.
UNIT-CONTENT is a (name . sections-alist) for the active unit.
TIMESTAMP is optional; if nil, current time is used."
  (let ((ts (or timestamp (format-time-string "%Y-%m-%dT%H:%M:%S"))))
    (with-temp-buffer
      ;; Header
      (insert (format "# SpecFlow Context Bundle\n# Generated: %s\n\n" ts))
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

(defun specflow-bundle-context (&optional unit-name)
  "Generate a context bundle for UNIT-NAME.
If UNIT-NAME is nil, uses the active unit from the control plane.
Returns a formatted string containing the complete context bundle."
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
    ;; Format and return
    (specflow-bundle--format-output project-state next-task parent-chain-content unit-content)))

(defun specflow-bundle-context-no-timestamp (&optional unit-name)
  "Like `specflow-bundle-context' but with fixed timestamp for testing."
  (let* ((cp-path (specflow-org-store-find-control-plane))
         (project-root (specflow-org-store--project-root-from-control-plane cp-path))
         (project-state (specflow-org-store-read-project-state cp-path))
         (active-unit (or unit-name (plist-get project-state :active-unit)))
         (unit-entry (specflow-org-store-read-unit active-unit cp-path))
         (parent-names (specflow-org-store-validate-parent-chain active-unit cp-path))
         (next-task (specflow-bundle--extract-next-task nil project-root))
         (parent-chain-content nil)
         (unit-content nil))
    (dolist (parent-name (reverse parent-names))
      (let ((parent-entry (specflow-org-store-read-unit parent-name cp-path)))
        (push (specflow-bundle--gather-unit-content parent-entry project-root)
              parent-chain-content)))
    (setq parent-chain-content (nreverse parent-chain-content))
    (setq unit-content (specflow-bundle--gather-unit-content unit-entry project-root))
    (specflow-bundle--format-output project-state next-task parent-chain-content unit-content
                                    "2025-01-01T00:00:00")))

;;;; bundle: Interactive Command

(defun specflow-bundle ()
  "Generate and display a context bundle for the active unit.
Copies the bundle to the kill-ring and displays it in a buffer."
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
    (message "SpecFlow bundle copied to kill-ring and displayed in *SpecFlow Bundle* buffer")))

(provide 'specflow)
;;; specflow.el ends here
