;;; test-specflow-org-store.el --- Tests for specflow org-store -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT tests for specflow-org-store functions.

;;; Code:

(require 'ert)
(require 'specflow-org-store)

;;;; Test Helpers

(defmacro specflow-test-with-temp-project (project-structure &rest body)
  "Create a temporary project with PROJECT-STRUCTURE and execute BODY.
PROJECT-STRUCTURE is a list of relative file paths to create.
Each path ending in / creates a directory, otherwise creates an empty file.
The macro binds `project-root' to the temporary directory."
  (declare (indent 1))
  `(let ((project-root (make-temp-file "specflow-test-" t)))
     (unwind-protect
         (progn
           ;; Create project structure
           (dolist (path ,project-structure)
             (let ((full-path (expand-file-name path project-root)))
               (if (string-suffix-p "/" path)
                   (make-directory full-path t)
                 (make-directory (file-name-directory full-path) t)
                 (write-region "" nil full-path))))
           ,@body)
       ;; Cleanup
       (delete-directory project-root t))))

;;;; Discovery Tests

(ert-deftest specflow-test-find-control-plane-at-root ()
  "Test finding control plane at project root."
  (specflow-test-with-temp-project
      '(".git/" "docs/specflow.org")
    (let ((expected (expand-file-name "docs/specflow.org" project-root)))
      (should (equal (specflow-org-store-find-control-plane project-root)
                     expected)))))

(ert-deftest specflow-test-find-control-plane-from-subdir ()
  "Test finding control plane when starting from a subdirectory."
  (specflow-test-with-temp-project
      '(".git/" "docs/specflow.org" "src/foo/bar/")
    (let ((start-dir (expand-file-name "src/foo/bar" project-root))
          (expected (expand-file-name "docs/specflow.org" project-root)))
      (should (equal (specflow-org-store-find-control-plane start-dir)
                     expected)))))

(ert-deftest specflow-test-find-control-plane-two-levels-up ()
  "Test finding control plane two directory levels up."
  (specflow-test-with-temp-project
      '(".git/" "docs/specflow.org" "units/org-store/")
    (let ((start-dir (expand-file-name "units/org-store" project-root))
          (expected (expand-file-name "docs/specflow.org" project-root)))
      (should (equal (specflow-org-store-find-control-plane start-dir)
                     expected)))))

(ert-deftest specflow-test-find-control-plane-stops-at-project-root ()
  "Test that search stops at project root even if control plane not found."
  (specflow-test-with-temp-project
      '(".git/" "src/")  ; No control plane
    (let ((specflow-control-plane-path nil))
      (should-error (specflow-org-store-find-control-plane project-root)
                    :type 'specflow-control-plane-not-found))))

(ert-deftest specflow-test-find-control-plane-fallback-variable ()
  "Test fallback to `specflow-control-plane-path' variable."
  (specflow-test-with-temp-project
      '(".git/" "src/")  ; No control plane in standard location
    ;; Create control plane in non-standard location
    (let* ((alt-path (expand-file-name "custom/control.org" project-root))
           (specflow-control-plane-path alt-path))
      (make-directory (file-name-directory alt-path) t)
      (write-region "" nil alt-path)
      (should (equal (specflow-org-store-find-control-plane project-root)
                     alt-path)))))

(ert-deftest specflow-test-find-control-plane-fallback-not-exists ()
  "Test error when fallback path does not exist."
  (specflow-test-with-temp-project
      '(".git/" "src/")
    (let ((specflow-control-plane-path "/nonexistent/path/specflow.org"))
      (should-error (specflow-org-store-find-control-plane project-root)
                    :type 'specflow-control-plane-not-found))))

(ert-deftest specflow-test-find-control-plane-not-found ()
  "Test error when control plane not found anywhere."
  (specflow-test-with-temp-project
      '(".git/" "src/")
    (let ((specflow-control-plane-path nil))
      (should-error (specflow-org-store-find-control-plane project-root)
                    :type 'specflow-control-plane-not-found))))

(ert-deftest specflow-test-find-control-plane-projectile-marker ()
  "Test that .projectile is recognized as project root marker."
  (specflow-test-with-temp-project
      '(".projectile" "docs/specflow.org")
    (let ((expected (expand-file-name "docs/specflow.org" project-root)))
      (should (equal (specflow-org-store-find-control-plane project-root)
                     expected)))))

(ert-deftest specflow-test-find-control-plane-specflow-root-marker ()
  "Test that .specflow-root is recognized as project root marker."
  (specflow-test-with-temp-project
      '(".specflow-root" "docs/specflow.org")
    (let ((expected (expand-file-name "docs/specflow.org" project-root)))
      (should (equal (specflow-org-store-find-control-plane project-root)
                     expected)))))

(ert-deftest specflow-test-find-control-plane-returns-absolute-path ()
  "Test that returned path is always absolute."
  (specflow-test-with-temp-project
      '(".git/" "docs/specflow.org")
    (let ((result (specflow-org-store-find-control-plane project-root)))
      (should (file-name-absolute-p result)))))

;;;; Determinism Tests (Discovery)

(ert-deftest specflow-test-find-control-plane-deterministic ()
  "Test that calling find-control-plane twice returns identical results."
  (specflow-test-with-temp-project
      '(".git/" "docs/specflow.org" "src/")
    (let ((start-dir (expand-file-name "src" project-root)))
      (should (equal (specflow-org-store-find-control-plane start-dir)
                     (specflow-org-store-find-control-plane start-dir))))))

;;;; Project State Tests

(defconst specflow-test-valid-control-plane
  "#+TITLE: Test Control Plane

* Project
  :PROPERTIES:
  :SPEC_FLOW_PHASE: Implement
  :SPEC_FLOW_ACTIVE_UNIT: org-store
  :END:

Some content here.

* Units

** org-store
   :PROPERTIES:
   :SPEC: units/org-store/spec.org
   :TODO: units/org-store/todo.org
   :RULES: units/org-store/CLAUDE.md
   :END:
"
  "Valid control plane content for testing.")

(defconst specflow-test-control-plane-missing-phase
  "#+TITLE: Test Control Plane

* Project
  :PROPERTIES:
  :SPEC_FLOW_ACTIVE_UNIT: org-store
  :END:
"
  "Control plane missing SPEC_FLOW_PHASE.")

(defconst specflow-test-control-plane-missing-active-unit
  "#+TITLE: Test Control Plane

* Project
  :PROPERTIES:
  :SPEC_FLOW_PHASE: Plan
  :END:
"
  "Control plane missing SPEC_FLOW_ACTIVE_UNIT.")

(defconst specflow-test-control-plane-no-project-heading
  "#+TITLE: Test Control Plane

* Units

** org-store
   :PROPERTIES:
   :SPEC: units/org-store/spec.org
   :END:
"
  "Control plane without Project heading.")

(ert-deftest specflow-test-read-project-state-valid ()
  "Test reading project state from a valid control plane."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-valid-control-plane nil cp-path)
      (let ((result (specflow-org-store-read-project-state cp-path)))
        (should (equal (plist-get result :phase) "Implement"))
        (should (equal (plist-get result :active-unit) "org-store"))
        (should (equal (plist-get result :control-plane-path) cp-path))))))

(ert-deftest specflow-test-read-project-state-discovers-control-plane ()
  "Test that read-project-state discovers control plane when path not given."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-valid-control-plane nil cp-path)
      (let ((default-directory project-root))
        (let ((result (specflow-org-store-read-project-state)))
          (should (equal (plist-get result :phase) "Implement"))
          (should (equal (plist-get result :active-unit) "org-store")))))))

(ert-deftest specflow-test-read-project-state-missing-phase ()
  "Test error when SPEC_FLOW_PHASE is missing."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-missing-phase nil cp-path)
      (should-error (specflow-org-store-read-project-state cp-path)
                    :type 'specflow-control-plane-malformed))))

(ert-deftest specflow-test-read-project-state-missing-active-unit ()
  "Test error when SPEC_FLOW_ACTIVE_UNIT is missing."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-missing-active-unit nil cp-path)
      (should-error (specflow-org-store-read-project-state cp-path)
                    :type 'specflow-control-plane-malformed))))

(ert-deftest specflow-test-read-project-state-no-project-heading ()
  "Test error when Project heading is missing."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-no-project-heading nil cp-path)
      (should-error (specflow-org-store-read-project-state cp-path)
                    :type 'specflow-control-plane-malformed))))

(ert-deftest specflow-test-read-project-state-deterministic ()
  "Test that reading project state twice returns identical results."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-valid-control-plane nil cp-path)
      (should (equal (specflow-org-store-read-project-state cp-path)
                     (specflow-org-store-read-project-state cp-path))))))

;;;; Unit Read Tests

(defconst specflow-test-control-plane-with-units
  "#+TITLE: Test Control Plane

* Project
  :PROPERTIES:
  :SPEC_FLOW_PHASE: Implement
  :SPEC_FLOW_ACTIVE_UNIT: org-store
  :END:

* Units

** core
   :PROPERTIES:
   :DIR: src/
   :SPEC: units/core/spec.org
   :TODO: units/core/todo.org
   :RULES: units/core/CLAUDE.md
   :CHILDREN: org-store bundle
   :END:

** org-store
   :PROPERTIES:
   :PARENT: core
   :DIR: src/
   :SPEC: units/org-store/spec.org
   :TODO: units/org-store/todo.org
   :RULES: units/org-store/CLAUDE.md
   :CONTEXT_REFS: docs/overview.org docs/architecture.org
   :END:

** minimal-unit
   :PROPERTIES:
   :SPEC: units/minimal/spec.org
   :TODO: units/minimal/todo.org
   :RULES: units/minimal/CLAUDE.md
   :END:
"
  "Control plane with multiple units for testing.")

(defconst specflow-test-control-plane-unit-missing-spec
  "#+TITLE: Test Control Plane

* Project
  :PROPERTIES:
  :SPEC_FLOW_PHASE: Plan
  :SPEC_FLOW_ACTIVE_UNIT: bad-unit
  :END:

* Units

** bad-unit
   :PROPERTIES:
   :TODO: units/bad/todo.org
   :RULES: units/bad/CLAUDE.md
   :END:
"
  "Control plane with unit missing SPEC property.")

(defconst specflow-test-control-plane-unit-missing-todo
  "#+TITLE: Test Control Plane

* Project
  :PROPERTIES:
  :SPEC_FLOW_PHASE: Plan
  :SPEC_FLOW_ACTIVE_UNIT: bad-unit
  :END:

* Units

** bad-unit
   :PROPERTIES:
   :SPEC: units/bad/spec.org
   :RULES: units/bad/CLAUDE.md
   :END:
"
  "Control plane with unit missing TODO property.")

(defconst specflow-test-control-plane-unit-missing-rules
  "#+TITLE: Test Control Plane

* Project
  :PROPERTIES:
  :SPEC_FLOW_PHASE: Plan
  :SPEC_FLOW_ACTIVE_UNIT: bad-unit
  :END:

* Units

** bad-unit
   :PROPERTIES:
   :SPEC: units/bad/spec.org
   :TODO: units/bad/todo.org
   :END:
"
  "Control plane with unit missing RULES property.")

(ert-deftest specflow-test-read-unit-valid ()
  "Test reading a valid unit with all properties."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-with-units nil cp-path)
      (let ((result (specflow-org-store-read-unit "org-store" cp-path)))
        (should (equal (plist-get result :name) "org-store"))
        (should (equal (plist-get result :dir) "src/"))
        (should (equal (plist-get result :spec) "units/org-store/spec.org"))
        (should (equal (plist-get result :todo) "units/org-store/todo.org"))
        (should (equal (plist-get result :rules) "units/org-store/CLAUDE.md"))
        (should (equal (plist-get result :parent) "core"))
        (should (equal (plist-get result :context-refs)
                       '("docs/overview.org" "docs/architecture.org")))))))

(ert-deftest specflow-test-read-unit-with-children ()
  "Test reading a unit with CHILDREN property."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-with-units nil cp-path)
      (let ((result (specflow-org-store-read-unit "core" cp-path)))
        (should (equal (plist-get result :name) "core"))
        (should (equal (plist-get result :children) '("org-store" "bundle")))
        (should (null (plist-get result :parent)))))))

(ert-deftest specflow-test-read-unit-minimal ()
  "Test reading a unit with only required properties."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-with-units nil cp-path)
      (let ((result (specflow-org-store-read-unit "minimal-unit" cp-path)))
        (should (equal (plist-get result :name) "minimal-unit"))
        (should (equal (plist-get result :spec) "units/minimal/spec.org"))
        (should (null (plist-get result :dir)))
        (should (null (plist-get result :parent)))
        (should (null (plist-get result :children)))
        (should (null (plist-get result :context-refs)))))))

(ert-deftest specflow-test-read-unit-not-found ()
  "Test error when unit does not exist."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-with-units nil cp-path)
      (should-error (specflow-org-store-read-unit "nonexistent-unit" cp-path)
                    :type 'specflow-unit-not-found))))

(ert-deftest specflow-test-read-unit-missing-spec ()
  "Test error when unit is missing SPEC property."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-unit-missing-spec nil cp-path)
      (should-error (specflow-org-store-read-unit "bad-unit" cp-path)
                    :type 'specflow-unit-malformed))))

(ert-deftest specflow-test-read-unit-missing-todo ()
  "Test error when unit is missing TODO property."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-unit-missing-todo nil cp-path)
      (should-error (specflow-org-store-read-unit "bad-unit" cp-path)
                    :type 'specflow-unit-malformed))))

(ert-deftest specflow-test-read-unit-missing-rules ()
  "Test error when unit is missing RULES property."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-unit-missing-rules nil cp-path)
      (should-error (specflow-org-store-read-unit "bad-unit" cp-path)
                    :type 'specflow-unit-malformed))))

(ert-deftest specflow-test-read-unit-deterministic ()
  "Test that reading a unit twice returns identical results."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-with-units nil cp-path)
      (should (equal (specflow-org-store-read-unit "org-store" cp-path)
                     (specflow-org-store-read-unit "org-store" cp-path))))))

;;;; Unit Registry Tests

(defconst specflow-test-control-plane-empty-registry
  "#+TITLE: Test Control Plane

* Project
  :PROPERTIES:
  :SPEC_FLOW_PHASE: Plan
  :SPEC_FLOW_ACTIVE_UNIT: none
  :END:

* Units

"
  "Control plane with empty unit registry.")

(defconst specflow-test-control-plane-multi-unit
  "#+TITLE: Test Control Plane

* Project
  :PROPERTIES:
  :SPEC_FLOW_PHASE: Implement
  :SPEC_FLOW_ACTIVE_UNIT: org-store
  :END:

* Units

** org-store
   :PROPERTIES:
   :SPEC: units/org-store/spec.org
   :TODO: units/org-store/todo.org
   :RULES: units/org-store/CLAUDE.md
   :END:

** bundle
   :PROPERTIES:
   :SPEC: units/bundle/spec.org
   :TODO: units/bundle/todo.org
   :RULES: units/bundle/CLAUDE.md
   :END:
"
  "Control plane with multiple units for phase-shift tests.")

(ert-deftest specflow-test-read-unit-registry-multiple-units ()
  "Test reading registry with multiple units in document order."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-with-units nil cp-path)
      (let ((result (specflow-org-store-read-unit-registry cp-path)))
        ;; Should have 3 units
        (should (= (length result) 3))
        ;; Should be in document order: core, org-store, minimal-unit
        (should (equal (plist-get (nth 0 result) :name) "core"))
        (should (equal (plist-get (nth 1 result) :name) "org-store"))
        (should (equal (plist-get (nth 2 result) :name) "minimal-unit"))))))

(ert-deftest specflow-test-read-unit-registry-empty ()
  "Test reading empty unit registry returns empty list."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-empty-registry nil cp-path)
      (let ((result (specflow-org-store-read-unit-registry cp-path)))
        (should (null result))))))

(ert-deftest specflow-test-read-unit-registry-validates-units ()
  "Test that registry read validates each unit's required properties."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-unit-missing-spec nil cp-path)
      (should-error (specflow-org-store-read-unit-registry cp-path)
                    :type 'specflow-unit-malformed))))

(ert-deftest specflow-test-read-unit-registry-deterministic ()
  "Test that reading registry twice returns identical results."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-with-units nil cp-path)
      (should (equal (specflow-org-store-read-unit-registry cp-path)
                     (specflow-org-store-read-unit-registry cp-path))))))

