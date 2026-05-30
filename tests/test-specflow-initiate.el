;;; test-specflow-initiate.el --- Tests for specflow initiate -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT tests for specflow-initiate functions.
;; Tests verify .specflow/ directory structure with root unit.

;;; Code:

;; Load-path setup for standalone test execution
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../src" dir)))

(require 'ert)
(require 'specflow-initiate)

;;;; Test Helpers

(defmacro specflow-test-with-empty-dir (&rest body)
  "Create an empty temp directory and execute BODY."
  (declare (indent 0))
  `(let ((test-dir (make-temp-file "specflow-initiate-test-" t)))
     (unwind-protect
         (let ((default-directory (file-name-as-directory test-dir)))
           ,@body)
       (delete-directory test-dir t))))

(defmacro specflow-test-with-existing-project (&rest body)
  "Create a temp directory with existing SpecFlow project and execute BODY."
  (declare (indent 0))
  `(let ((test-dir (make-temp-file "specflow-initiate-test-" t)))
     (unwind-protect
         (let ((default-directory (file-name-as-directory test-dir)))
           ;; Create existing project structure
           (make-directory ".specflow" t)
           (write-region "existing" nil ".specflow/specflow.org")
           ,@body)
       (delete-directory test-dir t))))

;;;; Project Name Derivation Tests

(ert-deftest specflow-test-initiate-derive-name-simple ()
  "Test project name derivation from simple directory."
  (let ((default-directory "/tmp/my-project/"))
    (should (equal "my-project" (specflow-initiate--derive-project-name)))))

(ert-deftest specflow-test-initiate-derive-name-spaces ()
  "Test project name derivation replaces spaces with hyphens."
  (let ((default-directory "/tmp/My Cool Project/"))
    (should (equal "my-cool-project" (specflow-initiate--derive-project-name)))))

(ert-deftest specflow-test-initiate-derive-name-uppercase ()
  "Test project name derivation converts to lowercase."
  (let ((default-directory "/tmp/MyProject/"))
    (should (equal "myproject" (specflow-initiate--derive-project-name)))))

(ert-deftest specflow-test-initiate-derive-name-mixed ()
  "Test project name derivation with mixed case and spaces."
  (let ((default-directory "/tmp/My COOL Project/"))
    (should (equal "my-cool-project" (specflow-initiate--derive-project-name)))))

;;;; Precondition Tests

(ert-deftest specflow-test-initiate-preconditions-empty-dir ()
  "Test preconditions pass for empty directory."
  (specflow-test-with-empty-dir
    (should (null (specflow-initiate--check-preconditions)))))

(ert-deftest specflow-test-initiate-preconditions-existing-control-plane ()
  "Test preconditions fail when .specflow/specflow.org exists."
  (specflow-test-with-existing-project
    (let ((result (specflow-initiate--check-preconditions)))
      (should result)
      (should (string-match-p "already exists" result))
      (should (string-match-p ".specflow/specflow.org" result)))))

;;;; Template Tests

(ert-deftest specflow-test-initiate-control-plane-template ()
  "Test control plane template includes project name and root unit."
  (let ((template (specflow-initiate--control-plane-template "test-project")))
    (should (string-match-p "test-project" template))
    (should (string-match-p "SPEC_FLOW_PHASE: Plan" template))
    (should (string-match-p "SPEC_FLOW_ACTIVE_UNIT: root" template))
    (should (string-match-p "\\* Units" template))
    (should (string-match-p "\\*\\* root" template))
    (should (string-match-p ".specflow/units/root/spec.org" template))
    ;; Root unit's task list is the master TODO at .specflow/todo.org
    (should (string-match-p ":TODO: .specflow/todo.org" template))))

(ert-deftest specflow-test-initiate-control-plane-no-dir-for-root ()
  "Test control plane root unit has no DIR property."
  (let ((template (specflow-initiate--control-plane-template "test-project")))
    ;; root unit should NOT have a DIR property
    (should-not (string-match-p ":DIR:" template))))

(ert-deftest specflow-test-initiate-todo-template ()
  "Test todo.org template includes project name and NEXT task for docs."
  (let ((template (specflow-initiate--todo-template "test-project")))
    (should (string-match-p "test-project" template))
    (should (string-match-p "NEXT" template))
    (should (string-match-p "root: Plan phase" template))
    (should (string-match-p "Backlog" template))))

(ert-deftest specflow-test-initiate-find-rules-org ()
  "Test find-rules-org locates rules.org in specflow installation."
  (let ((rules-path (specflow-initiate--find-rules-org)))
    (should rules-path)
    (should (file-exists-p rules-path))
    (should (string-match-p "rules\\.org$" rules-path))))

(ert-deftest specflow-test-initiate-root-spec-template ()
  "Test root spec.org template describes documentation deliverables."
  (let ((template (specflow-initiate--root-spec-template)))
    (should (string-match-p "root – Specification" template))
    (should (string-match-p "spec.org" template))
    (should (string-match-p "no source code" template))))

;;;; Full Initialization Tests - Directory Structure

(ert-deftest specflow-test-initiate-creates-specflow-dir ()
  "Test that initiate creates .specflow/ directory."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (should (file-directory-p ".specflow"))))

(ert-deftest specflow-test-initiate-creates-control-plane ()
  "Test that initiate creates .specflow/specflow.org."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (should (file-exists-p ".specflow/specflow.org"))))

