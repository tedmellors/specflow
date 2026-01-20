;;; test-specflow-rules.el --- Tests for specflow-rules -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT tests for specflow-rules functions.

;;; Code:

(require 'ert)
(require 'specflow-rules)

;;;; Test Helpers

(defmacro specflow-rules-test-with-temp-project (project-structure &rest body)
  "Create a temporary project with PROJECT-STRUCTURE and execute BODY.
PROJECT-STRUCTURE is a list of relative file paths to create.
Each path ending in / creates a directory, otherwise creates an empty file.
The macro binds `project-root' to the temporary directory."
  (declare (indent 1))
  `(let ((project-root (make-temp-file "specflow-rules-test-" t)))
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

;;;; Test Fixtures

(defconst specflow-rules-test-valid-rules
  "#+TITLE: SpecFlow – Operational Rules
#+STARTUP: overview

* Control Plane Authority
  :PROPERTIES:
  :RULE_ID: control-plane-authority
  :PRIORITY: mandatory
  :PHASE: all
  :TAGS: control-plane startup
  :END:

  The control plane is authoritative for project state.
  Always read it before starting work.

* Plan Phase Rules
  :PROPERTIES:
  :RULE_ID: plan-phase
  :PRIORITY: mandatory
  :PHASE: plan
  :TAGS: phase planning
  :END:

  In Plan phase:
  - Do NOT write code
  - Summarize understanding
  - Identify constraints

* Documentation Guidelines
  :PROPERTIES:
  :RULE_ID: documentation-guidelines
  :PRIORITY: recommended
  :PHASE: document
  :TAGS: docs writing
  :END:

  Write clear, concise documentation.

* Optional Helpers
  :PROPERTIES:
  :RULE_ID: optional-helpers
  :PRIORITY: optional
  :PHASE: all
  :TAGS: helpers utilities
  :END:

  Optional helper functions may be used.
"
  "Valid rules.org content for testing.")

(defconst specflow-rules-test-missing-rule-id
  "#+TITLE: Test Rules

* Bad Rule
  :PROPERTIES:
  :PRIORITY: mandatory
  :PHASE: all
  :END:

  This rule is missing RULE_ID.
"
  "Rules file missing RULE_ID property.")

(defconst specflow-rules-test-missing-priority
  "#+TITLE: Test Rules

* Bad Rule
  :PROPERTIES:
  :RULE_ID: bad-rule
  :PHASE: all
  :END:

  This rule is missing PRIORITY.
"
  "Rules file missing PRIORITY property.")

(defconst specflow-rules-test-missing-phase
  "#+TITLE: Test Rules

* Bad Rule
  :PROPERTIES:
  :RULE_ID: bad-rule
  :PRIORITY: mandatory
  :END:

  This rule is missing PHASE.
"
  "Rules file missing PHASE property.")

;;;; Discovery Tests

(ert-deftest specflow-rules-test-find-file-at-root ()
  "Test finding rules.org at project root."
  (specflow-rules-test-with-temp-project
      '(".git/" "rules.org")
    (let ((expected (expand-file-name "rules.org" project-root)))
      (should (equal (specflow-rules-find-file project-root) expected)))))

(ert-deftest specflow-rules-test-find-file-from-subdir ()
  "Test finding rules.org from a subdirectory."
  (specflow-rules-test-with-temp-project
      '(".git/" "rules.org" "src/foo/bar/")
    (let ((start-dir (expand-file-name "src/foo/bar" project-root))
          (expected (expand-file-name "rules.org" project-root)))
      (should (equal (specflow-rules-find-file start-dir) expected)))))

(ert-deftest specflow-rules-test-find-file-not-found ()
  "Test error when rules.org not found."
  (specflow-rules-test-with-temp-project
      '(".git/" "src/")
    (should-error (specflow-rules-find-file project-root)
                  :type 'specflow-rules-file-not-found)))

(ert-deftest specflow-rules-test-find-file-returns-absolute ()
  "Test that returned path is absolute."
  (specflow-rules-test-with-temp-project
      '(".git/" "rules.org")
    (let ((result (specflow-rules-find-file project-root)))
      (should (file-name-absolute-p result)))))

;;;; Parse Tests

(ert-deftest specflow-rules-test-load-valid ()
  "Test loading valid rules file."
  (specflow-rules-test-with-temp-project
      '(".git/")
    (let ((rules-path (expand-file-name "rules.org" project-root)))
      (write-region specflow-rules-test-valid-rules nil rules-path)
      (let ((rules (specflow-rules-load rules-path)))
        (should (= (length rules) 4))
        ;; Check first rule
        (let ((first (nth 0 rules)))
          (should (equal (plist-get first :id) "control-plane-authority"))
          (should (equal (plist-get first :title) "Control Plane Authority"))
          (should (equal (plist-get first :priority) "mandatory"))
          (should (equal (plist-get first :phase) "all"))
          (should (equal (plist-get first :tags) '("control-plane" "startup"))))))))

(ert-deftest specflow-rules-test-load-content-captured ()
  "Test that rule content is captured correctly."
  (specflow-rules-test-with-temp-project
      '(".git/")
    (let ((rules-path (expand-file-name "rules.org" project-root)))
      (write-region specflow-rules-test-valid-rules nil rules-path)
      (let* ((rules (specflow-rules-load rules-path))
             (first (nth 0 rules))
             (content (plist-get first :content)))
        (should (string-match-p "control plane is authoritative" content))))))

(ert-deftest specflow-rules-test-load-missing-rule-id ()
  "Test error when RULE_ID is missing."
  (specflow-rules-test-with-temp-project
      '(".git/")
    (let ((rules-path (expand-file-name "rules.org" project-root)))
      (write-region specflow-rules-test-missing-rule-id nil rules-path)
      (should-error (specflow-rules-load rules-path)
                    :type 'specflow-rules-malformed))))

(ert-deftest specflow-rules-test-load-missing-priority ()
  "Test error when PRIORITY is missing."
  (specflow-rules-test-with-temp-project
      '(".git/")
    (let ((rules-path (expand-file-name "rules.org" project-root)))
      (write-region specflow-rules-test-missing-priority nil rules-path)
      (should-error (specflow-rules-load rules-path)
                    :type 'specflow-rules-malformed))))

(ert-deftest specflow-rules-test-load-missing-phase ()
  "Test error when PHASE is missing."
  (specflow-rules-test-with-temp-project
      '(".git/")
    (let ((rules-path (expand-file-name "rules.org" project-root)))
      (write-region specflow-rules-test-missing-phase nil rules-path)
      (should-error (specflow-rules-load rules-path)
                    :type 'specflow-rules-malformed))))

(ert-deftest specflow-rules-test-load-deterministic ()
  "Test that loading twice returns identical results."
  (specflow-rules-test-with-temp-project
      '(".git/")
    (let ((rules-path (expand-file-name "rules.org" project-root)))
      (write-region specflow-rules-test-valid-rules nil rules-path)
      (should (equal (specflow-rules-load rules-path)
                     (specflow-rules-load rules-path))))))

(ert-deftest specflow-rules-test-load-tags-as-list ()
  "Test that tags are parsed as a list."
  (specflow-rules-test-with-temp-project
      '(".git/")
    (let ((rules-path (expand-file-name "rules.org" project-root)))
      (write-region specflow-rules-test-valid-rules nil rules-path)
      (let* ((rules (specflow-rules-load rules-path))
             (first (nth 0 rules))
             (tags (plist-get first :tags)))
        (should (listp tags))
        (should (= (length tags) 2))))))

;;;; Filter by Phase Tests

(ert-deftest specflow-rules-test-for-phase-matches ()
  "Test filtering by specific phase."
  (specflow-rules-test-with-temp-project
      '(".git/")
    (let ((rules-path (expand-file-name "rules.org" project-root)))
      (write-region specflow-rules-test-valid-rules nil rules-path)
      (let ((rules (specflow-rules-for-phase "plan" rules-path)))
        ;; Should get plan-phase rule AND all "all" phase rules
        (should (>= (length rules) 1))
        (should (cl-some (lambda (r) (string= (plist-get r :id) "plan-phase")) rules))))))

(ert-deftest specflow-rules-test-for-phase-includes-all ()
  "Test that 'all' phase rules are always included."
  (specflow-rules-test-with-temp-project
      '(".git/")
    (let ((rules-path (expand-file-name "rules.org" project-root)))
      (write-region specflow-rules-test-valid-rules nil rules-path)
      (let ((rules (specflow-rules-for-phase "plan" rules-path)))
        (should (cl-some (lambda (r) (string= (plist-get r :id) "control-plane-authority")) rules))))))

(ert-deftest specflow-rules-test-for-phase-case-insensitive ()
  "Test case-insensitive phase matching."
  (specflow-rules-test-with-temp-project
      '(".git/")
    (let ((rules-path (expand-file-name "rules.org" project-root)))
      (write-region specflow-rules-test-valid-rules nil rules-path)
      (let ((rules-lower (specflow-rules-for-phase "plan" rules-path))
            (rules-upper (specflow-rules-for-phase "PLAN" rules-path)))
        (should (equal rules-lower rules-upper))))))

(ert-deftest specflow-rules-test-for-phase-empty-result ()
  "Test empty result for non-matching phase."
  (specflow-rules-test-with-temp-project
      '(".git/")
    (let ((rules-path (expand-file-name "rules.org" project-root)))
      (write-region specflow-rules-test-valid-rules nil rules-path)
      ;; scaffold phase should only get "all" rules, not scaffold-specific
      (let ((rules (specflow-rules-for-phase "scaffold" rules-path)))
        ;; Should still get "all" phase rules
        (should (cl-every (lambda (r) (string= (plist-get r :phase) "all")) rules))))))

;;;; Filter by Priority Tests

(ert-deftest specflow-rules-test-mandatory-only ()
  "Test filtering for mandatory rules only."
  (specflow-rules-test-with-temp-project
      '(".git/")
    (let ((rules-path (expand-file-name "rules.org" project-root)))
      (write-region specflow-rules-test-valid-rules nil rules-path)
      (let ((rules (specflow-rules-mandatory rules-path)))
        (should (= (length rules) 2))
        (should (cl-every (lambda (r) (string= (plist-get r :priority) "mandatory")) rules))))))

(ert-deftest specflow-rules-test-mandatory-excludes-others ()
  "Test that mandatory excludes recommended and optional."
  (specflow-rules-test-with-temp-project
      '(".git/")
    (let ((rules-path (expand-file-name "rules.org" project-root)))
      (write-region specflow-rules-test-valid-rules nil rules-path)
      (let ((rules (specflow-rules-mandatory rules-path)))
        (should-not (cl-some (lambda (r) (string= (plist-get r :priority) "recommended")) rules))
        (should-not (cl-some (lambda (r) (string= (plist-get r :priority) "optional")) rules))))))

;;;; Filter by Tag Tests

(ert-deftest specflow-rules-test-by-tag-matches ()
  "Test filtering by tag."
  (specflow-rules-test-with-temp-project
      '(".git/")
    (let ((rules-path (expand-file-name "rules.org" project-root)))
      (write-region specflow-rules-test-valid-rules nil rules-path)
      (let ((rules (specflow-rules-by-tag "control-plane" rules-path)))
        (should (= (length rules) 1))
        (should (string= (plist-get (car rules) :id) "control-plane-authority"))))))

(ert-deftest specflow-rules-test-by-tag-case-insensitive ()
  "Test case-insensitive tag matching."
  (specflow-rules-test-with-temp-project
      '(".git/")
    (let ((rules-path (expand-file-name "rules.org" project-root)))
      (write-region specflow-rules-test-valid-rules nil rules-path)
      (let ((rules-lower (specflow-rules-by-tag "control-plane" rules-path))
            (rules-upper (specflow-rules-by-tag "CONTROL-PLANE" rules-path)))
        (should (equal rules-lower rules-upper))))))

(ert-deftest specflow-rules-test-by-tag-no-match ()
  "Test empty result for non-matching tag."
  (specflow-rules-test-with-temp-project
      '(".git/")
    (let ((rules-path (expand-file-name "rules.org" project-root)))
      (write-region specflow-rules-test-valid-rules nil rules-path)
      (let ((rules (specflow-rules-by-tag "nonexistent-tag" rules-path)))
        (should (null rules))))))

;;;; Format Tests

(ert-deftest specflow-rules-test-format-contains-titles ()
  "Test that formatted output contains rule titles."
  (specflow-rules-test-with-temp-project
      '(".git/")
    (let ((rules-path (expand-file-name "rules.org" project-root)))
      (write-region specflow-rules-test-valid-rules nil rules-path)
      (let* ((rules (specflow-rules-load rules-path))
             (formatted (specflow-rules-format-for-context rules)))
        (should (string-match-p "Control Plane Authority" formatted))
        (should (string-match-p "Plan Phase Rules" formatted))))))

(ert-deftest specflow-rules-test-format-contains-priority ()
  "Test that formatted output contains priority markers."
  (specflow-rules-test-with-temp-project
      '(".git/")
    (let ((rules-path (expand-file-name "rules.org" project-root)))
      (write-region specflow-rules-test-valid-rules nil rules-path)
      (let* ((rules (specflow-rules-load rules-path))
             (formatted (specflow-rules-format-for-context rules)))
        (should (string-match-p "\\[mandatory\\]" formatted))
        (should (string-match-p "\\[recommended\\]" formatted))))))

(ert-deftest specflow-rules-test-format-contains-content ()
  "Test that formatted output contains rule content."
  (specflow-rules-test-with-temp-project
      '(".git/")
    (let ((rules-path (expand-file-name "rules.org" project-root)))
      (write-region specflow-rules-test-valid-rules nil rules-path)
      (let* ((rules (specflow-rules-load rules-path))
             (formatted (specflow-rules-format-for-context rules)))
        (should (string-match-p "control plane is authoritative" formatted))))))

(ert-deftest specflow-rules-test-format-separators ()
  "Test that rules are separated correctly."
  (specflow-rules-test-with-temp-project
      '(".git/")
    (let ((rules-path (expand-file-name "rules.org" project-root)))
      (write-region specflow-rules-test-valid-rules nil rules-path)
      (let* ((rules (specflow-rules-load rules-path))
             (formatted (specflow-rules-format-for-context rules)))
        (should (string-match-p "---" formatted))))))

;;;; All Rules Tests

(ert-deftest specflow-rules-test-all-returns-everything ()
  "Test that specflow-rules-all returns all rules."
  (specflow-rules-test-with-temp-project
      '(".git/")
    (let ((rules-path (expand-file-name "rules.org" project-root)))
      (write-region specflow-rules-test-valid-rules nil rules-path)
      (let ((rules (specflow-rules-all rules-path)))
        (should (= (length rules) 4))))))

(provide 'test-specflow-rules)

;;; test-specflow-rules.el ends here