(ert-deftest specflow-test-read-unit-registry-each-unit-complete ()
  "Test that each unit in registry has all expected properties."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-with-units nil cp-path)
      (let ((result (specflow-org-store-read-unit-registry cp-path)))
        ;; Check org-store unit has all properties
        (let ((org-store (nth 1 result)))
          (should (equal (plist-get org-store :name) "org-store"))
          (should (equal (plist-get org-store :parent) "core"))
          (should (equal (plist-get org-store :spec) "units/org-store/spec.org"))
          (should (equal (plist-get org-store :context-refs)
                         '("docs/overview.org" "docs/architecture.org"))))))))

;;;; Write Property Tests

(defconst specflow-test-file-with-drawer
  "#+TITLE: Test File

* Project
  :PROPERTIES:
  :SPEC_FLOW_PHASE: Plan
  :SPEC_FLOW_ACTIVE_UNIT: core
  :END:

Some content here.
"
  "File with existing property drawer.")

(defconst specflow-test-file-without-drawer
  "#+TITLE: Test File

* Project

Some content here.
"
  "File without property drawer.")

(defconst specflow-test-file-nested-heading
  "#+TITLE: Test File

* Units

** org-store
   :PROPERTIES:
   :SPEC: units/org-store/spec.org
   :END:

Content under org-store.
"
  "File with nested heading.")

(ert-deftest specflow-test-write-property-replace-existing ()
  "Test replacing an existing property value."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((file-path (expand-file-name "docs/test.org" project-root)))
      (write-region specflow-test-file-with-drawer nil file-path)
      ;; Write new value
      (should (specflow-org-store-write-property
               file-path '("Project") "SPEC_FLOW_PHASE" "Implement"))
      ;; Verify by reading file
      (with-temp-buffer
        (insert-file-contents file-path)
        (should (search-forward "SPEC_FLOW_PHASE: Implement" nil t))))))

(ert-deftest specflow-test-write-property-add-to-drawer ()
  "Test adding a new property to existing drawer."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((file-path (expand-file-name "docs/test.org" project-root)))
      (write-region specflow-test-file-with-drawer nil file-path)
      ;; Write new property
      (should (specflow-org-store-write-property
               file-path '("Project") "NEW_PROPERTY" "new-value"))
      ;; Verify by reading file
      (with-temp-buffer
        (insert-file-contents file-path)
        (should (search-forward "NEW_PROPERTY: new-value" nil t))
        ;; Original properties should still exist
        (goto-char (point-min))
        (should (search-forward "SPEC_FLOW_PHASE: Plan" nil t))))))

(ert-deftest specflow-test-write-property-create-drawer ()
  "Test creating property drawer when none exists."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((file-path (expand-file-name "docs/test.org" project-root)))
      (write-region specflow-test-file-without-drawer nil file-path)
      ;; Write property - should create drawer
      (should (specflow-org-store-write-property
               file-path '("Project") "NEW_PROP" "value"))
      ;; Verify drawer was created
      (with-temp-buffer
        (insert-file-contents file-path)
        (should (search-forward ":PROPERTIES:" nil t))
        (should (search-forward "NEW_PROP: value" nil t))
        (should (search-forward ":END:" nil t))))))

(ert-deftest specflow-test-write-property-nested-heading ()
  "Test writing property to nested heading."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((file-path (expand-file-name "docs/test.org" project-root)))
      (write-region specflow-test-file-nested-heading nil file-path)
      ;; Write to nested heading
      (should (specflow-org-store-write-property
               file-path '("Units" "org-store") "SPEC" "new/path/spec.org"))
      ;; Verify
      (with-temp-buffer
        (insert-file-contents file-path)
        (should (search-forward "SPEC: new/path/spec.org" nil t))))))

(ert-deftest specflow-test-write-property-heading-not-found ()
  "Test error when heading path is invalid."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((file-path (expand-file-name "docs/test.org" project-root)))
      (write-region specflow-test-file-with-drawer nil file-path)
      (should-error (specflow-org-store-write-property
                     file-path '("NonExistent") "PROP" "value")
                    :type 'specflow-heading-not-found))))

(ert-deftest specflow-test-write-property-nested-heading-not-found ()
  "Test error when nested heading path is invalid."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((file-path (expand-file-name "docs/test.org" project-root)))
      (write-region specflow-test-file-nested-heading nil file-path)
      (should-error (specflow-org-store-write-property
                     file-path '("Units" "nonexistent") "PROP" "value")
                    :type 'specflow-heading-not-found))))

(ert-deftest specflow-test-write-property-minimal-diff ()
  "Test that only the property line changes (minimal diff)."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((file-path (expand-file-name "docs/test.org" project-root)))
      (write-region specflow-test-file-with-drawer nil file-path)
      ;; Get original content
      (let ((original-content (with-temp-buffer
                                (insert-file-contents file-path)
                                (buffer-string))))
        ;; Write property
        (specflow-org-store-write-property
         file-path '("Project") "SPEC_FLOW_PHASE" "Implement")
        ;; Get new content
        (let ((new-content (with-temp-buffer
                             (insert-file-contents file-path)
                             (buffer-string))))
          ;; Content before :PROPERTIES: should be unchanged
          (should (string-prefix-p "#+TITLE: Test File\n\n* Project\n"
                                   new-content))
          ;; Content after :END: should be unchanged
          (should (string-suffix-p "Some content here.\n" new-content)))))))

(ert-deftest specflow-test-write-then-read-property ()
  "Test that write followed by read returns the written value."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((file-path (expand-file-name "docs/test.org" project-root)))
      (write-region specflow-test-valid-control-plane nil file-path)
      ;; Write new phase
      (specflow-org-store-write-property
       file-path '("Project") "SPEC_FLOW_PHASE" "Validate")
      ;; Read and verify
      (let ((state (specflow-org-store-read-project-state file-path)))
        (should (equal (plist-get state :phase) "Validate"))))))

(ert-deftest specflow-test-write-property-idempotent ()
  "Test that writing same value twice produces same file."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((file-path (expand-file-name "docs/test.org" project-root)))
      (write-region specflow-test-file-with-drawer nil file-path)
      ;; Write once
      (specflow-org-store-write-property
       file-path '("Project") "SPEC_FLOW_PHASE" "NewValue")
      (let ((content-after-first (with-temp-buffer
                                   (insert-file-contents file-path)
                                   (buffer-string))))
        ;; Write same value again
        (specflow-org-store-write-property
         file-path '("Project") "SPEC_FLOW_PHASE" "NewValue")
        (let ((content-after-second (with-temp-buffer
                                      (insert-file-contents file-path)
                                      (buffer-string))))
          ;; Files should be identical
          (should (equal content-after-first content-after-second)))))))

;;;; Validation Tests - Unit Pointers

(ert-deftest specflow-test-validate-unit-pointers-valid ()
  "Test validation passes when all required files exist."
  (specflow-test-with-temp-project
      '(".git/"
        "docs/specflow.org"
        "units/org-store/spec.org"
        "units/org-store/todo.org"
        "units/org-store/CLAUDE.md")
    (let ((unit-entry (list :name "org-store"
                            :spec "units/org-store/spec.org"
                            :todo "units/org-store/todo.org"
                            :rules "units/org-store/CLAUDE.md")))
      (should (eq t (specflow-org-store-validate-unit-pointers
                     unit-entry project-root))))))

(ert-deftest specflow-test-validate-unit-pointers-missing-spec ()
  "Test validation fails when SPEC file is missing."
  (specflow-test-with-temp-project
      '(".git/"
        "docs/specflow.org"
        "units/org-store/todo.org"
        "units/org-store/CLAUDE.md")
    (let ((unit-entry (list :name "org-store"
                            :spec "units/org-store/spec.org"
                            :todo "units/org-store/todo.org"
                            :rules "units/org-store/CLAUDE.md")))
      (should-error (specflow-org-store-validate-unit-pointers
                     unit-entry project-root)
                    :type 'specflow-unit-pointer-invalid))))

(ert-deftest specflow-test-validate-unit-pointers-missing-todo ()
  "Test validation fails when TODO file is missing."
  (specflow-test-with-temp-project
      '(".git/"
        "docs/specflow.org"
        "units/org-store/spec.org"
        "units/org-store/CLAUDE.md")
    (let ((unit-entry (list :name "org-store"
                            :spec "units/org-store/spec.org"
                            :todo "units/org-store/todo.org"
                            :rules "units/org-store/CLAUDE.md")))
      (should-error (specflow-org-store-validate-unit-pointers
                     unit-entry project-root)
                    :type 'specflow-unit-pointer-invalid))))

(ert-deftest specflow-test-validate-unit-pointers-missing-rules ()
  "Test validation fails when RULES file is missing."
  (specflow-test-with-temp-project
      '(".git/"
        "docs/specflow.org"
        "units/org-store/spec.org"
        "units/org-store/todo.org")
    (let ((unit-entry (list :name "org-store"
                            :spec "units/org-store/spec.org"
                            :todo "units/org-store/todo.org"
                            :rules "units/org-store/CLAUDE.md")))
      (should-error (specflow-org-store-validate-unit-pointers
                     unit-entry project-root)
                    :type 'specflow-unit-pointer-invalid))))

(ert-deftest specflow-test-validate-unit-pointers-multiple-missing ()
  "Test error message lists all missing files."
  (specflow-test-with-temp-project
      '(".git/"
        "docs/specflow.org")
    (let ((unit-entry (list :name "org-store"
                            :spec "units/org-store/spec.org"
                            :todo "units/org-store/todo.org"
                            :rules "units/org-store/CLAUDE.md")))
      (condition-case err
          (progn
            (specflow-org-store-validate-unit-pointers unit-entry project-root)
            (should nil))  ; Should not reach here
        (specflow-unit-pointer-invalid
         ;; Error message should mention all three missing files
         (let ((msg (cadr err)))
           (should (string-match-p ":spec=" msg))
           (should (string-match-p ":todo=" msg))
           (should (string-match-p ":rules=" msg))))))))

(ert-deftest specflow-test-validate-unit-pointers-nil-path ()
  "Test validation fails when path is nil."
  (specflow-test-with-temp-project
      '(".git/"
        "docs/specflow.org"
        "units/org-store/spec.org"
        "units/org-store/todo.org")
    (let ((unit-entry (list :name "org-store"
                            :spec "units/org-store/spec.org"
                            :todo "units/org-store/todo.org"
                            :rules nil)))  ; nil rules path
      (should-error (specflow-org-store-validate-unit-pointers
                     unit-entry project-root)
                    :type 'specflow-unit-pointer-invalid))))

(ert-deftest specflow-test-validate-unit-pointers-discovers-root ()
  "Test validation discovers project root from control plane."
  (specflow-test-with-temp-project
      '(".git/"
        "docs/specflow.org"
        "units/org-store/spec.org"
        "units/org-store/todo.org"
        "units/org-store/CLAUDE.md")
    (let ((unit-entry (list :name "org-store"
                            :spec "units/org-store/spec.org"
                            :todo "units/org-store/todo.org"
                            :rules "units/org-store/CLAUDE.md"))
          (default-directory project-root))
      ;; Don't pass project-root explicitly - should discover it
      (should (eq t (specflow-org-store-validate-unit-pointers unit-entry))))))

;;;; Validation Tests - Parent Chain

(defconst specflow-test-control-plane-with-hierarchy
  "#+TITLE: Test Control Plane

* Project
  :PROPERTIES:
  :SPEC_FLOW_PHASE: Implement
  :SPEC_FLOW_ACTIVE_UNIT: org-store
  :END:

* Units

** root
   :PROPERTIES:
   :SPEC: units/root/spec.org
   :TODO: units/root/todo.org
   :RULES: units/root/CLAUDE.md
   :CHILDREN: core
   :END:

** core
   :PROPERTIES:
   :PARENT: root
   :SPEC: units/core/spec.org
   :TODO: units/core/todo.org
   :RULES: units/core/CLAUDE.md
   :CHILDREN: org-store
   :END:

** org-store
   :PROPERTIES:
   :PARENT: core
   :SPEC: units/org-store/spec.org
   :TODO: units/org-store/todo.org
   :RULES: units/org-store/CLAUDE.md
   :END:
"
  "Control plane with multi-level hierarchy: root -> core -> org-store.")

(defconst specflow-test-control-plane-missing-parent
  "#+TITLE: Test Control Plane

* Project
  :PROPERTIES:
  :SPEC_FLOW_PHASE: Implement
  :SPEC_FLOW_ACTIVE_UNIT: org-store
  :END:

* Units

** org-store
   :PROPERTIES:
   :PARENT: nonexistent-unit
   :SPEC: units/org-store/spec.org
   :TODO: units/org-store/todo.org
   :RULES: units/org-store/CLAUDE.md
   :END:
"
  "Control plane where unit references nonexistent parent.")

(defconst specflow-test-control-plane-circular-parent
  "#+TITLE: Test Control Plane

* Project
  :PROPERTIES:
  :SPEC_FLOW_PHASE: Implement
  :SPEC_FLOW_ACTIVE_UNIT: unit-a
  :END:

* Units

** unit-a
   :PROPERTIES:
   :PARENT: unit-b
   :SPEC: units/a/spec.org
   :TODO: units/a/todo.org
   :RULES: units/a/CLAUDE.md
   :END:

** unit-b
   :PROPERTIES:
   :PARENT: unit-a
   :SPEC: units/b/spec.org
   :TODO: units/b/todo.org
   :RULES: units/b/CLAUDE.md
   :END:
"
  "Control plane with circular parent reference.")

(ert-deftest specflow-test-validate-parent-chain-no-parent ()
  "Test that unit with no parent returns empty list."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-with-hierarchy nil cp-path)
      ;; root has no parent
      (should (equal '() (specflow-org-store-validate-parent-chain "root" cp-path))))))

(ert-deftest specflow-test-validate-parent-chain-single-parent ()
  "Test that unit with one parent returns single-element list."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-with-hierarchy nil cp-path)
      ;; core has parent root
      (should (equal '("root") (specflow-org-store-validate-parent-chain "core" cp-path))))))

(ert-deftest specflow-test-validate-parent-chain-multi-level ()
  "Test that multi-level hierarchy returns correct ancestor list."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-with-hierarchy nil cp-path)
      ;; org-store -> core -> root
      (should (equal '("core" "root")
                     (specflow-org-store-validate-parent-chain "org-store" cp-path))))))

(ert-deftest specflow-test-validate-parent-chain-missing-parent ()
  "Test error when parent unit does not exist."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-missing-parent nil cp-path)
      (should-error (specflow-org-store-validate-parent-chain "org-store" cp-path)
                    :type 'specflow-parent-not-found))))

(ert-deftest specflow-test-validate-parent-chain-unit-not-found ()
  "Test error when unit itself does not exist."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-with-hierarchy nil cp-path)
      (should-error (specflow-org-store-validate-parent-chain "nonexistent" cp-path)
                    :type 'specflow-unit-not-found))))

(ert-deftest specflow-test-validate-parent-chain-circular ()
  "Test error when circular parent reference detected."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-circular-parent nil cp-path)
      (should-error (specflow-org-store-validate-parent-chain "unit-a" cp-path)
                    :type 'specflow-parent-not-found))))

(ert-deftest specflow-test-validate-parent-chain-deterministic ()
  "Test that calling validate-parent-chain twice returns identical results."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-with-hierarchy nil cp-path)
      (should (equal (specflow-org-store-validate-parent-chain "org-store" cp-path)
                     (specflow-org-store-validate-parent-chain "org-store" cp-path))))))

;;;; Workflow Command Tests - specflow-phase-shift

(ert-deftest specflow-test-phase-shift-changes-both ()
  "Test that phase-shift successfully changes both phase and unit."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-multi-unit nil cp-path)
      (let ((default-directory project-root))
        ;; Change both phase and unit
        (should (specflow-phase-shift "Validate" "bundle"))
        ;; Verify both changed
        (let ((state (specflow-org-store-read-project-state cp-path)))
          (should (equal (plist-get state :phase) "Validate"))
          (should (equal (plist-get state :active-unit) "bundle")))))))

(ert-deftest specflow-test-phase-shift-changes-phase-only ()
  "Test that phase-shift can change only phase (keep unit)."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-valid-control-plane nil cp-path)
      (let ((default-directory project-root))
        ;; Change phase, keep unit
        (should (specflow-phase-shift "Validate" "org-store"))
        ;; Verify phase changed, unit unchanged
        (let ((state (specflow-org-store-read-project-state cp-path)))
          (should (equal (plist-get state :phase) "Validate"))
          (should (equal (plist-get state :active-unit) "org-store")))))))

(ert-deftest specflow-test-phase-shift-changes-unit-only ()
  "Test that phase-shift can change only unit (keep phase)."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-multi-unit nil cp-path)
      (let ((default-directory project-root))
        ;; Change unit, keep phase (Implement)
        (should (specflow-phase-shift "Implement" "bundle"))
        ;; Verify unit changed, phase unchanged
        (let ((state (specflow-org-store-read-project-state cp-path)))
          (should (equal (plist-get state :phase) "Implement"))
          (should (equal (plist-get state :active-unit) "bundle")))))))

(ert-deftest specflow-test-phase-shift-all-valid-phases ()
  "Test that all valid phases can be set."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-valid-control-plane nil cp-path)
      (let ((default-directory project-root))
        (dolist (phase specflow-valid-phases)
          (specflow-phase-shift phase "org-store")
          (let ((state (specflow-org-store-read-project-state cp-path)))
            (should (equal (plist-get state :phase) phase))))))))

(ert-deftest specflow-test-phase-shift-rejects-invalid-phase ()
  "Test that invalid phase is rejected with user-error."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-valid-control-plane nil cp-path)
      (let ((default-directory project-root))
        (should-error (specflow-phase-shift "InvalidPhase" "org-store")
                      :type 'user-error)))))

(ert-deftest specflow-test-phase-shift-rejects-invalid-unit ()
  "Test that invalid unit is rejected with user-error."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-valid-control-plane nil cp-path)
      (let ((default-directory project-root))
        (should-error (specflow-phase-shift "Implement" "nonexistent-unit")
                      :type 'user-error)))))

(ert-deftest specflow-test-phase-shift-displays-message ()
  "Test that phase-shift displays confirmation message with both values."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root))
          (messages nil))
      (write-region specflow-test-valid-control-plane nil cp-path)
      (let ((default-directory project-root))
        ;; Capture messages
        (cl-letf (((symbol-function 'message)
                   (lambda (fmt &rest args)
                     (push (apply #'format fmt args) messages))))
          (specflow-phase-shift "Document" "org-store"))
        ;; Check message includes both phase and unit
        (should (member "Phase: Document, Unit: org-store" messages))))))

(ert-deftest specflow-test-phase-shift-writes-both-properties ()
  "Test that phase-shift writes both properties to control plane."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root)))
      (write-region specflow-test-control-plane-multi-unit nil cp-path)
      (let ((default-directory project-root))
        (specflow-phase-shift "Scaffold" "bundle")
        ;; Verify file was updated correctly
        (with-temp-buffer
          (insert-file-contents cp-path)
          ;; Should have new phase
          (should (search-forward "SPEC_FLOW_PHASE: Scaffold" nil t))
          ;; Should have new unit
          (goto-char (point-min))
          (should (search-forward "SPEC_FLOW_ACTIVE_UNIT: bundle" nil t)))))))

;;;; Workflow Command Tests - specflow-add-root-task

(defconst specflow-test-todo-org
  "#+TITLE: Test TODO
#+STARTUP: overview

* Active

** NEXT First task
   Some description.

* Backlog

** TODO Future task
"
  "Test todo.org with Active section.")

(defconst specflow-test-todo-org-no-active
  "#+TITLE: Test TODO

* Backlog

** TODO Future task
"
  "Test todo.org without Active section.")

(defconst specflow-test-todo-org-no-backlog
  "#+TITLE: Test TODO

* Active

** NEXT First task
   Some description.
"
  "Test todo.org without Backlog section.")

(ert-deftest specflow-test-add-root-task-adds-task ()
  "Test that add-root-task adds a task to Backlog section."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root))
          (todo-path (expand-file-name "todo.org" project-root)))
      (write-region specflow-test-valid-control-plane nil cp-path)
      (write-region specflow-test-todo-org nil todo-path)
      (let ((default-directory project-root))
        ;; Add task
        (should (specflow-add-root-task "New test task"))
        ;; Verify task was added
        (with-temp-buffer
          (insert-file-contents todo-path)
          (should (search-forward "** TODO New test task" nil t)))))))

(ert-deftest specflow-test-add-root-task-creates-todo-not-next ()
  "Test that new tasks are TODO, not NEXT."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root))
          (todo-path (expand-file-name "todo.org" project-root)))
      (write-region specflow-test-valid-control-plane nil cp-path)
      (write-region specflow-test-todo-org nil todo-path)
      (let ((default-directory project-root))
        (specflow-add-root-task "Another task")
        (with-temp-buffer
          (insert-file-contents todo-path)
          ;; Should have TODO, not NEXT
          (should (search-forward "** TODO Another task" nil t))
          ;; Should not create as NEXT
          (goto-char (point-min))
          (should-not (search-forward "** NEXT Another task" nil t)))))))

