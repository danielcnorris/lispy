(require 'lispy)
(custom-set-variables
 '(indent-tabs-mode nil))

;; ——— Infrastructure ——————————————————————————————————————————————————————————
(defmacro lispy-with (in &rest body)
  `(with-temp-buffer
     (emacs-lisp-mode)
     (lispy-mode)
     (insert ,in)
     (when (search-backward "~" nil t)
       (delete-char 1)
       (set-mark (point))
       (goto-char (point-max)))
     (search-backward "|")
     (delete-char 1)
     ,@(mapcar (lambda (x) (if (stringp x) `(lispy-unalias ,x) x)) body)
     (insert "|")
     (when (region-active-p)
       (exchange-point-and-mark)
       (insert "~"))
     (buffer-substring-no-properties
      (point-min)
      (point-max))))

(defmacro lispy-with-value (in &rest body)
  `(with-temp-buffer
     (emacs-lisp-mode)
     (lispy-mode)
     (insert ,in)
     (when (search-backward "~" nil t)
       (delete-char 1)
       (set-mark (point))
       (goto-char (point-max)))
     (search-backward "|")
     (delete-char 1)
     ,@(mapcar (lambda (x) (if (stringp x) `(lispy-unalias ,x) x)) body)))

(defun lispy-decode-keysequence (str)
  "Decode STR from e.g. \"23ab5c\" to '(23 \"a\" \"b\" 5 \"c\")"
  (let ((table (copy-seq (syntax-table))))
    (loop for i from ?0 to ?9 do
         (modify-syntax-entry i "." table))
    (loop for i from ? to ? do
         (modify-syntax-entry i "w" table))
    (loop for i in '(? ?\( ?\) ?\[ ?\] ?{ ?} ?\" ?\')
       do (modify-syntax-entry i "w" table))
    (cl-mapcan (lambda (x)
                 (let ((y (ignore-errors (read x))))
                   (if (numberp y)
                       (list y)
                     (mapcar #'string x))))
               (with-syntax-table table
                 (split-string str "\\b" t)))))

(ert-deftest lispy-decode-keysequence ()
  (should (equal (lispy-decode-keysequence "23ab50c")
                 '(23 "a" "b" 50 "c")))
  (should (equal (lispy-decode-keysequence "3\C-d")
                 '(3 "")))
  (should (equal (lispy-decode-keysequence "3\C-?")
                 '(3 ""))))

(defun lispy-unalias (seq)
  "Emulate pressing keys decoded from SEQ."
  (let ((keys (lispy-decode-keysequence seq))
        key)
    (while (setq key (pop keys))
      (if (numberp key)
          (let ((current-prefix-arg (list key)))
            (when keys
              (lispy--unalias-key (pop keys))))
        (lispy--unalias-key key)))))

(defun lispy--unalias-key (key)
  "Call command that corresponds to KEY.
Insert KEY if there's no command."
  (let ((cmd (cdr (assoc 'lispy-mode (minor-mode-key-binding key)))))
    (if (or (and cmd (or (looking-at lispy-left)
                         (looking-back lispy-right)))
            (progn
              (setq cmd (key-binding key))
              (not (cond ((eq cmd 'self-insert-command))
                         ((string-match "^special" (symbol-name cmd)))))))
        (call-interactively cmd)
      (insert key))))

;; ——— Tests ———————————————————————————————————————————————————————————————————
(ert-deftest lispy-backward ()
  (should (string= (lispy-with "(|(a) (b) (c))" "[")
                   "|((a) (b) (c))"))
  (should (string= (lispy-with "((a)|)" "[")
                   "(|(a))"))
  (should (string= (lispy-with "((|a) (b) (c))" "[")
                   "(|(a) (b) (c))"))
  (should (string= (lispy-with "((a) |(b) (c))" "[")
                   "(|(a) (b) (c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "[[")
                   "|((a) (b) (c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "3[")
                   "|((a) (b) (c))"))
  (should (string= (lispy-with "((a) (b) (c)|)" "[")
                   "((a) (b) |(c))"))
  (should (string= (lispy-with "((a) (b) (c)|)" "4[")
                   "(|(a) (b) (c))"))
  (should (string= (lispy-with "((a) (b) (c)|)" "40[")
                   "(|(a) (b) (c))"))
  (should (string= (lispy-with "((b)|\"foo\")" "[")
                   "(|(b)\"foo\")"))
  (should (string= (lispy-with "(bar)\n;; (foo baar)|" "[")
                   "|(bar)\n;; (foo baar)"))
  (should (string= (lispy-with "(foo)\n;; (foo bar\n;;      tanf)|" "[")
                   "|(foo)\n;; (foo bar\n;;      tanf)")))

(ert-deftest lispy-out-forward ()
  (should (string= (lispy-with "(|(a) (b) (c))" "l")
                   "((a) (b) (c))|"))
  (should (string= (lispy-with "(|(a) (b) (c))" "ll")
                   "((a) (b) (c))|"))
  (should (string= (lispy-with "(|(a) (b) (c))" (lispy-out-forward 1))
                   "((a) (b) (c))|"))
  (should (string= (lispy-with "(|(a) (b) (c))"
                               (lispy-out-forward 1)
                               (lispy-out-forward 1))
                   "((a) (b) (c))|"))
  (should (string= (lispy-with "((|a) (b) (c))" (lispy-out-forward 1))
                   "((a)| (b) (c))"))
  (should (string= (lispy-with "((|a) (b) (c))"
                               (lispy-out-forward 1)
                               (lispy-out-forward 1))
                   "((a) (b) (c))|"))
  (should (string= (lispy-with "((|a) (b) (c))" (lispy-out-forward 2))
                   "((a) (b) (c))|"))
  (should (string= (lispy-with "((a) \"(|foo)\" (c))" (lispy-out-forward 2))
                   "((a) \"(foo)\" (c))|"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "l")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something))|))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "ll")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)))|)"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "3l")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something))))|"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "9l")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something))))|"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))" "l")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something))|))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))" "ll")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)))|)"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))" "3l")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something))))|"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))" "9l")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something))))|")))

