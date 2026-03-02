test_that("list_encoding_names returns 7 encodings", {
  names <- list_encoding_names()
  expect_equal(length(names), 7)
  expect_true("cl100k_base" %in% names)
  expect_true("o200k_base" %in% names)
  expect_true("r50k_base" %in% names)
  expect_true("p50k_base" %in% names)
  expect_true("p50k_edit" %in% names)
  expect_true("gpt2" %in% names)
  expect_true("o200k_harmony" %in% names)
  expect_true(!is.unsorted(names))
})

test_that("get_encoding_spec works", {
  spec <- get_encoding_spec("cl100k_base")
  expect_equal(spec$name, "cl100k_base")
  expect_equal(spec$n_vocab, 100277L)
  expect_true("<|endoftext|>" %in% names(spec$special_tokens))
  expect_equal(spec$special_tokens[["<|endoftext|>"]], 100257L)
})

test_that("get_encoding_spec unknown throws", {
  expect_error(get_encoding_spec("nonexistent"), "Unknown encoding")
})

test_that("model_to_encoding_name resolves exact", {
  expect_equal(model_to_encoding_name("gpt-4"), "cl100k_base")
  expect_equal(model_to_encoding_name("gpt-4o"), "o200k_base")
  expect_equal(model_to_encoding_name("o1"), "o200k_base")
  expect_equal(model_to_encoding_name("gpt2"), "gpt2")
})

test_that("model_to_encoding_name resolves prefix", {
  expect_equal(model_to_encoding_name("gpt-4o-2024-01-01"), "o200k_base")
  expect_equal(model_to_encoding_name("gpt-4-turbo-preview"), "cl100k_base")
  expect_equal(model_to_encoding_name("o1-preview"), "o200k_base")
})

test_that("model_to_encoding_name unknown throws", {
  expect_error(model_to_encoding_name("nonexistent-model"), "Could not automatically map")
})
