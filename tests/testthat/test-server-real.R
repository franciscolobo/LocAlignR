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
  # With load_or_default_config() now correctly defaulting to an empty
  # registry (rather than hardcoded developer-machine paths) when no
  # config.yml is present, this is simply the default sandboxed behavior --
  # no special seed_config_yml needed.
  with_sandboxed_server(function(server_fn) {
    calls_env <- attr(server_fn, "update_select_calls")

    testServer(server_fn, {
      session$setInputs(aligner = "BLAST", program = "blastn")
      session$flushReact()
    })

    upd <- last_update_for(calls_env, "db")
    expect_false(is.null(upd))
    expect_equal(upd$selected, "nt")
  })
})

test_that("real server(): switching to BLAST + blastn prefers a registered local nucleotide DB over the 'nt' shortcut", {
  with_sandboxed_server(function(server_fn) {
    calls_env <- attr(server_fn, "update_select_calls")

    testServer(server_fn, {
      session$setInputs(aligner = "BLAST", program = "blastn")
      session$flushReact()
    })

    upd <- last_update_for(calls_env, "db")
    expect_false(is.null(upd))
    expect_equal(upd$selected, "local_nt_db")
  }, seed_config_yml = list(
    databases = list(local_nt_db = file.path(tempdir(), "fake_nt_db"))
  ))
})
