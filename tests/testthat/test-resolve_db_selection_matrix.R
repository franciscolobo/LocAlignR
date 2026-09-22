# Exhaustive combination coverage for resolve_db_selection() over every
# (aligner, backend, db_type, program) combination it can actually be
# called with. This function has already hidden one real bug (the DIAMOND
# branch once compared backend against "blast" instead of "diamond",
# silently making every correctly-registered DIAMOND database
# unresolvable) that a handful of hand-picked example tests missed.
#
# shiny::validate() evaluates its need() arguments in order and throws on
# the FIRST failing one. resolve_db_selection()'s checks are ordered:
#   1. DIAMOND-backend mismatch
#   2. BLAST-backend mismatch
#   3. nucleotide-program/db_type mismatch
#   4. protein-program/db_type mismatch
# So when both a backend mismatch AND a program/db_type mismatch are
# present simultaneously, the backend error always wins -- this matrix
# encodes that priority explicitly rather than just asserting "some
# error occurred," so a future change that silently reorders or drops a
# check would be caught.

nucleotide_programs <- c("blastn", "tblastn", "tblastx")
protein_programs    <- c("blastp", "blastx")

combos <- expand.grid(
  aligner = c("BLAST", "DIAMOND"),
  backend = c("blast", "diamond"),
  db_type = c("prot", "nucl"),
  program = c("blastp", "blastx", "blastn", "tblastn", "tblastx"),
  stringsAsFactors = FALSE
)

for (.i in seq_len(nrow(combos))) {
  local({
    i <- .i
    aligner <- combos$aligner[i]
    backend <- combos$backend[i]
    db_type <- combos$db_type[i]
    program <- combos$program[i]

    backend_ok <- (aligner == "BLAST" && backend == "blast") ||
      (aligner == "DIAMOND" && backend == "diamond")

    program_ok <- if (program %in% nucleotide_programs) {
      db_type == "nucl"
    } else {
      db_type == "prot"
    }

    desc <- sprintf(
      "resolve_db_selection: aligner=%s backend=%s db_type=%s program=%s -> %s",
      aligner, backend, db_type, program,
      if (backend_ok && program_ok) {
        "success"
      } else if (!backend_ok) {
        "backend mismatch error"
      } else {
        "program/db_type mismatch error"
      }
    )

    test_that(desc, {
      reg <- normalize_registry_df(data.frame(
        name    = "testdb",
        path    = "/fake/path",
        type    = db_type,
        backend = backend,
        stringsAsFactors = FALSE
      ))

      if (backend_ok && program_ok) {
        res <- resolve_db_selection(
          db_input = "testdb", registry = reg, program = program, aligner = aligner
        )
        expect_equal(res$db_path, "/fake/path")
        expect_equal(res$db_type, db_type)
        expect_equal(res$backend, backend)
        expect_false(res$remote)
      } else if (!backend_ok) {
        # Backend check is evaluated first, so it wins regardless of
        # whether program_ok is also FALSE.
        expected_msg <- if (aligner == "DIAMOND") {
          "not registered for DIAMOND"
        } else {
          "not registered for BLAST"
        }
        expect_shiny_validation_error(
          resolve_db_selection(
            db_input = "testdb", registry = reg, program = program, aligner = aligner
          ),
          regexp = expected_msg
        )
      } else {
        # backend_ok TRUE, program_ok FALSE
        expected_msg <- if (program %in% nucleotide_programs) {
          "Program needs a nucleotide DB"
        } else {
          "Program needs a protein DB"
        }
        expect_shiny_validation_error(
          resolve_db_selection(
            db_input = "testdb", registry = reg, program = program, aligner = aligner
          ),
          regexp = expected_msg
        )
      }
    })
  })
}

# The nr/nt remote shortcut is explicitly restricted to aligner == "BLAST"
# in resolve_db_selection()'s first branch. This is easy to overlook when
# reading the function (it looks at first glance like a general shortcut),
# so pin down that DIAMOND does NOT get it -- "nr"/"nt" must fall through
# to an ordinary (and, since neither is ever registered, failing) registry
# lookup instead.
test_that("resolve_db_selection does not apply the nr/nt remote shortcut for DIAMOND", {
  reg <- normalize_registry_df(data.frame(
    name = "unrelated_entry", path = "/x", type = "prot", backend = "diamond",
    stringsAsFactors = FALSE
  ))

  expect_shiny_validation_error(
    resolve_db_selection("nr", reg, program = "blastp", aligner = "DIAMOND"),
    regexp = "Unknown DB"
  )

  expect_shiny_validation_error(
    resolve_db_selection("nt", reg, program = "blastn", aligner = "DIAMOND"),
    regexp = "Unknown DB"
  )
})