(ert-deftest specflow-test-initiate-creates-root-todo ()
  "Test that initiate creates .specflow/todo.org."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (should (file-exists-p ".specflow/todo.org"))))

(ert-deftest specflow-test-initiate-creates-rules ()
  "Test that initiate creates .specflow/rules.org."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (should (file-exists-p ".specflow/rules.org"))))

(ert-deftest specflow-test-initiate-creates-root-unit-dir ()
  "Test that initiate creates .specflow/units/root/ directory."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (should (file-directory-p ".specflow/units/root"))))

(ert-deftest specflow-test-initiate-creates-root-spec ()
  "Test that initiate creates .specflow/units/root/spec.org."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (should (file-exists-p ".specflow/units/root/spec.org"))))

(ert-deftest specflow-test-initiate-no-root-unit-todo ()
  "Test that initiate does NOT create .specflow/units/root/todo.org.
The root unit's task list is the master TODO at .specflow/todo.org."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (should-not (file-exists-p ".specflow/units/root/todo.org"))))

(ert-deftest specflow-test-initiate-creates-src-dir ()
  "Test that initiate creates src/ directory."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (should (file-directory-p "src"))))

(ert-deftest specflow-test-initiate-creates-tests-dir ()
  "Test that initiate creates tests/ directory."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (should (file-directory-p "tests"))))

;;;; Full Initialization Tests - Content Verification

(ert-deftest specflow-test-initiate-control-plane-content ()
  "Test that created control plane has correct content."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (let ((content (with-temp-buffer
                     (insert-file-contents ".specflow/specflow.org")
                     (buffer-string))))
      (should (string-match-p "SPEC_FLOW_PHASE: Plan" content))
      (should (string-match-p "SPEC_FLOW_ACTIVE_UNIT: root" content))
      (should (string-match-p ".specflow/units/root/spec.org" content)))))

(ert-deftest specflow-test-initiate-todo-content ()
  "Test that created todo.org has correct content."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (let ((content (with-temp-buffer
                     (insert-file-contents ".specflow/todo.org")
                     (buffer-string))))
      (should (string-match-p "NEXT" content))
      (should (string-match-p "root: Plan phase" content)))))

(ert-deftest specflow-test-initiate-rules-content ()
  "Test that created rules.org has correct content."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (let ((content (with-temp-buffer
                     (insert-file-contents ".specflow/rules.org")
                     (buffer-string))))
      (should (string-match-p "Control Plane Authority" content))
      (should (string-match-p ".specflow/specflow.org" content)))))

(ert-deftest specflow-test-initiate-root-spec-content ()
  "Test that created root spec.org has correct content."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (let ((content (with-temp-buffer
                     (insert-file-contents ".specflow/units/root/spec.org")
                     (buffer-string))))
      (should (string-match-p "spec.org" content))
      (should (string-match-p "no source code" content)))))

;;;; Error Case Tests

(ert-deftest specflow-test-initiate-refuses-existing-project ()
  "Test that initiate refuses to run in existing project."
  (specflow-test-with-existing-project
    (should-error (specflow-initiate) :type 'user-error)))

;;;; Idempotence Tests

(ert-deftest specflow-test-initiate-not-idempotent ()
  "Test that running initiate twice fails."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (should-error (specflow-initiate) :type 'user-error)))

;;;; No Legacy Structure Tests

(ert-deftest specflow-test-initiate-no-legacy-docs-dir ()
  "Test that initiate does NOT create docs/ directory."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (should-not (file-directory-p "docs"))))

(ert-deftest specflow-test-initiate-no-legacy-units-dir ()
  "Test that initiate does NOT create root units/ directory."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (should-not (file-directory-p "units"))))

(ert-deftest specflow-test-initiate-no-root-todo ()
  "Test that initiate does NOT create root todo.org."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (should-not (file-exists-p "todo.org"))))

(ert-deftest specflow-test-initiate-no-specflow-marker ()
  "Test that initiate does NOT create .specflow marker file."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    ;; .specflow should be a directory, not a file
    (should (file-directory-p ".specflow"))
    (should-not (file-regular-p ".specflow"))))

(provide 'test-specflow-initiate)
;;; test-specflow-initiate.el ends here
