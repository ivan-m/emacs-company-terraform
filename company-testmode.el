(require 'company)
(require 'cl-lib)
(require 'terraform-mode)

(defconst terraform-toplevel-keywords
  '(
    ("resource" "Defines a new resource")
    ("variable" "Defines a variable or module input")
    ("data" "Defines a new data source")
    ("output" "Defines an output value or module output")
    ))

(defconst terraform-interpolation-extra
  '(("module." "References a module")
    ("var." "References a variable")
    ("data." "References a data source")
    ))

(setq terraform-resource-arguments-hash
      (make-hash-table :test `equal))
(setq terraform-data-arguments-hash
      (make-hash-table :test `equal))
(setq terraform-resource-attributes-hash
      (make-hash-table :test `equal))
(setq terraform-data-attributes-hash
      (make-hash-table :test `equal))

(defun company-terraform-load-data ()
  (interactive)
  (let ((datafile (expand-file-name "data.el" (file-name-directory (or load-file-name buffer-file-name)))))
    (load-file datafile)))

(defun test-parser-string ()
  (interactive)
  (message "%s" (nth 3 (syntax-ppss))))

(defun company-terraform-get-context ()
  (let ((nest-level (nth 0 (syntax-ppss)))
        (curr-ppos (nth 1 (syntax-ppss)))
        (string-state (nth 3 (syntax-ppss)))
        (string-ppos (nth 8 (syntax-ppss))))
    (cond
     ; object kind
     ((and string-state
           (save-excursion
             (goto-char string-ppos)
             (re-search-backward "\\(resource\\|data\\)[[:space:]\n]*\\=" nil t)))
      (list 'object-type (match-string-no-properties 0)))
     ; string interpolation
     ((and (> nest-level 0)
           string-state
           (save-excursion
             (re-search-backward "\\${[^\"]*\\=" nil t)))
      (list 'interpolation (buffer-substring (point)
                                             (save-excursion
                                               (skip-syntax-backward "w.")
                                               (point)))))
     ; resource/data block
     ((and (eq ?{ (char-after curr-ppos))
           (save-excursion
             (goto-char curr-ppos)
             (re-search-backward "\\(resource\\|data\\)[[:space:]\n]*\"\\([^\"]*\\)\"[[:space:]\n]*\"[^\"]*\"[[:space:]\n]*\\=" nil t)
             ))
           
      (list (match-string-no-properties 1) (match-string-no-properties 2)))
     ; top level
     ((eq 0 nest-level) 'top-level)
    (t 'no-idea))))

(defun test-context ()
  (interactive)
  (message "context: %s" (company-terraform-get-context)))

(defun company-terraform-prefix ()
  (if (eq major-mode 'terraform-mode)
      (let ((context (company-terraform-get-context)))
        (cond
         ((eq 'top-level context) (company-grab-symbol))
         ((eq (car context) 'interpolation) (cons (car (last (split-string (nth 1 context) "\\."))) t))
         ((eq (car context) 'object-type) (company-grab-symbol-cons "\"" 1))
         ((equal (car context) "resource") (company-grab-symbol))
         ((equal (car context) "data") (company-grab-symbol))
         (t (company-grab-symbol))))
    nil))

(defun company-terraform-make-candidate (candidate)
  (let ((text (nth 0 candidate))
        (meta (nth 1 candidate)))
    (propertize text 'meta meta)))

(defun filter-prefix (prefix list)
  (let (res)
    (dolist (item list)
      (when (string-prefix-p prefix item)
        (push item res)))
    res))

(defun filter-prefix-with-doc (prefix lists &optional multi)
  (if (not multi) (setq lists (list lists)))
  (let (res)
    (dolist (l lists)
      (dolist (item l)
        (when (string-prefix-p prefix (car item))
          (push (company-terraform-make-candidate item) res))))
      res))

(defun company-terraform-candidates (prefix)
  (let ((context (company-terraform-get-context)))
    ;(message "%s" context)
    (cond
     ((eq 'top-level context)
      (filter-prefix-with-doc prefix terraform-toplevel-keywords))
     ((and (eq    (nth 0 context) 'object-type)
           (equal (nth 1 context) "resource ")) ; ??? Why is this space necessary?!
      (filter-prefix-with-doc prefix terraform-resources-list))
     ((and (eq    (nth 0 context) 'object-type)
           (equal (nth 1 context) "data ")) ; ??? Why is this space necessary?!
      (filter-prefix-with-doc prefix terraform-data-list))
     ((equal (car context) "resource")
      (filter-prefix-with-doc prefix (gethash (nth 1 context) terraform-resource-arguments-hash)))
     ((equal (car context) "data")
      (filter-prefix-with-doc prefix (gethash (nth 1 context) terraform-data-hash)))
     ((equal (car context) 'interpolation)
      (let ((a (split-string (nth 1 context) "\\.")))
        (cond
         ((eq (length a) 1)
          (filter-prefix-with-doc prefix (list terraform-interpolation-functions
                                               terraform-resources-list
                                               terraform-interpolation-extra) t))
         ((and (eq (length a) 2)
               (equal (nth 0 a) "data"))
          (filter-prefix-with-doc (nth 1 a) terraform-data-list))
         ((and (eq (length a) 3))
          (filter-prefix-with-doc (nth 2 a) (list (gethash (nth 0 a) terraform-resource-arguments-hash)
                                                  (gethash (nth 0 a) terraform-resource-attributes-hash)) t))
         ((and (eq (length a) 4)
               (equal (nth 0 a) "data"))
          (filter-prefix-with-doc (nth 3 a) (list (gethash (nth 1 a) terraform-data-arguments-hash)
                                                  (gethash (nth 1 a) terraform-data-attributes-hash)) t))
         (t nil))))
     (t nil))))

(defun company-terraform-meta (candidate)
  (get-text-property 0 'meta candidate))

(defun company-terraform-docstring (candidate)
  (company-doc-buffer (company-terraform-meta candidate)))

(defun company-terraform-backend (command &optional arg &rest ignored)
  (interactive (list 'interactive))
  (cl-case command
    (interactive (company-begin-backend 'company-test-backend))
    (prefix (company-terraform-prefix))
    (candidates (company-terraform-candidates arg))
    (meta (company-terraform-meta arg))
    (doc-buffer (company-terraform-docstring arg))
    (init (if (not (bound-and-true-p company-terraform-initialized))
              (progn
                (company-terraform-load-data)
                (setq company-terraform-initialized t))))))


(add-to-list 'company-backends 'company-terraform-backend)

(company-terraform-load-data)
(message "eval success")
