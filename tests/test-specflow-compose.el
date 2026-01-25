;;; test-specflow-compose.el --- Tests for specflow compose -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT tests for specflow-compose functions.

;;; Code:

;; Load-path setup for standalone test execution
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../src" dir)))

(require 'ert)
(require 'specflow-compose)

;;;; Test Helpers

(defmacro specflow-test-with-compose-project (&rest body)
  "Create a complete test project for compose testing and execute BODY.
Sets up control plane in Plan phase for compose commands."
  (declare (indent 0))
  `(let ((project-root (make-temp-file "specflow-test-" t)))
     (unwind-protect
         (progn
           ;; Create directory structure
           (make-directory (expand-file-name ".git" project-root) t)
           (make-directory (expand-file-name ".specflow" project-root) t)
           (make-directory (expand-file-name ".specflow/units/docs" project-root) t)
           (make-directory (expand-file-name ".specflow/units/compose" project-root) t)
           ;; Write control plane (Plan phase)
           (write-region
            "#+TITLE: Test Control Plane

* Project
  :PROPERTIES:
  :SPEC_FLOW_PHASE: Plan
  :SPEC_FLOW_ACTIVE_UNIT: compose
  :END:

* Units

** docs
   :PROPERTIES:
   :SPEC: .specflow/units/docs/spec.org
   :TODO: .specflow/units/docs/todo.org
   :CHILDREN: compose
   :END:

** compose
   :PROPERTIES:
   :PARENT: docs
   :SPEC: .specflow/units/compose/spec.org
   :TODO: .specflow/units/compose/todo.org
   :END:
"
            nil (expand-file-name ".specflow/specflow.org" project-root))
           ;; Write root todo.org
           (write-region
            "#+TITLE: Test TODO

* Active

** NEXT compose: Plan phase
   Planning the compose unit.
"
            nil (expand-file-name ".specflow/todo.org" project-root))
           ;; Write docs files
           (write-region "Docs spec content" nil
                         (expand-file-name ".specflow/units/docs/spec.org" project-root))
           (write-region "Docs todo content" nil
                         (expand-file-name ".specflow/units/docs/todo.org" project-root))
           ;; Write compose files
           (write-region "Compose spec content" nil
                         (expand-file-name ".specflow/units/compose/spec.org" project-root))
           (write-region "Compose todo content" nil
                         (expand-file-name ".specflow/units/compose/todo.org" project-root))
           ,@body)
       ;; Cleanup
       (delete-directory project-root t))))

(defmacro specflow-test-with-implement-phase (&rest body)
  "Create test project in Implement phase and execute BODY."
  (declare (indent 0))
  `(let ((project-root (make-temp-file "specflow-test-" t)))
     (unwind-protect
         (progn
           (make-directory (expand-file-name ".git" project-root) t)
           (make-directory (expand-file-name ".specflow" project-root) t)
           (write-region
            "#+TITLE: Test Control Plane

* Project
  :PROPERTIES:
  :SPEC_FLOW_PHASE: Implement
  :SPEC_FLOW_ACTIVE_UNIT: compose
  :END:

* Units

** compose
   :PROPERTIES:
   :SPEC: .specflow/units/compose/spec.org
   :END:
"
            nil (expand-file-name ".specflow/specflow.org" project-root))
           ,@body)
       (delete-directory project-root t))))

;;;; Template Structure Tests

(ert-deftest specflow-test-compose-template-new-unit ()
  "Test new-unit template has correct structure."
  (let ((template (specflow-compose--template-new-unit)))
    (should (= 8 (length template)))
    ;; Required fields
    (should (cdr (assoc "Unit Name" template)))
    (should (cdr (assoc "Parent" template)))
    (should (cdr (assoc "Purpose (one line)" template)))
    (should (cdr (assoc "In Scope" template)))
    ;; Optional fields
    (should-not (cdr (assoc "Out of Scope" template)))
    (should-not (cdr (assoc "Dependencies" template)))))

(ert-deftest specflow-test-compose-template-edit-spec ()
  "Test edit-spec template has correct structure."
  (let ((template (specflow-compose--template-edit-spec)))
    (should (= 4 (length template)))
    (should (cdr (assoc "Which Unit" template)))
    (should (cdr (assoc "What to Change" template)))
    (should (cdr (assoc "Why (rationale)" template)))
    (should-not (cdr (assoc "Constraints" template)))))

(ert-deftest specflow-test-compose-template-new-feature ()
  "Test new-feature template has correct structure."
  (let ((template (specflow-compose--template-new-feature)))
    (should (= 5 (length template)))
    (should (cdr (assoc "Which Unit" template)))
    (should (cdr (assoc "Feature Description" template)))
    (should (cdr (assoc "In Scope" template)))
    (should (cdr (assoc "Affects Parent Architecture? (yes/no/unsure)" template)))))

(ert-deftest specflow-test-compose-template-refactor ()
  "Test refactor template has correct structure."
  (let ((template (specflow-compose--template-refactor)))
    (should (= 4 (length template)))
    (should (cdr (assoc "Which Unit" template)))
    (should (cdr (assoc "What to Refactor" template)))
    (should (cdr (assoc "Why (rationale)" template)))))

;;;; Phase Enforcement Tests

(ert-deftest specflow-test-compose-check-plan-phase-allowed ()
  "Test that Plan phase allows compose commands."
  (specflow-test-with-compose-project
    (let ((default-directory project-root))
      (should (specflow-compose--check-plan-phase)))))

(ert-deftest specflow-test-compose-check-plan-phase-denied ()
  "Test that non-Plan phase denies compose commands."
  (specflow-test-with-implement-phase
    (let ((default-directory project-root))
      (should-not (specflow-compose--check-plan-phase)))))

;;;; Buffer Creation Tests

(ert-deftest specflow-test-compose-create-buffer ()
  "Test that create-buffer produces correct structure."
  (specflow-test-with-compose-project
    (let ((default-directory project-root))
      (specflow-compose--create-buffer
       'new-unit "Test" '(("Question 1" . t) ("Question 2" . nil)))
      (let ((buf (get-buffer "*SpecFlow Compose: Test*")))
        (unwind-protect
            (with-current-buffer buf
              (should specflow-compose-mode)
              (should (eq specflow-compose--task-type 'new-unit))
              (let ((content (buffer-string)))
                (should (string-match-p "\\* Question 1 (required)" content))
                (should (string-match-p "\\* Question 2\n" content))
                (should (string-match-p "C-c C-c" content))
                (should (string-match-p "C-c C-k" content))))
          (kill-buffer buf))))))

(ert-deftest specflow-test-compose-create-buffer-with-default ()
  "Test that create-buffer inserts default unit."
  (specflow-test-with-compose-project
    (let ((default-directory project-root))
      (specflow-compose--create-buffer
       'edit-spec "Test" '(("Which Unit" . t)) "compose")
      (let ((buf (get-buffer "*SpecFlow Compose: Test*")))
        (unwind-protect
            (with-current-buffer buf
              (let ((content (buffer-string)))
                (should (string-match-p "compose" content))))
          (kill-buffer buf))))))

;;;; Answer Extraction Tests

(ert-deftest specflow-test-compose-extract-answers ()
  "Test extracting answers from compose buffer."
  (with-temp-buffer
    (insert "#+TITLE: Test\n\n")
    (insert "* Question One\nAnswer one\n\n")
    (insert "* Question Two\nAnswer two\n\n")
    (insert "────────────────\n")
    (let ((answers (specflow-compose--extract-answers)))
      (should (equal 2 (length answers)))
      (should (equal "Answer one" (cdr (assoc "Question One" answers))))
      (should (equal "Answer two" (cdr (assoc "Question Two" answers)))))))

(ert-deftest specflow-test-compose-extract-answers-multiline ()
  "Test extracting multiline answers."
  (with-temp-buffer
    (insert "#+TITLE: Test\n\n")
    (insert "* Question\nLine one\nLine two\nLine three\n\n")
    (insert "────────────────\n")
    (let ((answers (specflow-compose--extract-answers)))
      (should (string-match-p "Line one" (cdr (car answers))))
      (should (string-match-p "Line two" (cdr (car answers))))
      (should (string-match-p "Line three" (cdr (car answers)))))))

(ert-deftest specflow-test-compose-extract-answers-empty ()
  "Test that empty answers are extracted as empty strings."
  (with-temp-buffer
    (insert "#+TITLE: Test\n\n")
    (insert "* Question One\n\n")
    (insert "* Question Two\nHas answer\n")
    (insert "────────────────\n")
    (let ((answers (specflow-compose--extract-answers)))
      (should (equal "" (cdr (assoc "Question One" answers))))
      (should (equal "Has answer" (cdr (assoc "Question Two" answers)))))))

;;;; Context File Selection Tests

(ert-deftest specflow-test-compose-context-new-unit ()
  "Test context files for new-unit include parent spec."
  (specflow-test-with-compose-project
    (let ((default-directory project-root))
      (let ((files (specflow-compose--context-files-new-unit)))
        (should (cl-some (lambda (f) (string-match-p "docs/spec.org" (car f))) files))
        (should (cl-some (lambda (f) (string-match-p "specflow.org" (car f))) files))
        (should (cl-some (lambda (f) (string-match-p "todo.org" (car f))) files))))))

(ert-deftest specflow-test-compose-context-edit-spec ()
  "Test context files for edit-spec include unit spec."
  (specflow-test-with-compose-project
    (let ((default-directory project-root))
      (let ((files (specflow-compose--context-files-edit-spec "compose")))
        (should (cl-some (lambda (f) (string-match-p "spec.org" (car f))) files))
        (should (cl-some (lambda (f) (string-match-p "specflow.org" (car f))) files))))))

(ert-deftest specflow-test-compose-context-new-feature-with-parent ()
  "Test context files for new-feature when affects parent."
  (specflow-test-with-compose-project
    (let ((default-directory project-root))
      (let ((files (specflow-compose--context-files-new-feature "compose" "yes")))
        (should (cl-some (lambda (f) (string-match-p "spec.org" (car f))) files))
        (should (cl-some (lambda (f) (string-match-p "todo.org" (car f))) files))
        ;; Should include parent spec
        (should (cl-some (lambda (f) (string-match-p "parent:" (cdr f))) files))))))

(ert-deftest specflow-test-compose-context-new-feature-no-parent ()
  "Test context files for new-feature when does not affect parent."
  (specflow-test-with-compose-project
    (let ((default-directory project-root))
      (let ((files (specflow-compose--context-files-new-feature "compose" "no")))
        ;; Should NOT include parent spec
        (should-not (cl-some (lambda (f) (string-match-p "parent:" (cdr f))) files))))))

(ert-deftest specflow-test-compose-context-refactor ()
  "Test context files for refactor include spec and todo."
  (specflow-test-with-compose-project
    (let ((default-directory project-root))
      (let ((files (specflow-compose--context-files-refactor "compose")))
        (should (cl-some (lambda (f) (string-match-p "spec.org" (car f))) files))
        (should (cl-some (lambda (f) (string-match-p "todo.org" (car f))) files))))))

;;;; Prompt Generation Tests

(ert-deftest specflow-test-compose-prompt-includes-task ()
  "Test that generated prompt includes task description."
  (specflow-test-with-compose-project
    (let ((default-directory project-root))
      (let ((prompt (specflow-compose--generate-prompt
                     'new-unit
                     '(("Unit Name" . "test-unit")
                       ("Parent" . "docs")
                       ("Purpose (one line)" . "Test purpose")
                       ("Problem it solves" . "Test problem")
                       ("In Scope" . "Test scope")))))
        (should (string-match-p "## Task:" prompt))
        (should (string-match-p "test-unit" prompt))))))

(ert-deftest specflow-test-compose-prompt-includes-state ()
  "Test that generated prompt includes current state."
  (specflow-test-with-compose-project
    (let ((default-directory project-root))
      (let ((prompt (specflow-compose--generate-prompt
                     'new-unit
                     '(("Unit Name" . "test-unit")))))
        (should (string-match-p "### Current State" prompt))
        (should (string-match-p "Active unit: compose" prompt))
        (should (string-match-p "Phase: Plan" prompt))
        (should (string-match-p "Parent chain:" prompt))))))

(ert-deftest specflow-test-compose-prompt-includes-context-files ()
  "Test that generated prompt includes context files section."
  (specflow-test-with-compose-project
    (let ((default-directory project-root))
      (let ((prompt (specflow-compose--generate-prompt
                     'new-unit
                     '(("Unit Name" . "test-unit")))))
        (should (string-match-p "### Context Files" prompt))
        (should (string-match-p "Read these files" prompt))))))

(ert-deftest specflow-test-compose-prompt-includes-requirements ()
  "Test that generated prompt includes requirements from answers."
  (specflow-test-with-compose-project
    (let ((default-directory project-root))
      (let ((prompt (specflow-compose--generate-prompt
                     'new-unit
                     '(("Unit Name" . "test-unit")
                       ("Purpose (one line)" . "My specific purpose")))))
        (should (string-match-p "### Requirements" prompt))
        (should (string-match-p "My specific purpose" prompt))))))

(ert-deftest specflow-test-compose-prompt-includes-instructions ()
  "Test that generated prompt includes task-specific instructions."
  (specflow-test-with-compose-project
    (let ((default-directory project-root))
      (let ((prompt (specflow-compose--generate-prompt
                     'new-unit
                     '(("Unit Name" . "test-unit")))))
        (should (string-match-p "### Instructions" prompt))
        (should (string-match-p "Plan phase" prompt))))))

(ert-deftest specflow-test-compose-prompt-includes-artifact-preservation ()
  "Test that generated prompt includes artifact preservation section."
  (specflow-test-with-compose-project
    (let ((default-directory project-root))
      (let ((prompt (specflow-compose--generate-prompt
                     'new-unit
                     '(("Unit Name" . "test-unit")))))
        (should (string-match-p "### Artifact Preservation" prompt))
        (should (string-match-p "temp-planning-artifacts.org" prompt))))))

(ert-deftest specflow-test-compose-artifact-section-uses-unit-name ()
  "Test that artifact section uses the correct unit name."
  (let ((section (specflow-compose--artifact-preservation-section "myunit")))
    (should (string-match-p "units/myunit/temp-planning-artifacts.org" section))))

;;;; Instructions Tests

(ert-deftest specflow-test-compose-instructions-new-unit ()
  "Test new-unit instructions mention correct steps."
  (let ((instructions (specflow-compose--instructions-new-unit "myunit" "docs")))
    (should (string-match-p "parent unit spec" instructions))
    (should (string-match-p "control plane" instructions))
    (should (string-match-p "units/myunit" instructions))
    (should (string-match-p "spec.org" instructions))
    (should (string-match-p "todo.org" instructions))))

(ert-deftest specflow-test-compose-instructions-edit-spec ()
  "Test edit-spec instructions."
  (let ((instructions (specflow-compose--instructions-edit-spec "myunit")))
    (should (string-match-p "units/myunit/spec.org" instructions))
    (should (string-match-p "parent constraints" instructions))))

(ert-deftest specflow-test-compose-instructions-new-feature-affects-parent ()
  "Test new-feature instructions when affects parent."
  (let ((instructions (specflow-compose--instructions-new-feature "myunit" "yes")))
    (should (string-match-p "affects parent" instructions))
    (should (string-match-p "parent specs first" instructions))))

(ert-deftest specflow-test-compose-instructions-new-feature-no-parent ()
  "Test new-feature instructions when does not affect parent."
  (let ((instructions (specflow-compose--instructions-new-feature "myunit" "no")))
    (should (string-match-p "child unit" instructions))))

(ert-deftest specflow-test-compose-instructions-refactor ()
  "Test refactor instructions."
  (let ((instructions (specflow-compose--instructions-refactor "myunit")))
    (should (string-match-p "refactor" instructions))
    (should (string-match-p "behavior is preserved" instructions))))

;;;; Format Helper Tests

(ert-deftest specflow-test-compose-format-requirements-single-line ()
  "Test formatting single-line answers."
  (let ((formatted (specflow-compose--format-requirements
                    '(("Question" . "Answer")))))
    (should (string-match-p "- Question: Answer" formatted))))

(ert-deftest specflow-test-compose-format-requirements-multiline ()
  "Test formatting multiline answers."
  (let ((formatted (specflow-compose--format-requirements
                    '(("Question" . "Line 1\nLine 2")))))
    (should (string-match-p "- Question:" formatted))
    (should (string-match-p "  - Line 1" formatted))
    (should (string-match-p "  - Line 2" formatted))))

(ert-deftest specflow-test-compose-format-requirements-empty-skipped ()
  "Test that empty answers are skipped."
  (let ((formatted (specflow-compose--format-requirements
                    '(("Empty" . "")
                      ("Has Value" . "value")))))
    (should-not (string-match-p "Empty" formatted))
    (should (string-match-p "Has Value: value" formatted))))

(ert-deftest specflow-test-compose-format-context-files ()
  "Test formatting context files."
  (let ((formatted (specflow-compose--format-context-files
                    '(("path/to/file.org" . "description")))))
    (should (string-match-p "Read these files" formatted))
    (should (string-match-p "- path/to/file.org (description)" formatted))))

;;;; Minor Mode Tests

(ert-deftest specflow-test-compose-mode-keymap ()
  "Test that compose mode has correct keybindings."
  (should (keymapp specflow-compose-mode-map))
  (should (eq (lookup-key specflow-compose-mode-map (kbd "C-c C-c"))
              'specflow-compose--generate))
  (should (eq (lookup-key specflow-compose-mode-map (kbd "C-c C-k"))
              'specflow-compose--cancel)))

;;;; Phase Completion Tests

(ert-deftest specflow-test-compose-next-phase-plan ()
  "Test that Plan phase transitions to Specify."
  (should (equal "Specify" (specflow-compose--next-phase "Plan")))
  (should (equal "Specify" (specflow-compose--next-phase "plan"))))

(ert-deftest specflow-test-compose-next-phase-specify ()
  "Test that Specify phase transitions to Scaffold."
  (should (equal "Scaffold" (specflow-compose--next-phase "Specify")))
  (should (equal "Scaffold" (specflow-compose--next-phase "specify"))))

(ert-deftest specflow-test-compose-next-phase-scaffold ()
  "Test that Scaffold phase transitions to Implement."
  (should (equal "Implement" (specflow-compose--next-phase "Scaffold")))
  (should (equal "Implement" (specflow-compose--next-phase "scaffold"))))

(ert-deftest specflow-test-compose-next-phase-implement ()
  "Test that Implement phase transitions to Validate."
  (should (equal "Validate" (specflow-compose--next-phase "Implement")))
  (should (equal "Validate" (specflow-compose--next-phase "implement"))))

(ert-deftest specflow-test-compose-next-phase-validate ()
  "Test that Validate phase transitions to Document."
  (should (equal "Document" (specflow-compose--next-phase "Validate")))
  (should (equal "Document" (specflow-compose--next-phase "validate"))))

(ert-deftest specflow-test-compose-next-phase-document ()
  "Test that Document phase has no next phase."
  (should-not (specflow-compose--next-phase "Document"))
  (should-not (specflow-compose--next-phase "document")))

(ert-deftest specflow-test-compose-phase-completion-section-has-checklist ()
  "Test that phase completion section includes checklist items."
  (let ((section (specflow-compose--phase-completion-section "Plan" "myunit")))
    (should (string-match-p "### Phase Completion Checklist" section))
    (should (string-match-p "Update .specflow/todo.org" section))
    (should (string-match-p "Update control plane" section))
    (should (string-match-p "Commit:" section))))

(ert-deftest specflow-test-compose-phase-completion-section-uses-unit-name ()
  "Test that phase completion section interpolates unit name."
  (let ((section (specflow-compose--phase-completion-section "Plan" "myunit")))
    (should (string-match-p "myunit: Plan phase" section))
    (should (string-match-p "myunit: Specify phase" section))
    (should (string-match-p "myunit: complete Plan phase" section))))

(ert-deftest specflow-test-compose-phase-completion-section-document-complete ()
  "Test that Document phase shows unit complete message."
  (let ((section (specflow-compose--phase-completion-section "Document" "myunit")))
    (should (string-match-p "(unit complete)" section))))

(ert-deftest specflow-test-compose-prompt-includes-phase-completion ()
  "Test that generated prompt includes phase completion checklist."
  (specflow-test-with-compose-project
    (let ((default-directory project-root))
      (let ((prompt (specflow-compose--generate-prompt
                     'new-unit
                     '(("Unit Name" . "test-unit")))))
        (should (string-match-p "### Phase Completion Checklist" prompt))
        (should (string-match-p "Update .specflow/todo.org" prompt))
        (should (string-match-p "Update control plane" prompt))
        (should (string-match-p "test-unit: Plan phase" prompt))))))

(provide 'test-specflow-compose)
;;; test-specflow-compose.el ends here
