;;; test-specflow-initiate.el --- Tests for specflow initiate -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT tests for specflow-initiate functions.

;;; Code:

(require 'ert)
(require 'specflow)

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
           ;; Create existing project marker
           (make-directory "docs" t)
           (write-region "existing" nil "docs/specflow.org")
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
  "Test preconditions fail when control plane exists."
  (specflow-test-with-existing-project
    (let ((result (specflow-initiate--check-preconditions)))
      (should result)
      (should (string-match-p "already exists" result))
      (should (string-match-p "specflow.org" result)))))

(ert-deftest specflow-test-initiate-preconditions-existing-marker ()
  "Test preconditions fail when .specflow marker exists."
  (specflow-test-with-empty-dir
    (write-region "" nil ".specflow")
    (let ((result (specflow-initiate--check-preconditions)))
      (should result)
      (should (string-match-p "already exists" result))
      (should (string-match-p ".specflow" result)))))

;;;; Template Tests

(ert-deftest specflow-test-initiate-control-plane-template ()
  "Test control plane template includes project name and structure."
  (let ((template (specflow-initiate--control-plane-template "test-project")))
    (should (string-match-p "test-project" template))
    (should (string-match-p "SPEC_FLOW_PHASE: Plan" template))
    (should (string-match-p "SPEC_FLOW_ACTIVE_UNIT: core" template))
    (should (string-match-p "\\* Units" template))
    (should (string-match-p "\\*\\* core" template))))

(ert-deftest specflow-test-initiate-claude-md-template ()
  "Test CLAUDE.md template includes project name and rules."
  (let ((template (specflow-initiate--claude-md-template "test-project")))
    (should (string-match-p "test-project" template))
    (should (string-match-p "SpecFlow" template))
    (should (string-match-p "Phase Enforcement" template))
    (should (string-match-p "Plan.*Specify.*Scaffold.*Implement" template))
    (should (string-match-p "STOP" template))))

(ert-deftest specflow-test-initiate-todo-template ()
  "Test todo.org template includes project name and NEXT task."
  (let ((template (specflow-initiate--todo-template "test-project")))
    (should (string-match-p "test-project" template))
    (should (string-match-p "NEXT" template))
    (should (string-match-p "core: Plan phase" template))
    (should (string-match-p "Backlog" template))))

;;;; Full Initialization Tests

(ert-deftest specflow-test-initiate-creates-control-plane ()
  "Test that initiate creates docs/specflow.org."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (should (file-exists-p "docs/specflow.org"))))

(ert-deftest specflow-test-initiate-creates-claude-md ()
  "Test that initiate creates CLAUDE.md."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (should (file-exists-p "CLAUDE.md"))))

(ert-deftest specflow-test-initiate-creates-todo ()
  "Test that initiate creates todo.org."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (should (file-exists-p "todo.org"))))

(ert-deftest specflow-test-initiate-creates-marker ()
  "Test that initiate creates .specflow marker."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (should (file-exists-p ".specflow"))))

(ert-deftest specflow-test-initiate-creates-core-dir ()
  "Test that initiate creates units/core/ directory."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (should (file-directory-p "units/core"))))

(ert-deftest specflow-test-initiate-control-plane-content ()
  "Test that created control plane has correct content."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (let ((content (with-temp-buffer
                     (insert-file-contents "docs/specflow.org")
                     (buffer-string))))
      (should (string-match-p "SPEC_FLOW_PHASE: Plan" content))
      (should (string-match-p "SPEC_FLOW_ACTIVE_UNIT: core" content)))))

(ert-deftest specflow-test-initiate-claude-md-content ()
  "Test that created CLAUDE.md has correct content."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (let ((content (with-temp-buffer
                     (insert-file-contents "CLAUDE.md")
                     (buffer-string))))
      (should (string-match-p "Phase Enforcement" content))
      (should (string-match-p "docs/specflow.org" content)))))

(ert-deftest specflow-test-initiate-todo-content ()
  "Test that created todo.org has correct content."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (let ((content (with-temp-buffer
                     (insert-file-contents "todo.org")
                     (buffer-string))))
      (should (string-match-p "NEXT" content))
      (should (string-match-p "core: Plan phase" content)))))

;;;; Error Case Tests

(ert-deftest specflow-test-initiate-refuses-existing-project ()
  "Test that initiate refuses to run in existing project."
  (specflow-test-with-existing-project
    (should-error (specflow-initiate) :type 'user-error)))

(ert-deftest specflow-test-initiate-refuses-marker-exists ()
  "Test that initiate refuses when .specflow marker exists."
  (specflow-test-with-empty-dir
    (write-region "" nil ".specflow")
    (should-error (specflow-initiate) :type 'user-error)))

;;;; Idempotence Tests

(ert-deftest specflow-test-initiate-not-idempotent ()
  "Test that running initiate twice fails."
  (specflow-test-with-empty-dir
    (specflow-initiate)
    (should-error (specflow-initiate) :type 'user-error)))

(provide 'test-specflow-initiate)
;;; test-specflow-initiate.el ends here
