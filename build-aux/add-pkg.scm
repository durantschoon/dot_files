;;; add-pkg.scm --- insert a package spec into a home config, comment-safe
;;;
;;; Usage: guile -s build-aux/add-pkg.scm <file.scm> <package-spec>
;;;
;;; Exit 0 on success or when the package is already present (idempotent),
;;; non-zero with a message on stderr otherwise.  Writes nothing unless the
;;; post-edit verification below passes.
;;;
;;; WHY THE EDIT IS TEXTUAL AND NOT A SEXP REWRITE
;;;
;;; The obvious implementation -- `read' the file, cons the new spec into the
;;; list, `write' it back -- destroys these files.  Guile's reader discards
;;; comments, and home/base.scm and home/wayland.scm are mostly comments: the
;;; librewolf note alone is ten lines, and it is the thing that stops firefox
;;; being re-added every six months.  A round trip would silently delete all of
;;; it and renormalise the formatting besides.
;;;
;;; The next idea -- read with `(read-enable 'positions)' and use each element's
;;; source properties to find the insertion offset -- does not work either, and
;;; the reason is worth recording so nobody tries it again.  Guile annotates
;;; only the HEAD cons cell of a form.  Measured on home/wayland.scm:
;;;
;;;   cell 0: car="git"       props=((filename . "...") (line . 65) (column . 3))
;;;   cell 1: car="zsh"       props=()
;;;   cell 2: car="starship"  props=()
;;;
;;; So the reader locates the LIST, and nothing finer.  Strings are immediates
;;; and cannot carry properties at all.
;;;
;;; Hence the split this file implements:
;;;
;;;   Guile  finds the list, reads the authoritative set of existing specs
;;;          (so duplicate detection is structural, not a grep that would also
;;;          match the word "firefox" inside the librewolf comment), and
;;;          re-reads the result afterwards to prove the edit was correct.
;;;   Text   performs the insertion, so every byte not being inserted is
;;;          preserved exactly.
;;;
;;; The verification is what makes the textual edit safe: the file must still
;;; parse, the target list must contain the new spec, it must be longer by
;;; exactly one, and every previously present spec must survive.  Anything else
;;; restores the original and fails.

(use-modules (ice-9 rdelim)
             (ice-9 regex)
             ;; The full `format', not the `simple-format' the core binds: the
             ;; messages below use ~<newline> to wrap long strings in source,
             ;; which simple-format rejects at runtime with "Unsupported format
             ;; option" -- turning every clean refusal into a backtrace.
             (ice-9 format)
             (srfi srfi-1))

