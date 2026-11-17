# Paths in tests are relative to tests/testthat, so build them from the root.
repo_path <- function(...) testthat::test_path("..", "..", ...)

source(repo_path("R", "cdm.R"))
source(repo_path("R", "sql.R"))
source(repo_path("R", "cohort_sql.R"))