(ert-deftest lispy-out-backward ()
  (should (string= (lispy-with "(|(a) (b) (c))" "h")
                   "|((a) (b) (c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "hh")
                   "|((a) (b) (c))"))
  (should (string= (lispy-with "((a)| (b) (c))" "h")
                   "|((a) (b) (c))"))
  (should (string= (lispy-with "((a) (b)| (c))" "h")
                   "|((a) (b) (c))"))
  (should (string= (lispy-with "((a) |(b) (c))" "h")
                   "|((a) (b) (c))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "h")
                   "(defun foo ()\n  (let ((a 1))\n    |(let ((b 2))\n      (something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "hh")
                   "(defun foo ()\n  |(let ((a 1))\n    (let ((b 2))\n      (something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "3h")
                   "|(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "9h")
                   "|(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))" "h")
                   "(defun foo ()\n  (let ((a 1))\n    |(let ((b 2))\n      (something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))" "hh")
                   "(defun foo ()\n  |(let ((a 1))\n    (let ((b 2))\n      (something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))" "3h")
                   "|(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))" "9h")
                   "|(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something))))"))
  (should (equal (lispy-with-value "|(foo)" (lispy-backward 1)) nil))
  (should (equal (lispy-with "((foo \"(\"))\n((foo \")\"))\n\"un|expected\"" (lispy-backward 1))
                 "((foo \"(\"))\n|((foo \")\"))\n\"unexpected\"")))

(ert-deftest lispy-flow ()
  (should (string= (lispy-with "(|(a) (b) (c))" "f")
                   "((a) |(b) (c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "ff")
                   "((a) (b) |(c))"))
  (should (string= (lispy-with "((a)| (b) (c))" "f")
                   "((a)| (b) (c))"))
  (should (string= (lispy-with "((a) (b)| (c))" "f")
                   "((a)| (b) (c))"))
  (should (string= (lispy-with "((a) |(b) (c))" "f")
                   "((a) (b) |(c))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "f")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))|\n      (something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "ff")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2)|)\n      (something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "3f")
                   "(defun foo ()\n  (let ((a 1))|\n    (let ((b 2))\n      (something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "9f")
                   "(defun foo ()|\n  (let ((a 1))\n    (let ((b 2))\n      (something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))" "f")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))" "ff")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))" "3f")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))")))

