.diag_test_server <- function() {
  function(input, output, session) {
    db_registry <- reactiveVal(normalize_registry_df(NULL))
    session$userData$db_registry <- db_registry
    wire_diagnostics(input, output, db_registry = db_registry)
  }
}

test_that("diag_session reports R version and detected thread count", {
  testServer(.diag_test_server(), {
    session$flushReact()
    expect_match(output$diag_session, "R:")
    expect_match(output$diag_session, "Detected CPU threads:")
  })
})

test_that("diag_packages lists every required package with a version or NOT INSTALLED", {
  testServer(.diag_test_server(), {
    session$flushReact()
    expect_match(output$diag_packages, "shiny\\s")
    expect_match(output$diag_packages, "openxlsx")
    expect_no_match(output$diag_packages, "shiny\\s+NOT INSTALLED")
  })
})

test_that("diag_db_health reports zero databases when registry is empty", {
  testServer(.diag_test_server(), {
    session$flushReact()
    expect_match(output$diag_db_health, "No databases registered")
  })
})

test_that("diag_db_health reacts to db_registry() changes and flags missing paths", {
  testServer(.diag_test_server(), {
    reg <- normalize_registry_df(data.frame(
      name = "ghost_db",
      path = file.path(tempdir(), "definitely_does_not_exist_xyz"),
      type = "prot",
      backend = "blast",
      stringsAsFactors = FALSE
    ))
    session$userData$db_registry(reg)
    session$flushReact()

    expect_match(output$diag_db_health, "Registered databases: 1")
    expect_match(output$diag_db_health, "Missing/broken paths: 1")
    expect_match(output$diag_db_health, "ghost_db")
  })
})

test_that("diag_db_health treats nr/nt as remote, not missing", {
  testServer(.diag_test_server(), {
    reg <- normalize_registry_df(data.frame(
      name = "remote_nt", path = "nt", type = "nucl", backend = "blast",
      stringsAsFactors = FALSE
    ))
    session$userData$db_registry(reg)
    session$flushReact()

    expect_match(output$diag_db_health, "Missing/broken paths: 0")
  })
})

test_that("diag_storage reports the temp directory as writable", {
  testServer(.diag_test_server(), {
    session$flushReact()
    expect_match(output$diag_storage, "Writable: yes")
  })
})

test_that("diag_log_tail responds to the refresh button", {
  testServer(.diag_test_server(), {
    session$flushReact()

    session$setInputs(diag_refresh_log = 1)
    after <- output$diag_log_tail

    expect_true(is.character(after))
    expect_length(after, 1)
  })
})