(ert-deftest specflow-test-add-root-task-inserts-in-backlog-section ()
  "Test that task is inserted at end of Backlog section."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root))
          (todo-path (expand-file-name "todo.org" project-root)))
      (write-region specflow-test-valid-control-plane nil cp-path)
      (write-region specflow-test-todo-org nil todo-path)
      (let ((default-directory project-root))
        (specflow-add-root-task "End of backlog task")
        (with-temp-buffer
          (insert-file-contents todo-path)
          ;; Task should appear after Backlog heading
          (let ((backlog-pos (progn (search-forward "* Backlog" nil t) (point)))
                (task-pos (progn (search-forward "End of backlog task" nil t) (point))))
            (should (> task-pos backlog-pos))))))))

(ert-deftest specflow-test-add-root-task-missing-backlog-heading ()
  "Test error when Backlog heading not found."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root))
          (todo-path (expand-file-name "todo.org" project-root)))
      (write-region specflow-test-valid-control-plane nil cp-path)
      (write-region specflow-test-todo-org-no-backlog nil todo-path)
      (let ((default-directory project-root))
        (should-error (specflow-add-root-task "Orphan task")
                      :type 'specflow-heading-not-found)))))

(ert-deftest specflow-test-add-root-task-displays-message ()
  "Test that add-root-task displays confirmation message."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root))
          (todo-path (expand-file-name "todo.org" project-root))
          (messages nil))
      (write-region specflow-test-valid-control-plane nil cp-path)
      (write-region specflow-test-todo-org nil todo-path)
      (let ((default-directory project-root))
        (cl-letf (((symbol-function 'message)
                   (lambda (fmt &rest args)
                     (push (apply #'format fmt args) messages))))
          (specflow-add-root-task "Message test task"))
        (should (member "Task added: Message test task" messages))))))

(ert-deftest specflow-test-add-root-task-minimal-diff ()
  "Test that only the new task is added (minimal diff)."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root))
          (todo-path (expand-file-name "todo.org" project-root)))
      (write-region specflow-test-valid-control-plane nil cp-path)
      (write-region specflow-test-todo-org nil todo-path)
      (let ((default-directory project-root))
        (specflow-add-root-task "Minimal diff task")
        (with-temp-buffer
          (insert-file-contents todo-path)
          ;; Original content should be preserved
          (should (search-forward "** NEXT First task" nil t))
          (goto-char (point-min))
          (should (search-forward "Some description." nil t))
          (goto-char (point-min))
          (should (search-forward "* Backlog" nil t))
          (goto-char (point-min))
          (should (search-forward "** TODO Future task" nil t)))))))

