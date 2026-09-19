# Tests the REAL server() function from server.R via with_sandboxed_server()
# (defined in helper-source-app.R above).
# =============================================================================

test_that("real server(): switching aligner resets program choices to a valid one", {
  with_sandboxed_server(function(server_fn) {
    calls_env <- attr(server_fn, "update_select_calls")

    testServer(server_fn, {
      session$setInputs(aligner = "DIAMOND")
      session$flushReact()
    })

    upd <- last_update_for(calls_env, "program")
    expect_false(is.null(upd))
    expect_true(upd$selected %in% c("blastp", "blastx"))
    expect_setequal(upd$choices, c("blastp", "blastx"))
  })
})

test_that("real server(): DIAMOND with no registered protein DBs yields empty db choices", {
  with_sandboxed_server(function(server_fn) {
    calls_env <- attr(server_fn, "update_select_calls")

    testServer(server_fn, {
      session$setInputs(aligner = "DIAMOND", program = "blastp")
      session$flushReact()
    })

    upd <- last_update_for(calls_env, "db")
    expect_false(is.null(upd))
    expect_equal(length(upd$choices), 0)
  })
})

test_that("real server(): switching to BLAST + blastn falls back to the 'nt' shortcut when no local nucleotide DB is registered", {
  with_sandboxed_server(function(server_fn) {
    calls_env <- attr(server_fn, "update_select_calls")

    testServer(server_fn, {
      session$setInputs(aligner = "BLAST", program = "blastn")
      session$flushReact()
    })

    upd <- last_update_for(calls_env, "db")
    expect_false(is.null(upd))
    expect_equal(upd$selected, "nt")
  }, empty_seed_registry = TRUE)
})

test_that("real server(): switching to BLAST + blastn prefers a registered local nucleotide DB over the 'nt' shortcut", {
  # Without empty_seed_registry = TRUE, load_or_default_config() falls back
  # to its hardcoded default databases (Mlig_core_nt / Mlig_core_aa,
  # defined in 02_user_db_registry.R). This documents that a real,
  # registered local database is correctly preferred over the generic
  # remote "nt" placeholder when one is available.
  with_sandboxed_server(function(server_fn) {
    calls_env <- attr(server_fn, "update_select_calls")

    testServer(server_fn, {
      session$setInputs(aligner = "BLAST", program = "blastn")
      session$flushReact()
    })

    upd <- last_update_for(calls_env, "db")
    expect_false(is.null(upd))
    expect_equal(upd$selected, "Mlig_core_nt")
  })
})