(ert-deftest lispy-down ()
  (should (string= (lispy-with "(|(a) (b) (c))" "j")
                   "((a) |(b) (c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "jj")
                   "((a) (b) |(c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "2j")
                   "((a) (b) |(c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "jjj")
                   "((a) (b) (c)|)"))
  (should (string= (lispy-with "(|(a) (b) (c))" "3j")
                   "((a) (b) (c)|)"))
  (should (string= (lispy-with "(|(a) (b) (c))" "jjjj")
                   "((a) (b) |(c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "4j")
                   "((a) (b) (c)|)"))
  (should (string= (lispy-with "(a)| (b)\n" "2j")
                   "(a) (b)|\n"))
  (should (string= (lispy-with "(foo\n |(one)\n two\n (three)\n (four))" "j")
                   "(foo\n (one)\n two\n |(three)\n (four))"))
  (should (string= (lispy-with "(foo\n |(one)\n two\n (three)\n (four))" "jj")
                   "(foo\n (one)\n two\n (three)\n |(four))"))
  (should (string= (lispy-with "(foo\n |(one)\n two\n (three)\n (four))" "jjj")
                   "(foo\n (one)\n two\n (three)\n (four)|)"))
  (should (string= (lispy-with "(foo\n (one)|\n two\n (three)\n (four))" "j")
                   "(foo\n (one)\n two\n (three)|\n (four))"))
  (should (string= (lispy-with "(foo\n (one)|\n two\n (three)\n (four))" "jj")
                   "(foo\n (one)\n two\n (three)\n (four)|)"))
  (should (string= (lispy-with "(foo\n (one)|\n two\n (three)\n (four))" "jjj")
                   "(foo\n (one)\n two\n (three)\n |(four))")))

(ert-deftest lispy-up ()
  (should (string= (lispy-with "((a) (b) (c)|)" "k")
                   "((a) (b)| (c))"))
  (should (string= (lispy-with "((a) (b) (c)|)" "kk")
                   "((a)| (b) (c))"))
  (should (string= (lispy-with "((a) (b) (c)|)" "2k")
                   "((a)| (b) (c))"))
  (should (string= (lispy-with "((a) (b) (c)|)" "kkk")
                   "(|(a) (b) (c))"))
  (should (string= (lispy-with "((a) (b) (c)|)" "3k")
                   "(|(a) (b) (c))"))
  (should (string= (lispy-with "((a) (b) (c)|)" "kkkk")
                   "((a)| (b) (c))"))
  (should (string= (lispy-with "((a) (b) (c)|)" "4k")
                   "(|(a) (b) (c))"))
  (should (string= (lispy-with ";; \n(foo)\n|(bar)" "2k")
                   ";; \n|(foo)\n(bar)"))
  (should (string= (lispy-with "(foo\n |(one)\n two\n (three)\n (four))" "k")
                   "(foo\n (one)|\n two\n (three)\n (four))"))
  (should (string= (lispy-with "(foo\n |(one)\n two\n (three)\n (four))" "kk")
                   "(foo\n |(one)\n two\n (three)\n (four))"))
  (should (string= (lispy-with "(foo\n (one)|\n two\n (three)\n (four))" "k")
                   "(foo\n |(one)\n two\n (three)\n (four))"))
  (should (string= (lispy-with "(foo\n (one)\n two\n (three)|\n (four))" "k")
                   "(foo\n (one)|\n two\n (three)\n (four))"))
  (should (string= (lispy-with "(foo\n (one)\n two\n (three)|\n (four))" "kk")
                   "(foo\n |(one)\n two\n (three)\n (four))"))
  (should (string= (lispy-with "(foo\n (one)\n two\n (three)\n (four)|)" "k")
                   "(foo\n (one)\n two\n (three)|\n (four))"))
  (should (string= (lispy-with "(foo\n (one)\n two\n (three)\n (four)|)" "kk")
                   "(foo\n (one)|\n two\n (three)\n (four))"))
  (should (string= (lispy-with "(foo\n (one)\n two\n (three)\n (four)|)" "kk")
                   "(foo\n (one)|\n two\n (three)\n (four))")))

(ert-deftest lispy-different ()
  (should (string= (lispy-with "((a) (b) (c)|)" "d")
                   "((a) (b) |(c))"))
  (should (string= (lispy-with "((a) (b) (c)|)" "dd")
                   "((a) (b) (c)|)"))
  (should (string= (lispy-with "((a) (b) (c))|" "d")
                   "|((a) (b) (c))")))

