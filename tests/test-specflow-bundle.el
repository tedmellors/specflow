;;; test-specflow-bundle.el --- Tests for specflow bundle -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT tests for specflow-bundle functions.

;;; Code:

(require 'ert)
(require 'specflow)

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

(defmacro specflow-test-with-bundle-project (&rest body)
  "Create a complete bundle test project and execute BODY.
Sets up control plane, units, and files for bundle testing."
  (declare (indent 0))
  `(specflow-test-with-temp-project
       '(".git/"
         "docs/"
         "units/core/"
         "units/bundle/")
     ;; Write control plane
     (write-region
      "#+TITLE: Test Control Plane

* Project
  :PROPERTIES:
  :SPEC_FLOW_PHASE: Implement
  :SPEC_FLOW_ACTIVE_UNIT: bundle
  :END:

* Units

** core
   :PROPERTIES:
   :SPEC: units/core/spec.org units/core/overview.org
   :TODO: units/core/todo.org
   :RULES: units/core/CLAUDE.md
   :CHILDREN: bundle
   :END:

** bundle
   :PROPERTIES:
   :PARENT: core
   :SPEC: units/bundle/spec.org
   :TODO: units/bundle/todo.org
   :RULES: units/bundle/CLAUDE.md
   :END:
"
      nil (expand-file-name "docs/specflow.org" project-root))
     ;; Write root todo.org with NEXT task
     (write-region
      "#+TITLE: Test TODO

* Active

** NEXT bundle: Implement phase
   This is the next task.

   - Sub-item 1
   - Sub-item 2

** TODO Another task
   Not the next one.
"
      nil (expand-file-name "todo.org" project-root))
     ;; Write core files
     (write-region "Core spec content" nil
                   (expand-file-name "units/core/spec.org" project-root))
     (write-region "Core overview content" nil
                   (expand-file-name "units/core/overview.org" project-root))
     (write-region "Core todo content" nil
                   (expand-file-name "units/core/todo.org" project-root))
     (write-region "Core CLAUDE.md content" nil
                   (expand-file-name "units/core/CLAUDE.md" project-root))
     ;; Write bundle files
     (write-region "Bundle spec content" nil
                   (expand-file-name "units/bundle/spec.org" project-root))
     (write-region "Bundle todo content" nil
                   (expand-file-name "units/bundle/todo.org" project-root))
     (write-region "Bundle CLAUDE.md content" nil
                   (expand-file-name "units/bundle/CLAUDE.md" project-root))
     ,@body))

;;;; Path Splitting Tests

(ert-deftest specflow-test-bundle-split-paths-single ()
  "Test splitting a single path."
  (should (equal '("path/to/file.org")
                 (specflow-bundle--split-paths "path/to/file.org"))))

(ert-deftest specflow-test-bundle-split-paths-multiple ()
  "Test splitting space-separated paths."
  (should (equal '("path/one.org" "path/two.org")
                 (specflow-bundle--split-paths "path/one.org path/two.org"))))

(ert-deftest specflow-test-bundle-split-paths-multiple-spaces ()
  "Test splitting with multiple spaces between paths."
  (should (equal '("a.org" "b.org" "c.org")
                 (specflow-bundle--split-paths "a.org   b.org    c.org"))))

(ert-deftest specflow-test-bundle-split-paths-nil ()
  "Test splitting nil returns nil."
  (should (null (specflow-bundle--split-paths nil))))

(ert-deftest specflow-test-bundle-split-paths-empty ()
  "Test splitting empty string returns nil."
  (should (null (specflow-bundle--split-paths ""))))

(ert-deftest specflow-test-bundle-split-paths-whitespace-only ()
  "Test splitting whitespace-only string returns nil."
  (should (null (specflow-bundle--split-paths "   "))))

;;;; File Reading Tests

(ert-deftest specflow-test-bundle-read-file-content-exists ()
  "Test reading existing file returns content."
  (specflow-test-with-temp-project
      '(".git/" "docs/specflow.org" "test.txt")
    (write-region "File content here" nil
                  (expand-file-name "test.txt" project-root))
    (should (equal "File content here"
                   (specflow-bundle--read-file-content "test.txt" project-root)))))

(ert-deftest specflow-test-bundle-read-file-content-missing ()
  "Test reading missing file returns placeholder."
  (specflow-test-with-temp-project
      '(".git/" "docs/specflow.org")
    (let ((result (specflow-bundle--read-file-content "nonexistent.txt" project-root)))
      (should (string-match-p "<file not found:" result)))))

(ert-deftest specflow-test-bundle-read-file-content-absolute-path ()
  "Test reading with absolute path."
  (specflow-test-with-temp-project
      '(".git/" "docs/specflow.org" "test.txt")
    (let ((abs-path (expand-file-name "test.txt" project-root)))
      (write-region "Absolute path content" nil abs-path)
      (should (equal "Absolute path content"
                     (specflow-bundle--read-file-content abs-path project-root))))))

;;;; NEXT Task Extraction Tests

(ert-deftest specflow-test-bundle-extract-next-task-found ()
  "Test extracting NEXT task when present."
  (specflow-test-with-temp-project
      '(".git/" "docs/specflow.org")
    (write-region
     "#+TITLE: TODO

* Tasks

** NEXT First task
   Description here.

   - Item 1
   - Item 2

** TODO Second task
"
     nil (expand-file-name "todo.org" project-root))
    (let ((result (specflow-bundle--extract-next-task "todo.org" project-root)))
      (should (string-match-p "NEXT First task" result))
      (should (string-match-p "Description here" result))
      (should (string-match-p "Item 1" result)))))

(ert-deftest specflow-test-bundle-extract-next-task-not-found ()
  "Test placeholder when no NEXT task exists."
  (specflow-test-with-temp-project
      '(".git/" "docs/specflow.org")
    (write-region
     "#+TITLE: TODO

* Tasks

** TODO First task
** TODO Second task
"
     nil (expand-file-name "todo.org" project-root))
    (let ((result (specflow-bundle--extract-next-task "todo.org" project-root)))
      (should (string-match-p "<no NEXT task found>" result)))))

(ert-deftest specflow-test-bundle-extract-next-task-no-file ()
  "Test placeholder when todo.org doesn't exist."
  (specflow-test-with-temp-project
      '(".git/" "docs/specflow.org")
    (let ((result (specflow-bundle--extract-next-task "todo.org" project-root)))
      (should (string-match-p "<no root todo.org found>" result)))))

;;;; Bundle Context Tests

(ert-deftest specflow-test-bundle-context-returns-string ()
  "Test that bundle-context returns a non-empty string."
  (specflow-test-with-bundle-project
    (let ((default-directory project-root))
      (let ((result (specflow-bundle-context)))
        (should (stringp result))
        (should (> (length result) 0))))))

(ert-deftest specflow-test-bundle-context-includes-project-state ()
  "Test that bundle includes project state section."
  (specflow-test-with-bundle-project
    (let ((default-directory project-root))
      (let ((result (specflow-bundle-context)))
        (should (string-match-p "## Project State" result))
        (should (string-match-p "Phase: Implement" result))
        (should (string-match-p "Active Unit: bundle" result))))))

(ert-deftest specflow-test-bundle-context-includes-next-task ()
  "Test that bundle includes NEXT task section."
  (specflow-test-with-bundle-project
    (let ((default-directory project-root))
      (let ((result (specflow-bundle-context)))
        (should (string-match-p "## NEXT Task" result))
        (should (string-match-p "bundle: Implement phase" result))))))

(ert-deftest specflow-test-bundle-context-includes-parent ()
  "Test that bundle includes parent unit content."
  (specflow-test-with-bundle-project
    (let ((default-directory project-root))
      (let ((result (specflow-bundle-context)))
        (should (string-match-p "## Parent: core" result))
        (should (string-match-p "Core spec content" result))
        (should (string-match-p "Core CLAUDE.md content" result))))))

(ert-deftest specflow-test-bundle-context-includes-unit ()
  "Test that bundle includes active unit content."
  (specflow-test-with-bundle-project
    (let ((default-directory project-root))
      (let ((result (specflow-bundle-context)))
        (should (string-match-p "## Unit: bundle" result))
        (should (string-match-p "Bundle spec content" result))
        (should (string-match-p "Bundle todo content" result))
        (should (string-match-p "Bundle CLAUDE.md content" result))))))

(ert-deftest specflow-test-bundle-context-multi-file-spec ()
  "Test that space-separated SPEC files are all included."
  (specflow-test-with-bundle-project
    (let ((default-directory project-root))
      (let ((result (specflow-bundle-context)))
        ;; Core has two spec files
        (should (string-match-p "units/core/spec.org" result))
        (should (string-match-p "units/core/overview.org" result))
        (should (string-match-p "Core spec content" result))
        (should (string-match-p "Core overview content" result))))))

(ert-deftest specflow-test-bundle-context-with-unit-name ()
  "Test bundling a specific unit by name."
  (specflow-test-with-bundle-project
    (let ((default-directory project-root))
      (let ((result (specflow-bundle-context "core")))
        ;; Should bundle core, not bundle
        (should (string-match-p "## Unit: core" result))
        ;; core has no parent, so no parent section
        (should-not (string-match-p "## Parent:" result))))))

(ert-deftest specflow-test-bundle-context-unit-not-found ()
  "Test error when specified unit doesn't exist."
  (specflow-test-with-bundle-project
    (let ((default-directory project-root))
      (should-error (specflow-bundle-context "nonexistent")
                    :type 'specflow-unit-not-found))))

;;;; Soft Failure Tests

(ert-deftest specflow-test-bundle-context-missing-file ()
  "Test that missing files produce placeholders, not errors."
  (specflow-test-with-temp-project
      '(".git/"
        "docs/"
        "units/test/")
    ;; Control plane references files that don't all exist
    (write-region
     "#+TITLE: Test

* Project
  :PROPERTIES:
  :SPEC_FLOW_PHASE: Plan
  :SPEC_FLOW_ACTIVE_UNIT: test
  :END:

* Units

** test
   :PROPERTIES:
   :SPEC: units/test/spec.org
   :TODO: units/test/todo.org
   :RULES: units/test/CLAUDE.md
   :END:
"
     nil (expand-file-name "docs/specflow.org" project-root))
    ;; Only create spec.org, not todo.org or CLAUDE.md
    (write-region "Spec content" nil
                  (expand-file-name "units/test/spec.org" project-root))
    (write-region "" nil
                  (expand-file-name "todo.org" project-root))
    (let ((default-directory project-root))
      (let ((result (specflow-bundle-context)))
        ;; Should complete without error
        (should (stringp result))
        ;; Should have placeholders for missing files
        (should (string-match-p "<file not found:" result))))))

;;;; Determinism Tests

(ert-deftest specflow-test-bundle-context-deterministic ()
  "Test that bundling twice produces identical output (with fixed timestamp)."
  (specflow-test-with-bundle-project
    (let ((default-directory project-root))
      (let ((result1 (specflow-bundle-context-no-timestamp))
            (result2 (specflow-bundle-context-no-timestamp)))
        (should (equal result1 result2))))))

;;;; Interactive Command Tests

(ert-deftest specflow-test-bundle-command-creates-buffer ()
  "Test that M-x specflow-bundle creates the bundle buffer."
  (specflow-test-with-bundle-project
    (let ((default-directory project-root))
      ;; Kill buffer if it exists
      (when (get-buffer "*SpecFlow Bundle*")
        (kill-buffer "*SpecFlow Bundle*"))
      ;; Run command
      (specflow-bundle)
      ;; Buffer should exist
      (should (get-buffer "*SpecFlow Bundle*"))
      ;; Clean up
      (kill-buffer "*SpecFlow Bundle*"))))

(ert-deftest specflow-test-bundle-command-copies-to-kill-ring ()
  "Test that M-x specflow-bundle copies to kill-ring."
  (specflow-test-with-bundle-project
    (let ((default-directory project-root))
      ;; Clear kill-ring
      (setq kill-ring nil)
      ;; Run command
      (specflow-bundle)
      ;; Kill-ring should have content
      (should kill-ring)
      (should (string-match-p "SpecFlow Context Bundle" (car kill-ring)))
      ;; Clean up
      (when (get-buffer "*SpecFlow Bundle*")
        (kill-buffer "*SpecFlow Bundle*")))))

(ert-deftest specflow-test-bundle-command-buffer-content ()
  "Test that bundle buffer contains expected content."
  (specflow-test-with-bundle-project
    (let ((default-directory project-root))
      (when (get-buffer "*SpecFlow Bundle*")
        (kill-buffer "*SpecFlow Bundle*"))
      (specflow-bundle)
      (with-current-buffer "*SpecFlow Bundle*"
        (let ((content (buffer-string)))
          (should (string-match-p "## Project State" content))
          (should (string-match-p "## NEXT Task" content))
          (should (string-match-p "## Unit: bundle" content))))
      (kill-buffer "*SpecFlow Bundle*"))))

(provide 'test-specflow-bundle)
;;; test-specflow-bundle.el ends here