(ert-deftest specflow-test-add-root-task-multiple-tasks ()
  "Test adding multiple tasks sequentially."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root))
          (todo-path (expand-file-name "todo.org" project-root)))
      (write-region specflow-test-valid-control-plane nil cp-path)
      (write-region specflow-test-todo-org nil todo-path)
      (let ((default-directory project-root))
        (specflow-add-root-task "Task one")
        (specflow-add-root-task "Task two")
        (specflow-add-root-task "Task three")
        (with-temp-buffer
          (insert-file-contents todo-path)
          ;; All three tasks should be present
          (should (search-forward "** TODO Task one" nil t))
          (should (search-forward "** TODO Task two" nil t))
          (should (search-forward "** TODO Task three" nil t)))))))

;;;; Task Management Command Tests - specflow-refine-task

(defconst specflow-test-todo-with-backlog
  "#+TITLE: Test TODO

* Active

** NEXT Current active task
   Working on this now.

* Backlog (future enhancements)

** TODO First backlog task
   Description of first task.
   - bullet point one
   - bullet point two

** TODO Second backlog task
   Another task description.

** TODO Third task without body

* Completed

** DONE Old completed task
"
  "Test todo.org with Active and Backlog sections.")

(defconst specflow-test-todo-no-backlog
  "#+TITLE: Test TODO

* Active

** NEXT Current task

* Completed
"
  "Test todo.org without Backlog section.")

