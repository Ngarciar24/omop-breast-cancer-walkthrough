test_that("the CDM opens and holds people", {
  cdm <- open_cdm()
  on.exit(close_cdm(cdm))

  n_person <- cdm$person |> count() |> pull("n")
  expect_gt(n_person, 0)
})

test_that("source and vocabulary versions can be read", {
  cdm <- open_cdm()
  on.exit(close_cdm(cdm))

  meta <- cdm_metadata(cdm)
  expect_length(meta$cdm_version, 1)
  expect_length(meta$vocabulary_version_vocabulary, 1)
  expect_true(nzchar(meta$vocabulary_version_vocabulary))
})
