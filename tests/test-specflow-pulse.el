;;; test-specflow-pulse.el --- Tests for specflow-pulse -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT tests for specflow-pulse functions.

;;; Code:

(require 'ert)
(require 'specflow-pulse)

;;;; Test Helpers

(defmacro specflow-pulse-test-with-temp-project (project-structure &rest body)
  "Create a temporary project with PROJECT-STRUCTURE and execute BODY.
PROJECT-STRUCTURE is a list of (path . content) pairs or just paths.
The macro binds `project-root' to the temporary directory."
  (declare (indent 1))
  `(let ((project-root (make-temp-file "specflow-pulse-test-" t)))
     (unwind-protect
         (progn
           ;; Create project structure
           (dolist (item ,project-structure)
             (let* ((path (if (consp item) (car item) item))
                    (content (if (consp item) (cdr item) ""))
                    (full-path (expand-file-name path project-root)))
               (if (string-suffix-p "/" path)
                   (make-directory full-path t)
                 (make-directory (file-name-directory full-path) t)
                 (write-region content nil full-path))))
           ,@body)
       ;; Cleanup
       (delete-directory project-root t))))

(defconst specflow-pulse-test--control-plane-content
  "* Project
  :PROPERTIES:
  :SPEC_FLOW_PHASE: Implement
  :SPEC_FLOW_ACTIVE_UNIT: pulse
  :END:

* Units

** pulse
   :PROPERTIES:
   :SPEC: .specflow/units/pulse/spec.org
   :TODO: .specflow/units/pulse/todo.org
   :END:
"
  "Sample control plane content for tests.")

;;;; Core Status Reading Tests

(ert-deftest specflow-pulse-test-status-valid-project ()
  "Test specflow-pulse-status with valid SpecFlow project."
  (specflow-pulse-test-with-temp-project
      `((".git/")
        (".specflow/specflow.org" . ,specflow-pulse-test--control-plane-content))
    (let ((status (specflow-pulse-status project-root)))
      (should status)
      (should (equal (plist-get status :phase) "Implement"))
      (should (equal (plist-get status :unit) "pulse"))
      (should (plist-get status :claude))
      (should (plist-get status :project-name)))))

(ert-deftest specflow-pulse-test-status-non-project ()
  "Test specflow-pulse-status with non-SpecFlow directory."
  (specflow-pulse-test-with-temp-project
      '((".git/") ("src/"))
    (let ((status (specflow-pulse-status project-root)))
      (should (null status)))))

(ert-deftest specflow-pulse-test-status-no-specflow-dir ()
  "Test specflow-pulse-status with directory lacking .specflow."
  (specflow-pulse-test-with-temp-project
      '(("src/") ("README.md"))
    (let ((status (specflow-pulse-status project-root)))
      (should (null status)))))

;;;; Claude Status File Tests

(ert-deftest specflow-pulse-test-claude-status-working ()
  "Test reading Claude status file with working status."
  (specflow-pulse-test-with-temp-project
      `((".git/")
        (".specflow/specflow.org" . ,specflow-pulse-test--control-plane-content)
        (".specflow/.claude-status" . "{\"status\": \"working\", \"timestamp\": \"2099-01-01T00:00:00Z\"}"))
    (let ((status (specflow-pulse-status project-root)))
      (should (eq (plist-get status :claude) 'working)))))

(ert-deftest specflow-pulse-test-claude-status-idle ()
  "Test reading Claude status file with idle status."
  (specflow-pulse-test-with-temp-project
      `((".git/")
        (".specflow/specflow.org" . ,specflow-pulse-test--control-plane-content)
        (".specflow/.claude-status" . "{\"status\": \"idle\", \"timestamp\": \"2099-01-01T00:00:00Z\"}"))
    (let ((status (specflow-pulse-status project-root)))
      (should (eq (plist-get status :claude) 'idle)))))

(ert-deftest specflow-pulse-test-claude-status-missing-file ()
  "Test Claude status when .claude-status file is missing."
  (specflow-pulse-test-with-temp-project
      `((".git/")
        (".specflow/specflow.org" . ,specflow-pulse-test--control-plane-content))
    (let ((status (specflow-pulse-status project-root)))
      ;; Without MCP, should be unknown
      (should (memq (plist-get status :claude) '(unknown disconnected))))))

(ert-deftest specflow-pulse-test-claude-status-stale-file ()
  "Test Claude status when .claude-status file is stale."
  (specflow-pulse-test-with-temp-project
      `((".git/")
        (".specflow/specflow.org" . ,specflow-pulse-test--control-plane-content)
        ;; Timestamp in the past (stale)
        (".specflow/.claude-status" . "{\"status\": \"working\", \"timestamp\": \"2020-01-01T00:00:00Z\"}"))
    (let ((status (specflow-pulse-status project-root)))
      ;; Stale file should result in unknown
      (should (memq (plist-get status :claude) '(unknown disconnected))))))

(ert-deftest specflow-pulse-test-claude-status-invalid-json ()
  "Test Claude status when .claude-status has invalid JSON."
  (specflow-pulse-test-with-temp-project
      `((".git/")
        (".specflow/specflow.org" . ,specflow-pulse-test--control-plane-content)
        (".specflow/.claude-status" . "not valid json"))
    (let ((status (specflow-pulse-status project-root)))
      (should (memq (plist-get status :claude) '(unknown disconnected))))))

;;;; Tab-Bar Segment Rendering Tests

(ert-deftest specflow-pulse-test-format-segment-basic ()
  "Test basic segment formatting."
  (let ((status '(:phase "Plan" :unit "root" :claude working)))
    (let ((segment (specflow-pulse--format-segment status)))
      (should (stringp segment))
      (should (string-match "Plan" segment))
      (should (string-match "root" segment))
      (should (string-match "●" segment)))))

(ert-deftest specflow-pulse-test-format-segment-idle ()
  "Test segment formatting with idle status."
  (let ((status '(:phase "Implement" :unit "pulse" :claude idle)))
    (let ((segment (specflow-pulse--format-segment status)))
      (should (string-match "○" segment)))))

(ert-deftest specflow-pulse-test-format-segment-disconnected ()
  "Test segment formatting with disconnected status."
  (let ((status '(:phase "Validate" :unit "test" :claude disconnected)))
    (let ((segment (specflow-pulse--format-segment status)))
      (should (string-match "✕" segment)))))

(ert-deftest specflow-pulse-test-format-segment-unknown ()
  "Test segment formatting with unknown status."
  (let ((status '(:phase "Document" :unit "docs" :claude unknown)))
    (let ((segment (specflow-pulse--format-segment status)))
      (should (string-match "\\?" segment)))))

(ert-deftest specflow-pulse-test-tab-bar-segment-non-project ()
  "Test tab-bar segment returns empty for non-project."
  (specflow-pulse-test-with-temp-project
      '((".git/") ("src/"))
    (let ((default-directory project-root))
      (let ((segment (specflow-pulse--tab-bar-segment)))
        (should (equal segment ""))))))

(ert-deftest specflow-pulse-test-format-segment-without-unit ()
  "Test segment formatting when specflow-pulse-show-unit is nil."
  (let ((specflow-pulse-show-unit nil)
        (status '(:phase "Plan" :unit "root" :claude working)))
    (let ((segment (specflow-pulse--format-segment status)))
      (should (string-match "Plan" segment))
      (should-not (string-match "root" segment)))))

;;;; Phase Face Tests

(ert-deftest specflow-pulse-test-phase-face-plan ()
  "Test Plan phase face."
  (should (eq (specflow-pulse--phase-face "Plan") 'specflow-pulse-phase-plan)))

(ert-deftest specflow-pulse-test-phase-face-implement ()
  "Test Implement phase face."
  (should (eq (specflow-pulse--phase-face "Implement") 'specflow-pulse-phase-implement)))

(ert-deftest specflow-pulse-test-phase-face-unknown ()
  "Test unknown phase returns default face."
  (should (eq (specflow-pulse--phase-face "Unknown") 'default)))

;;;; Claude Face Tests

(ert-deftest specflow-pulse-test-claude-face-working ()
  "Test working Claude status face."
  (should (eq (specflow-pulse--claude-face 'working) 'specflow-pulse-claude-working)))

(ert-deftest specflow-pulse-test-claude-face-idle ()
  "Test idle Claude status face."
  (should (eq (specflow-pulse--claude-face 'idle) 'specflow-pulse-claude-idle)))

(ert-deftest specflow-pulse-test-claude-face-disconnected ()
  "Test disconnected Claude status face."
  (should (eq (specflow-pulse--claude-face 'disconnected) 'specflow-pulse-claude-disconnected)))

(ert-deftest specflow-pulse-test-claude-face-unknown ()
  "Test unknown Claude status face."
  (should (eq (specflow-pulse--claude-face 'unknown) 'specflow-pulse-claude-unknown)))

;;;; Claude Icon Tests

(ert-deftest specflow-pulse-test-claude-icon-working ()
  "Test working Claude status icon."
  (should (equal (specflow-pulse--claude-icon 'working) "●")))

(ert-deftest specflow-pulse-test-claude-icon-idle ()
  "Test idle Claude status icon."
  (should (equal (specflow-pulse--claude-icon 'idle) "○")))

(ert-deftest specflow-pulse-test-claude-icon-disconnected ()
  "Test disconnected Claude status icon."
  (should (equal (specflow-pulse--claude-icon 'disconnected) "✕")))

(ert-deftest specflow-pulse-test-claude-icon-unknown ()
  "Test unknown Claude status icon."
  (should (equal (specflow-pulse--claude-icon 'unknown) "?")))

;;;; Mode Enable/Disable Tests

(ert-deftest specflow-pulse-test-mode-enable ()
  "Test enabling specflow-pulse-mode."
  (unwind-protect
      (progn
        (specflow-pulse-mode 1)
        (should specflow-pulse-mode)
        (should (memq 'specflow-pulse--tab-bar-segment tab-bar-format)))
    (specflow-pulse-mode -1)))

(ert-deftest specflow-pulse-test-mode-disable ()
  "Test disabling specflow-pulse-mode."
  (specflow-pulse-mode 1)
  (specflow-pulse-mode -1)
  (should-not specflow-pulse-mode)
  (should-not (memq 'specflow-pulse--tab-bar-segment tab-bar-format)))

(ert-deftest specflow-pulse-test-mode-timer-cleanup ()
  "Test that timer is cleaned up on mode disable."
  (specflow-pulse-mode 1)
  (should specflow-pulse--poll-timer)
  (specflow-pulse-mode -1)
  (should-not specflow-pulse--poll-timer))

;;;; Per-Tab Project Detection Tests

;; Note: specflow-pulse--current-project relies on selected-window behavior
;; which doesn't work reliably in batch mode. These tests verify the underlying
;; status function instead.

(ert-deftest specflow-pulse-test-status-from-subdir ()
  "Test that specflow-pulse-status works from a subdirectory."
  (specflow-pulse-test-with-temp-project
      `((".git/")
        (".specflow/specflow.org" . ,specflow-pulse-test--control-plane-content)
        ("src/test.el"))
    (let ((subdir (expand-file-name "src/" project-root)))
      (let ((status (specflow-pulse-status subdir)))
        (should status)
        (should (equal (plist-get status :phase) "Implement"))))))

(ert-deftest specflow-pulse-test-status-non-project-subdir ()
  "Test that specflow-pulse-status returns nil for non-project."
  (specflow-pulse-test-with-temp-project
      '((".git/") ("src/"))
    (let ((status (specflow-pulse-status project-root)))
      (should (null status)))))

;;;; MCP Integration Tests (when not available)

(ert-deftest specflow-pulse-test-mcp-not-loaded ()
  "Test MCP check when claude-code-ide is not loaded."
  ;; Ensure claude-code-ide-mcp is not loaded for this test
  (when (featurep 'claude-code-ide-mcp)
    (ert-skip "claude-code-ide-mcp is loaded"))
  (should (null (specflow-pulse--check-mcp-connection "/some/path"))))

(provide 'test-specflow-pulse)
;;; test-specflow-pulse.el ends here
