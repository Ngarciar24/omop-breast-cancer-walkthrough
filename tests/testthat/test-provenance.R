# ---------------------------------------------------------------------------
# Tests for provenance (M7)
# ---------------------------------------------------------------------------

test_that("git_commit() marks code changes as dirty, but not results changes", {
  skip_if(Sys.which("git") == "", "git not available")

  # A throwaway repository in a temporary folder.
  repo <- tempfile("repo")
  dir.create(file.path(repo, "results"), recursive = TRUE)
  old <- setwd(repo)
  on.exit(setwd(old))
  git <- function(...) system2("git", c(...), stdout = FALSE, stderr = FALSE)

  writeLines("x <- 1", "code.R")
  writeLines("a,b", "results/table.csv")
  git("init", "-q")
  git("add", ".")
  git("-c", "user.name=test", "-c", "user.email=test@example.org",
      "commit", "-q", "-m", "first")

  expect_false(grepl("-dirty$", git_commit()))

  writeLines("a,b,c", "results/table.csv")
  expect_false(grepl("-dirty$", git_commit()))

  writeLines("x <- 2", "code.R")
  expect_true(grepl("-dirty$", git_commit()))
})

test_that("write_result() adds the provenance columns, also to an empty table", {
  options(omop.provenance = list(git_commit = "abc", vocabulary_version = "v1"))
  on.exit(options(omop.provenance = NULL))
  path <- tempfile(fileext = ".csv")

  write_result(data.frame(x = 1:2), path)
  expect_equal(read.csv(path)$git_commit, c("abc", "abc"))

  write_result(data.frame(x = integer()), path)
  expect_named(read.csv(path), c("x", "git_commit", "vocabulary_version"))
})

# ---------------------------------------------------------------------------
# Checks on the real outputs. These need run_all.R first.
# ---------------------------------------------------------------------------

provenance_file <- repo_path("results", "provenance.yaml")

test_that("provenance.yaml has every field and the CDM's vocabulary version", {
  skip_if_not(file.exists(provenance_file), "provenance not written yet")
  provenance <- yaml::read_yaml(provenance_file)

  expect_true(all(c("git_commit", "vocabulary_version", "cdm_version", "dataset",
                    "r_version", "packages", "run_date") %in% names(provenance)))
  expect_match(provenance$git_commit, "^[0-9a-f]{40}(-dirty)?$")

  cdm <- open_cdm()
  on.exit(close_cdm(cdm))
  expect_equal(provenance$vocabulary_version, cdm_metadata(cdm)$vocabulary_version_vocabulary)
})

test_that("every results table carries the commit and vocabulary of this run", {
  skip_if_not(file.exists(provenance_file), "provenance not written yet")
  provenance <- yaml::read_yaml(provenance_file)

  files <- list.files(repo_path("results"), pattern = "\\.(csv|parquet)$",
                      recursive = TRUE, full.names = TRUE)
  expect_gt(length(files), 0)
  for (path in files) {
    data <- if (grepl("\\.parquet$", path)) {
      as.data.frame(arrow::read_parquet(path))
    } else {
      read.csv(path)
    }
    expect_true(all(provenance_columns %in% names(data)), info = path)
    expect_true(all(data$git_commit == provenance$git_commit), info = path)
    expect_true(all(data$vocabulary_version == provenance$vocabulary_version), info = path)
  }
})

test_that("CI uses the R version recorded in renv.lock", {
  lock <- jsonlite::read_json(repo_path("renv.lock"))
  workflow <- readLines(repo_path(".github", "workflows", "ci.yml"))
  r_version_line <- grep("r-version:", workflow, value = TRUE)
  expect_length(r_version_line, 1)
  expect_match(r_version_line, lock$R$Version, fixed = TRUE)
})
