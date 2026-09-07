(use-modules (guix gexp))

;; Exercise the daemon's builder setup, including personality(), without
;; downloading or compiling a package.
;; A fresh name forces execution rather than returning a cached result.
;; --check cannot redirect an existing output with chroots disabled.
(computed-file (string-append "container-build-check-"
                              (number->string (car (gettimeofday))) "-"
                              (number->string (cdr (gettimeofday))))
  #~(call-with-output-file #$output
      (lambda (port) (display "ok" port))))