(ert-deftest lispy-kill ()
  (should (string= (lispy-with "\n\n|(defun foo ()\n    )" (lispy-kill))
                   "\n\n|"))
  ;; while ahead of defun, and there's a comment before, move there
  (should (string= (lispy-with "\n;comment\n|(defun foo ()\n    )" (lispy-kill))
                   "\n;comment\n|"))
  (should (string= (lispy-with "(|(a) (b) (c))" "\C-k")
                   "(|)"))
  (should (string= (lispy-with "((a) |(b) (c))" "\C-k")
                   "((a) |)"))
  (should (string= (lispy-with "((a) (b) |(c))" "\C-k")
                   "((a) (b) |)"))
  (should (string= (lispy-with "((a)|\n (b) (c))" "\C-k")
                   "((a)| (b) (c))"))
  (should (string= (lispy-with "((a)|\n (b) (c))" "\C-k\C-k")
                   "((a)|)"))
  (should (string= (lispy-with "(a b c)\n(|)" "\C-k")
                   "(a b c)\n|"))
  (should (string= (lispy-with "(foo\nbar | baz  )" "\C-k")
                   "(foo\nbar |)")))

(ert-deftest lispy-yank ()
  (should (string= (lispy-with "\"|\"" (kill-new "foo") (lispy-yank))
                   "\"foo|\""))
  (should (string= (lispy-with "\"|\"" (kill-new "\"foo\"") (lispy-yank))
                   "\"\\\"foo\\\"|\"")))

(ert-deftest lispy-delete ()
  (should (string= (lispy-with "(|(a) (b) (c))" "\C-d")
                   "(|(b) (c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "2\C-d")
                   "(|(c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "3\C-d")
                   "|()"))
  (should (string= (lispy-with "(|(a) \"foo\")" "\C-d")
                   "|(\"foo\")"))
  (should (string= (lispy-with "(|(a)\"foo\")" "\C-d")
                   "|(\"foo\")"))
  (should (string= (lispy-with "(|(a) b (c))" "\C-d")
                   "(b |(c))"))
  (should (string= (lispy-with "((a) |\"foo\" (c))" "\C-d")
                   "((a) |(c))"))
  (should (string= (lispy-with "((a) (|) (c))" "\C-d")
                   "((a)| (c))"))
  (should (string= (lispy-with "(a (|) c)" "\C-d")
                   "(a c)|"))
  (should (string= (lispy-with "(foo \"bar|\")" "\C-d")
                   "(foo |\"bar\")"))
  (should (string= (lispy-with "\"foo|\\\"\\\"\"" "\C-d")
                   "\"foo|\\\"\""))
  (should (string= (lispy-with "\"|\\\\(foo\\\\)\"" "\C-d")
                   "\"|foo\""))
  (should (string= (lispy-with "\"\\\\(foo|\\\\)\"" "\C-d")
                   "\"foo|\""))
  (should (string= (lispy-with "(looking-at \"\\\\([a-z]+|\\\\)\")" "\C-d")
                   "(looking-at \"[a-z]+|\")"))
  (should (string= (lispy-with "(progn `|(foobar) (foo))" "\C-d")
                   "(progn |(foo))")))

(ert-deftest lispy-pair ()
  (should (string= (lispy-with "\"\\\\|\"" "(")
                   "\"\\\\(|\\\\)\""))
  (should (string= (lispy-with "\"\\\\|\"" "{")
                   "\"\\\\{|\\\\}\""))
  (should (string= (lispy-with "\"\\\\|\"" "}")
                   "\"\\\\[|\\\\]\"")))

(ert-deftest lispy-barf ()
  (should (string= (lispy-with "((a) (b) (c))|" "<")
                   "((a) (b))| (c)"))
  (should (string= (lispy-with "((a) (b) (c))|" "<<")
                   "((a))| (b) (c)"))
  (should (string= (lispy-with "((a) (b) (c))|" "<<<")
                   "()|(a) (b) (c)"))
  (should (string= (lispy-with "((a) (b) (c))|" "<<<<")
                   "()|(a) (b) (c)"))
  (should (string= (lispy-with "|((a) (b) (c))" "<")
                   "(a) |((b) (c))"))
  (should (string= (lispy-with "|((a) (b) (c))" "<<")
                   "(a) (b) |((c))"))
  (should (string= (lispy-with "|((a) (b) (c))" "<<<")
                   "(a) (b) (c)|()"))
  (should (string= (lispy-with "|((a) (b) (c))" "<<<<")
                   "(a) (b) (c)|()")))

