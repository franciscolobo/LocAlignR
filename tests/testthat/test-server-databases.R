.seed_and_user_registry <- function() {
  normalize_registry_df(data.frame(
    name    = c("builtin_db", "my_uniprot_blast"),
    path    = c("/seed/path", "/user/path"),
    type    = c("prot", "prot"),
    backend = c("blast", "blast"),
    source  = c("seed", "user"),
    stringsAsFactors = FALSE
  ))
}

.databases_test_server <- function(cfg = list(databases = list(builtin_db = "/seed/path"))) {
  function(input, output, session) {
    db_registry <- reactiveVal(.seed_and_user_registry())
    session$userData$db_registry <- db_registry

    allowed_db_choices <- function(program, aligner = NULL) {
      reg <- db_registry()
      allowed_db_choices_for_program(reg, program, toupper(aligner %||% "BLAST"))
    }

    wire_databases(
      input = input,
      output = output,
      session = session,
      db_registry = db_registry,
      cfg = cfg,
      allowed_db_choices = allowed_db_choices
    )
  }
}

#' Runs `code` with a fake updateSelectInput() shadowing the real one in
#' globalenv() -- where wire_databases() (sourced via .source_app_file())
#' resolves its unqualified updateSelectInput() call via lexical scoping.
#' Restores the previous binding (or removes the shadow entirely) afterward.
with_capturing_update_select_input_in_globalenv <- function(code) {
  capture <- make_capturing_update_select_input()

  had_prior <- exists("updateSelectInput", envir = globalenv(), inherits = FALSE)
  prior <- if (had_prior) get("updateSelectInput", envir = globalenv()) else NULL

  assign("updateSelectInput", capture$fn, envir = globalenv())

  on.exit({
    if (had_prior) {
      assign("updateSelectInput", prior, envir = globalenv())
    } else {
      rm("updateSelectInput", envir = globalenv())
    }
  }, add = TRUE)

  code(capture$calls_env)
}

test_that("removing a user database updates the registry and reports success", {
  saved <- NULL
  testthat::local_mocked_bindings(
    save_user_dbs = function(df, path = user_db_file) {
      saved <<- df
      invisible(NULL)
    }
  )

  with_capturing_update_select_input_in_globalenv(function(calls_env) {
    testServer(.databases_test_server(), {
      session$setInputs(aligner = "BLAST", program = "blastp", db = "my_uniprot_blast")

      session$setInputs(databasesTable_rows_selected = 2)
      session$setInputs(db_remove_selected = 1)

      reg_after <- session$userData$db_registry()
      expect_false("my_uniprot_blast" %in% reg_after$name)
      expect_true("builtin_db" %in% reg_after$name)

      expect_match(output$db_remove_status, "Removed 1 database")
      expect_match(output$db_remove_status, "my_uniprot_blast")

      expect_false(is.null(saved))
      expect_false("my_uniprot_blast" %in% saved$name)
    })

    upd <- last_update_for(calls_env, "db")
    expect_false(is.null(upd))
    expect_equal(upd$selected, "builtin_db")
  })
})

test_that("attempting to remove a seed database is refused with an explanatory message", {
  testServer(.databases_test_server(), {
    session$setInputs(aligner = "BLAST", program = "blastp", db = "my_uniprot_blast")

    session$setInputs(databasesTable_rows_selected = 1)  # builtin_db (seed)
    session$setInputs(db_remove_selected = 1)

    reg_after <- session$userData$db_registry()
    expect_true("builtin_db" %in% reg_after$name)  # unchanged

    expect_match(output$db_remove_status, "built-in \\(seed\\) databases")
  })
})

test_that("clicking Remove with no row selected reports 'no rows selected'", {
  testServer(.databases_test_server(), {
    session$setInputs(db_remove_selected = 1)
    expect_match(output$db_remove_status, "No rows selected")
  })
})

test_that("removing the currently-selected run-panel database updates its dropdown to a remaining valid choice", {
  with_capturing_update_select_input_in_globalenv(function(calls_env) {
    testServer(.databases_test_server(), {
      session$setInputs(aligner = "BLAST", program = "blastp", db = "my_uniprot_blast")

      session$setInputs(databasesTable_rows_selected = 2)
      session$setInputs(db_remove_selected = 1)
    })

    upd <- last_update_for(calls_env, "db")
    expect_false(is.null(upd))
    expect_false(identical(upd$selected, "my_uniprot_blast"))
    expect_equal(upd$selected, "builtin_db")
  })
})
