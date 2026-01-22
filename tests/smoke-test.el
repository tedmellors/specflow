;;; smoke-test.el --- Manual smoke tests for org-store -*- lexical-binding: t -*-

(require 'cl-lib)

(defun specflow-run-smoke-tests ()
  "Run smoke tests for task management commands."
  (let* ((test-dir (make-temp-file "specflow-smoke-" t))
         (docs-dir (expand-file-name "docs" test-dir))
         (control-plane (expand-file-name "specflow.org" docs-dir))
         (todo-file (expand-file-name "todo.org" test-dir))
         (all-pass t))

    ;; Create project structure
    (make-directory docs-dir t)
    (with-temp-file (expand-file-name ".git" test-dir) (insert ""))

    ;; Create control plane
    (with-temp-file control-plane
      (insert "* Project\n"
              "  :PROPERTIES:\n"
              "  :SPEC_FLOW_PHASE: Implement\n"
              "  :SPEC_FLOW_ACTIVE_UNIT: test\n"
              "  :END:\n"))

    ;; Create todo.org
    (with-temp-file todo-file
      (insert "* Active\n\n"
              "** NEXT Current task\n"
              "   Working now.\n\n"
              "* Backlog\n\n"
              "** TODO Add authentication\n"
              "   Need login flow.\n\n"
              "** TODO Fix error handling\n"
              "   Better messages.\n"))

    (let ((default-directory test-dir))

      ;; Test 1: specflow-refine-task
      (princ "\n=== SMOKE TEST: specflow-refine-task ===\n")
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) "Add authentication"))
                ((symbol-function 'read-string)
                 (lambda (prompt &rest _)
                   (if (string-match "unit" prompt) "auth-unit" "OAuth support"))))
        (let ((result (specflow-refine-task)))
          (if (and result (stringp result))
              (princ "PASS: Returns prompt string\n")
            (setq all-pass nil)
            (princ "FAIL: No prompt returned\n"))
          (if (string-match "Add authentication" result)
              (princ "PASS: Prompt contains task headline\n")
            (setq all-pass nil)
            (princ "FAIL: Missing task headline\n"))
          (if (string-match "auth-unit" result)
              (princ "PASS: Prompt contains unit hint\n")
            (setq all-pass nil)
            (princ "FAIL: Missing unit hint\n"))
          (if (string-match "OAuth" result)
              (princ "PASS: Prompt contains user context\n")
            (setq all-pass nil)
            (princ "FAIL: Missing user context\n"))
          (if (string= (car kill-ring) result)
              (princ "PASS: Copied to kill-ring\n")
            (setq all-pass nil)
            (princ "FAIL: Not in kill-ring\n"))))

      ;; Reset todo.org for activate test
      (with-temp-file todo-file
        (insert "* Active\n\n"
                "** NEXT Current task\n"
                "   Working now.\n\n"
                "* Backlog\n\n"
                "** TODO Add authentication\n"
                "   Need login flow.\n\n"
                "** TODO Fix error handling\n"
                "   Better messages.\n"))

      ;; Test 2: specflow-activate-task
      (princ "\n=== SMOKE TEST: specflow-activate-task ===\n")
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) "Fix error handling"))
                ((symbol-function 'read-string)
                 (lambda (&rest _) "")))
        (specflow-activate-task))

      (let ((content (with-temp-buffer
                       (insert-file-contents todo-file)
                       (buffer-string))))
        (if (string-match "\\*\\* TODO Current task" content)
            (princ "PASS: Previous NEXT demoted to TODO\n")
          (setq all-pass nil)
          (princ "FAIL: NEXT not demoted\n"))
        (if (string-match "\\*\\* NEXT Fix error handling" content)
            (princ "PASS: Selected task promoted to NEXT\n")
          (setq all-pass nil)
          (princ "FAIL: Task not promoted\n"))
        (let ((backlog-pos (string-match "\\* Backlog" content)))
          (if (and backlog-pos
                   (not (string-match "Fix error handling"
                                      (substring content backlog-pos))))
              (princ "PASS: Task removed from Backlog\n")
            (setq all-pass nil)
            (princ "FAIL: Task still in Backlog\n")))
        (if (string-match "Better messages" content)
            (princ "PASS: Task body preserved\n")
          (setq all-pass nil)
          (princ "FAIL: Task body lost\n"))))

    ;; Cleanup
    (delete-directory test-dir t)

    (princ "\n=== SMOKE TESTS COMPLETE ===\n")
    (if all-pass
        (princ "All smoke tests PASSED\n")
      (princ "Some smoke tests FAILED\n"))
    all-pass))

(specflow-run-smoke-tests)

;;; smoke-test.el ends here
