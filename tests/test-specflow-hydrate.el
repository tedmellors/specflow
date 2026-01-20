;;; test-specflow-hydrate.el --- Tests for specflow hydrate -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT tests for specflow-hydrate functions.

;;; Code:

(require 'ert)
(require 'specflow)

;;;; Test Helpers

(defmacro specflow-test-with-hydrate-project (&rest body)
  "Create a complete hydrate test project and execute BODY.
Sets up control plane, units, and files for hydrate testing."
  (declare (indent 0))
  `(let ((project-root (make-temp-file "specflow-test-" t)))
     (unwind-protect
         (progn
           ;; Create directory structure
           (make-directory (expand-file-name ".git" project-root) t)
           (make-directory (expand-file-name "docs" project-root) t)
           (make-directory (expand-file-name "units/core" project-root) t)
           (make-directory (expand-file-name "units/hydrate" project-root) t)
           ;; Write control plane
           (write-region
            "#+TITLE: Test Control Plane

* Project
  :PROPERTIES:
  :SPEC_FLOW_PHASE: Implement
  :SPEC_FLOW_ACTIVE_UNIT: hydrate
  :END:

* Units

** core
   :PROPERTIES:
   :SPEC: units/core/spec.org
   :TODO: units/core/todo.org
   :RULES: units/core/CLAUDE.md
   :CHILDREN: hydrate
   :END:

** hydrate
   :PROPERTIES:
   :PARENT: core
   :SPEC: units/hydrate/spec.org
   :TODO: units/hydrate/todo.org
   :RULES: units/hydrate/CLAUDE.md
   :END:
"
            nil (expand-file-name "docs/specflow.org" project-root))
           ;; Write root todo.org with NEXT task
           (write-region
            "#+TITLE: Test TODO

* Active

** NEXT hydrate: Implement phase
   This is the next task to complete.

   - Sub-item 1
   - Sub-item 2

** TODO Another task
   Not the next one.
"
            nil (expand-file-name "todo.org" project-root))
           ;; Write core files
           (write-region "Core spec content" nil
                         (expand-file-name "units/core/spec.org" project-root))
           (write-region "Core todo content" nil
                         (expand-file-name "units/core/todo.org" project-root))
           (write-region "Core CLAUDE.md content" nil
                         (expand-file-name "units/core/CLAUDE.md" project-root))
           ;; Write hydrate files
           (write-region "Hydrate spec content" nil
                         (expand-file-name "units/hydrate/spec.org" project-root))
           (write-region "Hydrate todo content" nil
                         (expand-file-name "units/hydrate/todo.org" project-root))
           (write-region "Hydrate CLAUDE.md content" nil
                         (expand-file-name "units/hydrate/CLAUDE.md" project-root))
           ,@body)
       ;; Cleanup
       (delete-directory project-root t))))

;;;; Phase Actions Tests

(ert-deftest specflow-test-hydrate-phase-actions-plan ()
  "Test phase actions for Plan phase."
  (let ((actions (specflow-hydrate--phase-actions "Plan")))
    (should (string-match-p "Summarize understanding" actions))
    (should (string-match-p "DO NOT write or modify code" actions))))

(ert-deftest specflow-test-hydrate-phase-actions-implement ()
  "Test phase actions for Implement phase."
  (let ((actions (specflow-hydrate--phase-actions "Implement")))
    (should (string-match-p "Write code and tests" actions))
    (should (string-match-p "Keep diffs minimal" actions))))

(ert-deftest specflow-test-hydrate-phase-actions-unknown ()
  "Test phase actions for unknown phase returns generic."
  (let ((actions (specflow-hydrate--phase-actions "unknown-phase")))
    (should (string-match-p "Follow phase-specific rules" actions))))

;;;; NEXT Extraction Tests

(ert-deftest specflow-test-hydrate-extract-next-found ()
  "Test extracting NEXT task when present."
  (specflow-test-with-hydrate-project
    (let ((default-directory project-root))
      (let ((result (specflow-hydrate--extract-next-task "todo.org" project-root)))
        (should (string-match-p "NEXT hydrate: Implement phase" result))
        (should (string-match-p "This is the next task" result))
        (should (string-match-p "Sub-item 1" result))))))

(ert-deftest specflow-test-hydrate-extract-next-not-found ()
  "Test placeholder when no NEXT task exists."
  (specflow-test-with-hydrate-project
    ;; Overwrite todo.org with no NEXT
    (write-region
     "#+TITLE: TODO

* Tasks

** TODO First task
** TODO Second task
"
     nil (expand-file-name "todo.org" project-root))
    (let ((default-directory project-root))
      (let ((result (specflow-hydrate--extract-next-task "todo.org" project-root)))
        (should (string-match-p "<no NEXT task found>" result))))))

(ert-deftest specflow-test-hydrate-extract-next-no-file ()
  "Test placeholder when todo.org doesn't exist."
  (specflow-test-with-hydrate-project
    ;; Delete the todo.org
    (delete-file (expand-file-name "todo.org" project-root))
    (let ((default-directory project-root))
      (let ((result (specflow-hydrate--extract-next-task "todo.org" project-root)))
        (should (string-match-p "<no root todo.org found>" result))))))

;;;; Header Generation Tests

(ert-deftest specflow-test-hydrate-header-includes-unit ()
  "Test that header includes active unit."
  (specflow-test-with-hydrate-project
    (let ((default-directory project-root))
      (let ((header (specflow-hydrate--generate-header)))
        (should (string-match-p "Active unit: hydrate" header))))))

(ert-deftest specflow-test-hydrate-header-includes-phase ()
  "Test that header includes current phase."
  (specflow-test-with-hydrate-project
    (let ((default-directory project-root))
      (let ((header (specflow-hydrate--generate-header)))
        (should (string-match-p "Phase: Implement" header))))))

(ert-deftest specflow-test-hydrate-header-includes-parent-chain ()
  "Test that header includes parent chain."
  (specflow-test-with-hydrate-project
    (let ((default-directory project-root))
      (let ((header (specflow-hydrate--generate-header)))
        (should (string-match-p "Parent chain: core" header))))))

(ert-deftest specflow-test-hydrate-header-includes-files ()
  "Test that header includes file pointers."
  (specflow-test-with-hydrate-project
    (let ((default-directory project-root))
      (let ((header (specflow-hydrate--generate-header)))
        (should (string-match-p "control plane" header))
        (should (string-match-p "root todo" header))
        (should (string-match-p "unit SPEC" header))
        (should (string-match-p "unit TODO" header))
        (should (string-match-p "unit RULES" header))))))

(ert-deftest specflow-test-hydrate-header-includes-phase-actions ()
  "Test that header includes phase-specific actions."
  (specflow-test-with-hydrate-project
    (let ((default-directory project-root))
      (let ((header (specflow-hydrate--generate-header)))
        (should (string-match-p "Allowed actions in this phase:" header))
        ;; In Implement phase
        (should (string-match-p "Write code and tests" header))))))

(ert-deftest specflow-test-hydrate-header-includes-stop-conditions ()
  "Test that header includes STOP conditions."
  (specflow-test-with-hydrate-project
    (let ((default-directory project-root))
      (let ((header (specflow-hydrate--generate-header)))
        (should (string-match-p "STOP conditions:" header))
        (should (string-match-p "violate the current phase" header))))))

(ert-deftest specflow-test-hydrate-header-includes-next-task ()
  "Test that header includes NEXT task."
  (specflow-test-with-hydrate-project
    (let ((default-directory project-root))
      (let ((header (specflow-hydrate--generate-header)))
        (should (string-match-p "Canonical NEXT task:" header))
        (should (string-match-p "hydrate: Implement phase" header))))))

(ert-deftest specflow-test-hydrate-header-no-parent ()
  "Test header for unit with no parent."
  (specflow-test-with-hydrate-project
    (let ((default-directory project-root))
      (let ((header (specflow-hydrate--generate-header "core")))
        (should (string-match-p "Active unit: core" header))
        (should (string-match-p "Parent chain: none" header))))))

;;;; Command Tests

(ert-deftest specflow-test-hydrate-copy-header ()
  "Test that copy-header populates kill-ring."
  (specflow-test-with-hydrate-project
    (let ((default-directory project-root))
      (setq kill-ring nil)
      (specflow-hydrate-copy-header)
      (should kill-ring)
      (should (string-match-p "Active unit: hydrate" (car kill-ring))))))

(ert-deftest specflow-test-hydrate-preview-header ()
  "Test that preview-header creates buffer."
  (specflow-test-with-hydrate-project
    (let ((default-directory project-root))
      (when (get-buffer "*SpecFlow Header*")
        (kill-buffer "*SpecFlow Header*"))
      (specflow-hydrate-preview-header)
      (should (get-buffer "*SpecFlow Header*"))
      (with-current-buffer "*SpecFlow Header*"
        (should buffer-read-only)
        (should (string-match-p "Active unit: hydrate" (buffer-string))))
      (kill-buffer "*SpecFlow Header*"))))

;;;; Scan Tests

(ert-deftest specflow-test-hydrate-violation-patterns-plan ()
  "Test that Plan phase has violation patterns."
  (let ((patterns (specflow-hydrate--violation-patterns "Plan")))
    (should patterns)
    (should (> (length patterns) 0))))

(ert-deftest specflow-test-hydrate-violation-patterns-implement ()
  "Test that Implement phase has no violation patterns."
  (let ((patterns (specflow-hydrate--violation-patterns "Implement")))
    (should (null patterns))))

(ert-deftest specflow-test-hydrate-scan-detects-code-block ()
  "Test that scan detects code blocks in Plan phase."
  (let* ((test-text "Some text\n```python\ncode here\n```\nMore text")
         (violations (specflow-hydrate--scan-for-violations test-text "Plan")))
    (should violations)
    (should (>= (length violations) 1))
    (should (string-match-p "```" (cdr (car violations))))))

(ert-deftest specflow-test-hydrate-scan-no-warning-implement ()
  "Test that scan does not warn for code in Implement phase."
  (let* ((test-text "Some text\n```python\ncode here\n```\nMore text")
         (violations (specflow-hydrate--scan-for-violations test-text "Implement")))
    (should (null violations))))

(ert-deftest specflow-test-hydrate-scan-detects-diff ()
  "Test that scan detects diff hunks in Plan phase."
  (let* ((test-text "Changes:\n@@ -1,3 +1,4 @@\n some diff\n")
         (violations (specflow-hydrate--scan-for-violations test-text "Plan")))
    (should violations)))

;;;; Error Case Tests

(ert-deftest specflow-test-hydrate-missing-control-plane ()
  "Test error when control plane is missing."
  (let ((project-root (make-temp-file "specflow-test-" t)))
    (unwind-protect
        (let ((default-directory project-root))
          (make-directory (expand-file-name ".git" project-root) t)
          (should-error (specflow-hydrate--generate-header)
                        :type 'specflow-control-plane-not-found))
      (delete-directory project-root t))))

;;;; Safe Buffer Tests

(ert-deftest specflow-test-hydrate-safe-buffer-scratch ()
  "Test that *scratch* is considered safe."
  (with-current-buffer (get-buffer-create "*scratch*")
    (should (specflow-hydrate--safe-buffer-p))))

(ert-deftest specflow-test-hydrate-safe-buffer-gptel ()
  "Test that gptel buffers are considered safe."
  (with-current-buffer (get-buffer-create "*gptel-test*")
    (unwind-protect
        (should (specflow-hydrate--safe-buffer-p))
      (kill-buffer "*gptel-test*"))))

(ert-deftest specflow-test-hydrate-safe-buffer-other ()
  "Test that random buffers are not considered safe."
  (with-current-buffer (get-buffer-create "*random-buffer*")
    (unwind-protect
        (should-not (specflow-hydrate--safe-buffer-p))
      (kill-buffer "*random-buffer*"))))

(provide 'test-specflow-hydrate)
;;; test-specflow-hydrate.el ends here