(ert-deftest specflow-test-parse-backlog-tasks ()
  "Test parsing backlog tasks from todo.org."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((todo-path (expand-file-name "todo.org" project-root)))
      (write-region specflow-test-todo-with-backlog nil todo-path)
      (let ((tasks (specflow-org-store--parse-backlog-tasks todo-path)))
        ;; Should have 3 tasks
        (should (= (length tasks) 3))
        ;; Check first task
        (should (equal (car (nth 0 tasks)) "First backlog task"))
        (should (string-match-p "bullet point one" (cdr (nth 0 tasks))))
        ;; Check second task
        (should (equal (car (nth 1 tasks)) "Second backlog task"))
        ;; Check third task (no body)
        (should (equal (car (nth 2 tasks)) "Third task without body"))))))

(ert-deftest specflow-test-parse-backlog-tasks-missing-backlog ()
  "Test error when Backlog section missing."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((todo-path (expand-file-name "todo.org" project-root)))
      (write-region specflow-test-todo-no-backlog nil todo-path)
      (should-error (specflow-org-store--parse-backlog-tasks todo-path)
                    :type 'specflow-heading-not-found))))

(ert-deftest specflow-test-format-refine-prompt ()
  "Test prompt formatting."
  (let ((prompt (specflow-org-store--format-refine-prompt
                 "Test task headline"
                 "Task body here"
                 "org-store"
                 "Some user context")))
    ;; Check structure
    (should (string-match-p "## Task to Refine" prompt))
    (should (string-match-p "Test task headline" prompt))
    (should (string-match-p "Task body here" prompt))
    (should (string-match-p "Related unit: org-store" prompt))
    (should (string-match-p "Notes: Some user context" prompt))
    (should (string-match-p "## Guidelines" prompt))
    ;; Check edit instruction ending
    (should (string-match-p "Refine this task and update it in the root todo.org file" prompt))))

(ert-deftest specflow-test-format-refine-prompt-empty-unit ()
  "Test prompt formatting with empty unit."
  (let ((prompt (specflow-org-store--format-refine-prompt
                 "Test task"
                 ""
                 ""
                 "")))
    (should (string-match-p "Related unit: Not specified" prompt))
    (should (string-match-p "Notes: None" prompt))))

(ert-deftest specflow-test-refine-task-copies-to-kill-ring ()
  "Test that refine-task copies prompt to kill-ring."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root))
          (todo-path (expand-file-name "todo.org" project-root)))
      (write-region specflow-test-valid-control-plane nil cp-path)
      (write-region specflow-test-todo-with-backlog nil todo-path)
      (let ((default-directory project-root))
        ;; Mock completing-read and read-string
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (&rest _) "First backlog task"))
                  ((symbol-function 'read-string)
                   (lambda (prompt &rest _)
                     (if (string-match-p "unit" prompt) "test-unit" "test context"))))
          (specflow-refine-task)
          ;; Check kill-ring
          (should (string-match-p "First backlog task" (car kill-ring)))
          (should (string-match-p "test-unit" (car kill-ring)))
          (should (string-match-p "test context" (car kill-ring))))))))