(ert-deftest lispy-splice ()
  (should (string= (lispy-with "(|(a) (b) (c))" "/")
                   "(a |(b) (c))"))
  (should (string= (lispy-with "((a) |(b) (c))" "/")
                   "((a) b |(c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "///")
                   "|(a b c)"))
  (should (string= (lispy-with "((a) (b) (c)|)" "/")
                   "((a) (b)| c)"))
  (should (string= (lispy-with "((a) (b) (c)|)" "//")
                   "((a)| b c)"))
  (should (string= (lispy-with "((a) (b) (c)|)" "///")
                   "(a b c)|"))
  (should (string= (lispy-with "|(a b c)" "/")
                   "|a b c"))
  (should (string= (lispy-with "(a b c)|" "/")
                   "a b c|")))

(ert-deftest lispy-join ()
  (should (string= (lispy-with "(foo) |(bar)" "+")
                   "|(foo bar)"))
  (should (string= (lispy-with "(foo)| (bar)" "+")
                   "(foo bar)|")))

(ert-deftest lispy-split ()
  (should (string= (lispy-with "(foo |bar)" (lispy-split))
                   "(foo)\n|(bar)")))

(ert-deftest lispy-oneline ()
  (should (string= (lispy-with "|(defun abc (x)\n  \"def.\"\n  (+ x\n     x\n     x))" "O")
                   "|(defun abc (x) \"def.\" (+ x x x))"))
  (should (string= (lispy-with "(defun abc (x)\n  \"def.\"\n  (+ x\n     x\n     x))|" "O")
                   "(defun abc (x) \"def.\" (+ x x x))|"))
  (should (string= (lispy-with "|(defun foo ()\n  ;; comment\n  (bar)\n  (baz))" "O")
                   ";; comment\n|(defun foo () (bar) (baz))")))

(ert-deftest lispy-multiline ()
  (should (string= (lispy-with "|(defun abc (x) \"def.\" (+ x x x) (foo) (bar))" "M")
                   "|(defun abc (x)\n  \"def.\" (+ x x x)\n  (foo)\n  (bar))"))
  (should (string= (lispy-with "|(defun abc(x)\"def.\"(+ x x x)(foo)(bar))" "M")
                   "|(defun abc(x)\n  \"def.\"(+ x x x)\n  (foo)\n  (bar))")))