(read-enable 'positions)


;;; Teaching plain Guile to read G-expressions
;;;
;;; These are guix home configs, so they contain #~ / #$ / #$@ -- reader syntax
;;; that (guix gexp) installs and that a bare `guile' has never heard of.
;;; Without this, `read' dies on home/base.scm at the first gexp in its services
;;; field ("Unknown # object: #~"), which is 60 lines PAST the package list this
;;; script came for.  It still has to get through them, because base.scm's list
;;; lives inside the (home-environment ...) form that also holds the services.
;;;
;;; Running under `guix repl' instead would give real gexp syntax, at the cost
;;; of loading Guix's module tree on every invocation.  Nothing here evaluates
;;; the forms -- the matchers look for one specific shape and ignore everything
;;; else -- so the reader only has to CONSUME gexps without error.  Mapping them
;;; onto ordinary lists does that, and keeps the script dependency-free.

(define (gexp-reader tag)
  "A reader that consumes the following datum and wraps it in TAG."
  (lambda (chr port) (list tag (read port))))

(define (splicing-reader plain splicing)
  "Reader for #$ and #+, which may be followed by @ for the splicing variant."
  (lambda (chr port)
    (if (eqv? (peek-char port) #\@)
        (begin (read-char port) (list splicing (read port)))
        (list plain (read port)))))

(read-hash-extend #\~ (gexp-reader 'gexp))
(read-hash-extend #\$ (splicing-reader 'ungexp 'ungexp-splicing))
(read-hash-extend #\+ (splicing-reader 'ungexp-native 'ungexp-native-splicing))


;;; Locating the package list

(define (package-list-form form)
  "Return the (quote (...)) FORM holding the spec list, or #f if FORM is not one
of the two shapes a home config uses.  Both are matched explicitly rather than by
hunting for any quoted string list: a wrong guess here edits the wrong list.

The quote form itself is returned, not the list inside it, because it is the only
thing carrying source properties -- see the header."
  (cond
   ;; (define %base-packages '("git" ...))          -- home/wayland.scm
   ((and (pair? form)
         (eq? (car form) 'define)
         (pair? (cdr form))
         (eq? (cadr form) '%base-packages)
         (pair? (cddr form))
         (quoted-list (caddr form)))
    => identity)
   ;; (specifications->packages '("git" ...))       -- home/base.scm, nested
   ((and (pair? form) (find-specifications form)) => identity)
   (else #f)))

(define (quoted-list x)
  "Return X when it is (quote (\"str\" ...)), else #f."
  (and (pair? x)
       (eq? (car x) 'quote)
       (pair? (cdr x))
       (list? (cadr x))
       (every string? (cadr x))
       x))

(define (find-specifications form)
  "Depth-first search for (specifications->packages '(...)) anywhere in FORM.
base.scm buries the call inside (home-environment (packages (append ...))), so
this cannot just look at the top level."
  (and (pair? form)
       (or (and (eq? (car form) 'specifications->packages)
                (pair? (cdr form))
                (quoted-list (cadr form)))
           (any (lambda (sub) (and (pair? sub) (find-specifications sub)))
                form))))

(define (read-package-list file)
  "Return (values specs index) -- the spec list in FILE and the 0-BASED index of
the line the list opens on -- or (values #f #f).

Guile's source-property `line' is 0-based, which is exactly what indexing into
the list of lines wants, so there is no conversion here.  Verified against
home/wayland.scm, whose list opens on 1-based line 66 and reports 65.  Do not
'fix' this with a -1."
  (call-with-input-file file
    (lambda (port)
      (let loop ()
        (let ((form (read port)))
          (cond
           ((eof-object? form) (values #f #f))
           ((package-list-form form)
            => (lambda (qform)
                 (values (cadr qform) (form-line qform))))
           (else (loop))))))))

(define (form-line form)
  "0-based source line of FORM, or #f."
  (and (pair? form)
       (assq-ref (source-properties form) 'line)))


;;; Finding the insertion line

(define (comment-line? line)
  "Is LINE a whole-line comment?"
  (string-match "^[ \t]*;" line))

(define (blank-line? line)
  (string-match "^[ \t]*$" line))

(define (count-specs line)
  "How many \"...\" string literals appear in LINE."
  (length (fold-matches "\"[^\"]*\"" line '() cons)))

(define (leading-run-end lines start)
  "Return the 0-based index of the last line of the leading uncommented run of
the package list beginning at 0-based START.

The run is the packages before the first comment inside the list.  That is
deliberately where new specs go: every later group in these files has a comment
bound to it that describes its members jointly -- \"curl fetches the Claude Code
binary, and glibc provides the ld-linux loader\" -- so an alphabetical insertion
would wedge an unrelated package into the middle of someone else's sentence.

Returns #f when no comment follows, rather than guessing: these two files both
have one, and a file that does not is a file this script has not been taught."
  (let loop ((i start) (last start))
    (cond
     ((>= i (length lines)) #f)
     ((comment-line? (list-ref lines i)) (and (> i start) last))
     ((blank-line? (list-ref lines i)) (loop (+ i 1) last))
     (else (loop (+ i 1) i)))))

(define (insert-spec lines idx spec)
  "Return LINES with SPEC added at 0-based IDX.

Two layouts, distinguished by how many specs that line already holds:
base.scm keeps its leading run on one long line, wayland.scm one per line."
  (let* ((line (list-ref lines idx))
         (multi? (> (count-specs line) 1)))
    (append (take lines idx)
            (if multi?
                (list (string-append line " \"" spec "\""))
                (list line
                      (string-append (indent-of line) "\"" spec "\"")))
            (drop lines (+ idx 1)))))

(define (indent-of line)
  "The leading whitespace of LINE."
  (let ((m (string-match "^[ \t]*" line)))
    (match:substring m 0)))


;;; Driver

(define (read-lines file)
  (call-with-input-file file
    (lambda (port)
      (let loop ((acc '()))
        (let ((line (read-line port)))
          (if (eof-object? line)
              (reverse acc)
              (loop (cons line acc))))))))

(define (write-lines file lines)
  (call-with-output-file file
    (lambda (port)
      (for-each (lambda (l) (display l port) (newline port)) lines))))

(define (die fmt . args)
  (apply format (current-error-port) (string-append "add-pkg: " fmt "~%") args)
  (exit 1))

(define (main args)
  (when (< (length args) 3)
    (die "usage: guile -s build-aux/add-pkg.scm <file.scm> <package-spec>"))
  (let* ((file (list-ref args 1))
         (spec (list-ref args 2)))
    (call-with-values (lambda () (read-package-list file))
      (lambda (specs start)
        (unless specs
          (die "~a: found no (define %base-packages '(...)) nor ~
(specifications->packages '(...))" file))
        (if (member spec specs)
            (begin
              (format #t "    ~a: \"~a\" already present~%" file spec)
              (exit 0))
            (let* ((lines (read-lines file))
                   ;; START is already a 0-based index, and names the line the
                   ;; list opens on, which itself holds specs -- so the leading
                   ;; run starts there rather than after it.
                   (idx (leading-run-end lines start)))
              (unless idx
                (die "~a: no comment follows the list at line ~a, so the ~
leading run has no end this script can identify" file (+ start 1)))
              (let ((edited (insert-spec lines idx spec))
                    (backup (string-append file ".add-pkg-bak")))
                (write-lines backup lines)
                (write-lines file edited)
                (verify-or-restore file backup spec specs)
                (delete-file backup)
                (format #t "    ~a: added \"~a\" after line ~a~%"
                        file spec (+ idx 1)))))))))

(define (verify-or-restore file backup spec before)
  "Re-read FILE and prove the edit did exactly what was intended, restoring from
BACKUP and exiting non-zero if not.  This is what licenses the textual edit."
  (define (restore! fmt . args)
    (write-lines file (read-lines backup))
    (delete-file backup)
    (apply die (string-append "~a: " fmt " (file restored)")
           file args))
  (call-with-values (lambda () (read-package-list file))
    (lambda (after _line)
      (cond
       ((not after)
        (restore! "no longer parses as a home config"))
       ((not (member spec after))
        (restore! "\"~a\" is missing after the edit" spec))
       ((not (= (length after) (+ 1 (length before))))
        (restore! "list went from ~a to ~a specs, expected ~a"
                  (length before) (length after) (+ 1 (length before))))
       ((not (every (lambda (s) (member s after)) before))
        (restore! "the edit dropped ~s"
                  (remove (lambda (s) (member s after)) before)))
       (else #t)))))

(main (command-line))
