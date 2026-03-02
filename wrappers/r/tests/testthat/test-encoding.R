test_that("encode/decode round trip", {
  skip_if_not(tryCatch({
    tt_version()
    TRUE
  }, error = function(e) FALSE), "Native library not available")

  enc <- get_encoding("cl100k_base")
  text <- "hello world"
  tokens <- encode(enc, text)
  expect_true(length(tokens) > 0)
  decoded <- decode(enc, tokens)
  expect_equal(decoded, text)
})

test_that("count_tokens works", {
  skip_if_not(tryCatch({
    tt_version()
    TRUE
  }, error = function(e) FALSE), "Native library not available")

  enc <- get_encoding("cl100k_base")
  text <- "hello world"
  n <- count_tokens(enc, text)
  tokens <- encode(enc, text)
  expect_equal(n, length(tokens))
})

test_that("is_within_token_limit works", {
  skip_if_not(tryCatch({
    tt_version()
    TRUE
  }, error = function(e) FALSE), "Native library not available")

  enc <- get_encoding("cl100k_base")
  text <- "hello"
  result <- is_within_token_limit(enc, text, 1000L)
  expect_true(!is.null(result))
  expect_true(result > 0)
})