(ert-deftest lispy-comment ()
  (should (string= (lispy-with "(defun foo ()\n  (let (a b c)\n    (cond ((s1)\n           |(s2)\n           (s3)))))" ";")
                   "(defun foo ()\n  (let (a b c)\n    (cond ((s1)\n           ;; (s2)\n           |(s3)))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let (a b c)\n    (cond ((s1)\n           |(s2)\n           (s3)))))" ";;")
                   "(defun foo ()\n  (let (a b c)\n    (cond |((s1)\n           ;; (s2)\n           ;; (s3)\n           ))))"))
  (should (string-match "(defun foo ()\n  (let (a b c)\n    |(cond ;; ((s1)\n          ;;  ;; (s2)\n          ;;  ;; (s3)\n          ;;  )\n     *)))"
                        (lispy-with "(defun foo ()\n  (let (a b c)\n    (cond ((s1)\n           |(s2)\n           (s3)))))" ";;;")))
  (should (string-match "(defun foo ()\n  |(let (a b c)\n    ;; (cond ;; ((s1)\n    ;;       ;;  ;; (s2)\n    ;;       ;;  ;; (s3)\n    ;;       ;;  )\n    ;;   *)\n   *))"
                        (lispy-with "(defun foo ()\n  (let (a b c)\n    (cond ((s1)\n           |(s2)\n           (s3)))))" ";;;;")))
  (should (string-match "|(defun foo ()\n  ;; (let (a b c)\n  ;;   ;; (cond ;; ((s1)\n  ;;   ;;       ;;  ;; (s2)\n  ;;   ;;       ;;  ;; (s3)\n  ;;   ;;       ;;  )\n  ;;   ;;  *)\n  ;;   )\n  )"
                        (lispy-with "(defun foo ()\n  (let (a b c)\n    (cond ((s1)\n           |(s2)\n           (s3)))))" ";;;;;")))
  (should (string-match "|;; (defun foo ()\n;;   ;; (let (a b c)\n;;   ;;   ;; (cond ;; ((s1)\n;;   ;;   ;;       ;;  ;; (s2)\n;;   ;;   ;;       ;;  ;; (s3)\n;;   ;;   ;;       ;;  )\n;;   ;;   ;;  *)\n;;   ;;   )\n;;   )"
                        (lispy-with "(defun foo ()\n  (let (a b c)\n    (cond ((s1)\n           |(s2)\n           (s3)))))" ";;;;;;")))
  (should (string= (lispy-with ";; line| 1\n;; line 2\n (a b c)\n ;; line 3" (lispy-comment 2))
                   "line| 1\nline 2\n (a b c)\n ;; line 3"))
  (should (string= (lispy-with ";; line 1\n;; line 2|\n (a b c)\n ;; line 3" (lispy-comment 2))
                   "line 1\nline 2|\n (a b c)\n ;; line 3"))
  (should (string= (lispy-with "(|\"foo\"\n (bar)\n baz)" ";")
                   "(;; \"foo\"\n |(bar)\n baz)")))

(ert-deftest lispy-string-oneline ()
  (should (string= (lispy-with "\"foo\nb|ar\n\"" (lispy-string-oneline))
                   "\"foo\\nbar\\n\"|")))

(ert-deftest lispy-stringify ()
  (should (string= (lispy-with "(a\n b\n (foo)\n c)|" "S")
                   "|\"(a\n b\n (foo)\n c)\""))
  (should (string= (lispy-with "(progn |(1 2 3))" "S")
                   "|(progn \"(1 2 3)\")"))
  (should (string= (lispy-with "(progn |(1 2 3))" "SS")
                   "|\"(progn \\\"(1 2 3)\\\")\""))
  (should (string= (lispy-with "(foo |(bar #\\x \"baz \\\\ quux\") zot)" "S")
                   "|(foo \"(bar #\\\\x \\\"baz \\\\\\\\ quux\\\")\" zot)")))

(ert-deftest lispy-eval ()
  (should (string= (lispy-with-value "(+ 2 2)|" (lispy-eval)) "4")))

(ert-deftest lispy-eval-and-insert ()
  (should (string= (lispy-with "(+ 2 2)|" "E")
                   "(+ 2 2)\n4|")))

(ert-deftest lispy--normalize-1 ()
  (should (string= (lispy-with "|(foo (bar)baz)" (lispy--normalize-1))
                   "|(foo (bar) baz)"))
  (should (string= (lispy-with "(foo (bar)baz)|" (lispy--normalize-1))
                   "(foo (bar) baz)|"))
  (should (string= (lispy-with "|(bar\n  foo )" (lispy--normalize-1))
                   "|(bar\n foo)"))
  (should (string= (lispy-with "|(foo \")\")" (lispy--normalize-1))
                   "|(foo \")\")"))
  (should (string= (lispy-with "|(foo     \n bar)" (lispy--normalize-1))
                   "|(foo\n bar)"))
  (should (string= (lispy-with "|(require' foo)" (lispy--normalize-1))
                   "|(require 'foo)")))

(ert-deftest lispy--sexp-normalize ()
  (should (equal
           (lispy--sexp-normalize
            '(progn
              (ly-raw comment "foo")
              (ly-raw newline)))
           '(progn
             (ly-raw comment "foo")
             (ly-raw newline)))))

(ert-deftest lispy--remove-gaps ()
  (should (string= (lispy-with "((a) |(c))" (lispy--remove-gaps))
                   "((a) |(c))")))