(ert-deftest specflow-test-refine-task-does-not-modify-file ()
  "Test that refine-task does NOT modify todo.org."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root))
          (todo-path (expand-file-name "todo.org" project-root)))
      (write-region specflow-test-valid-control-plane nil cp-path)
      (write-region specflow-test-todo-with-backlog nil todo-path)
      (let ((default-directory project-root)
            (original-content specflow-test-todo-with-backlog))
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (&rest _) "First backlog task"))
                  ((symbol-function 'read-string)
                   (lambda (&rest _) "")))
          (specflow-refine-task)
          ;; File should be unchanged
          (let ((content (with-temp-buffer
                           (insert-file-contents todo-path)
                           (buffer-string))))
            (should (equal original-content content))))))))

(ert-deftest specflow-test-refine-task-displays-message ()
  "Test that refine-task displays 'Task prompt copied' message."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root))
          (todo-path (expand-file-name "todo.org" project-root))
          (messages nil))
      (write-region specflow-test-valid-control-plane nil cp-path)
      (write-region specflow-test-todo-with-backlog nil todo-path)
      (let ((default-directory project-root))
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (&rest _) "First backlog task"))
                  ((symbol-function 'read-string)
                   (lambda (&rest _) ""))
                  ((symbol-function 'message)
                   (lambda (fmt &rest args)
                     (push (apply #'format fmt args) messages))))
          (specflow-refine-task)
          (should (member "Task prompt copied to kill-ring" messages)))))))

;;;; Task Management Command Tests - specflow-activate-task

(ert-deftest specflow-test-activate-task-copies-to-kill-ring ()
  "Test that activate-task copies prompt to kill-ring."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root))
          (todo-path (expand-file-name "todo.org" project-root)))
      (write-region specflow-test-valid-control-plane nil cp-path)
      (write-region specflow-test-todo-with-backlog nil todo-path)
      (let ((default-directory project-root))
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (&rest _) "First backlog task"))
                  ((symbol-function 'read-string)
                   (lambda (&rest _) "my context")))
          (specflow-activate-task)
          (should (string-match-p "First backlog task" (car kill-ring)))
          (should (string-match-p "my context" (car kill-ring))))))))

