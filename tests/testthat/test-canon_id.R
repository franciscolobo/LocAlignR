test_that("canon_id strips whitespace suffixes, pipe prefixes, and version numbers", {
  expect_equal(canon_id("sp|P12345|NAME_HUMAN"), "NAME_HUMAN")
  expect_equal(canon_id("NM_001234.2"), "NM_001234")
  expect_equal(canon_id("  gi|123|ref|NP_999.1  description text"), "NP_999")
  expect_equal(canon_id("plain_id"), "plain_id")
})

test_that("canon_id is vectorized and coerces to character", {
  out <- canon_id(c("a|b.1", 123, NA))
  expect_equal(out[1], "b")
  expect_equal(out[2], "123")
  expect_true(is.na(out[3]) || out[3] == "NA")
})