(ert-deftest clojure-thread-macro ()
  ;; changes indentation
  (require 'cider)
  (should (string= (lispy-with "|(map sqr (filter odd? [1 2 3 4 5]))" "2(->>]<]<]")
                   "(->> (map sqr) (filter odd?) [1 2 3 4 5]|)")))

(ert-deftest lispy--read ()
  (should (equal (lispy--read "(progn
  #'foo
  (ly-raw function foo)
  (function foo)
  \"#'bar\"
  \"(ly-raw)\"
  #'bar)")
                 '(progn (ly-raw newline)
                   (ly-raw function foo)
                   (ly-raw newline)
                   (ly-raw raw function foo)
                   (ly-raw newline)
                   (function foo)
                   (ly-raw newline)
                   (ly-raw string "\"#'bar\"")
                   (ly-raw newline)
                   (ly-raw string "\"(ly-raw)\"")
                   (ly-raw newline)
                   (ly-raw function bar)))))

(ert-deftest lispy-to-lambda ()
  (should (string= (lispy-with "|(defun foo (x y)\n  (bar))" (lispy-to-lambda))
                   "|(lambda (x y)\n  (bar))"))
  (should (string= (lispy-with "(defun foo (x y)\n  |(bar))" (lispy-to-lambda))
                   "|(lambda (x y)\n  (bar))"))
  (should (string= (lispy-with "(defun foo (x y)\n  (bar))|" (lispy-to-lambda))
                   "|(lambda (x y)\n  (bar))")))

(ert-deftest lispy-parens ()
  (should (string= (lispy-with "'|(foo bar)" "2(")
                   "'(| (foo bar))"))
  (should (string= (lispy-with "'(foo bar)|" "2(")
                   "'(| (foo bar))")))

(ert-deftest lispy-to-ifs ()
  (should (string= (lispy-with "|(cond ((looking-at \" *;\"))\n      ((and (looking-at \"\\n\")\n            (looking-back \"^ *\"))\n       (delete-blank-lines))\n      ((looking-at \"\\\\([\\n ]+\\\\)[^\\n ;]\")\n       (delete-region (match-beginning 1)\n                      (match-end 1))))"
                               (lispy-to-ifs))
                   "|(if (looking-at \" *;\")\n    nil\n  (if (and (looking-at \"\\n\")\n           (looking-back \"^ *\"))\n      (delete-blank-lines)\n    (if (looking-at \"\\\\([\\n ]+\\\\)[^\\n ;]\")\n        (delete-region (match-beginning 1)\n                       (match-end 1)))))")))

(ert-deftest lispy-to-cond ()
  (should (string= (lispy-with "|(if (looking-at \" *;\")\n    nil\n  (if (and (looking-at \"\\n\")\n           (looking-back \"^ *\"))\n      (delete-blank-lines)\n    (if (looking-at \"\\\\([\\n ]+\\\\)[^\\n ;]\")\n        (delete-region (match-beginning 1)\n                       (match-end 1)))))"
                               (lispy-to-cond))
                   "|(cond ((looking-at \" *;\"))\n      ((and (looking-at \"\\n\")\n            (looking-back \"^ *\"))\n       (delete-blank-lines))\n      ((looking-at \"\\\\([\\n ]+\\\\)[^\\n ;]\")\n       (delete-region (match-beginning 1)\n                      (match-end 1))))")))

(ert-deftest lispy-to-defun ()
  (should (string= (lispy-with "(foo bar)|" (lispy-to-defun))
                   "(defun foo (bar)\n  |)"))
  (should (string= (lispy-with "|(foo bar)" (lispy-to-defun))
                   "(defun foo (bar)\n  |)"))
  (should (string= (lispy-with "(foo)|" (lispy-to-defun))
                   "(defun foo ()\n  |)"))
  (should (string= (lispy-with "|(foo)" (lispy-to-defun))
                   "(defun foo ()\n  |)")))

(ert-deftest lispy-tab ()
  (should (string= (lispy-with "|(defun test?  (x) x)" "i")
                   "|(defun test? (x) x)")))

(defun lispy-test-normalize ()
  (interactive)
  (goto-char (point-min))
  (catch 'break
    (let ((pt (point)))
      (while (not (buffer-modified-p))
        (setq pt (max pt (point)))
        (lispy-down 1)
        (if (< (point) pt)
            (throw 'break nil))
        (lispy-tab)))))

(provide 'lispy-test)

;;; Local Variables:
;;; outline-regexp: ";; ———"
;;; End:

;;; lispy.el ends here