(ert-deftest specflow-test-activate-task-does-not-modify-file ()
  "Test that activate-task does NOT modify todo.org."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root))
          (todo-path (expand-file-name "todo.org" project-root)))
      (write-region specflow-test-valid-control-plane nil cp-path)
      (write-region specflow-test-todo-with-backlog nil todo-path)
      (let ((default-directory project-root)
            (original-content specflow-test-todo-with-backlog))
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (&rest _) "First backlog task"))
                  ((symbol-function 'read-string)
                   (lambda (&rest _) "")))
          (specflow-activate-task)
          ;; File should be unchanged
          (let ((content (with-temp-buffer
                           (insert-file-contents todo-path)
                           (buffer-string))))
            (should (equal original-content content))))))))

(ert-deftest specflow-test-activate-task-displays-message ()
  "Test that activate-task displays 'Task prompt copied' message."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root))
          (todo-path (expand-file-name "todo.org" project-root))
          (messages nil))
      (write-region specflow-test-valid-control-plane nil cp-path)
      (write-region specflow-test-todo-with-backlog nil todo-path)
      (let ((default-directory project-root))
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (&rest _) "First backlog task"))
                  ((symbol-function 'read-string)
                   (lambda (&rest _) ""))
                  ((symbol-function 'message)
                   (lambda (fmt &rest args)
                     (push (apply #'format fmt args) messages))))
          (specflow-activate-task)
          (should (member "Task prompt copied to kill-ring" messages)))))))

(ert-deftest specflow-test-activate-task-prompt-contains-activation-instructions ()
  "Test that activate-task prompt contains activation instructions."
  (specflow-test-with-temp-project
      '(".git/" "docs/")
    (let ((cp-path (expand-file-name "docs/specflow.org" project-root))
          (todo-path (expand-file-name "todo.org" project-root)))
      (write-region specflow-test-valid-control-plane nil cp-path)
      (write-region specflow-test-todo-with-backlog nil todo-path)
      (let ((default-directory project-root))
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (&rest _) "First backlog task"))
                  ((symbol-function 'read-string)
                   (lambda (&rest _) "")))
          (specflow-activate-task)
          ;; Verify prompt contains base edit instruction
          (should (string-match-p
                   "Refine this task and update it in the root todo.org file"
                   (car kill-ring)))
          ;; Verify prompt contains activation-specific instructions
          (should (string-match-p
                   "move this task from Backlog to Active section as NEXT"
                   (car kill-ring)))
          (should (string-match-p
                   "demote it to TODO"
                   (car kill-ring))))))))

(provide 'test-specflow-org-store)
;;; test-specflow-org-store.el ends here
