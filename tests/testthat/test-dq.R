# ---------------------------------------------------------------------------
# Known-answer test for the data-quality SQL
#
# A tiny in-memory DuckDB with four hand-made people. Each data problem is
# planted on purpose, so we know exactly which rows each check must flag. The
# real files in sql/dq/ run against it unchanged.
#
#   person 1  one condition outside observation, one duplicated condition
#   person 2  dies before birth
#   person 3  has a drug record after death
#   person 4  is 121 years old at the end of observation
# ---------------------------------------------------------------------------

d <- as.Date

build_toy_cdm <- function() {
  con <- DBI::dbConnect(duckdb::duckdb())

  DBI::dbWriteTable(con, "person", data.frame(
    person_id      = 1:4,
    year_of_birth  = c(1960L, 1970L, 1950L, 1880L),
    month_of_birth = c(1L, NA, 6L, 1L),
    day_of_birth   = c(1L, NA, 15L, 1L)
  ))

  DBI::dbWriteTable(con, "observation_period", data.frame(
    person_id                     = 1:4,
    observation_period_start_date = d(c("2000-01-01", "2000-01-01", "2000-01-01", "2000-01-01")),
    observation_period_end_date   = d(c("2010-12-31", "2001-12-31", "2020-12-31", "2001-12-31"))
  ))

  DBI::dbWriteTable(con, "death", data.frame(
    person_id  = c(2L, 3L),
    death_date = d(c("1965-03-01", "2010-01-01"))
  ))

  # Person 1. Two identical rows on 2005-06-01 (one duplicate) and one row in
  # 2015, after the observation period ended.
  DBI::dbWriteTable(con, "condition_occurrence", data.frame(
    person_id                 = c(1L, 1L, 1L),
    condition_concept_id      = c(100L, 100L, 100L),
    condition_start_date      = d(c("2005-06-01", "2005-06-01", "2015-01-01")),
    condition_type_concept_id = c(32020L, 32020L, 32020L)
  ))

  # Person 3. One drug before death and one after, both inside observation.
  DBI::dbWriteTable(con, "drug_exposure", data.frame(
    person_id                = c(3L, 3L),
    drug_concept_id          = c(200L, 200L),
    drug_exposure_start_date = d(c("2005-01-01", "2012-01-01")),
    drug_type_concept_id     = c(32838L, 32838L)
  ))

  # The other event tables exist but are empty.
  empty_events <- list(
    visit_occurrence     = "visit_start_date",
    procedure_occurrence = "procedure_date",
    measurement          = "measurement_date",
    observation          = "observation_date",
    device_exposure      = "device_exposure_start_date"
  )
  for (table in names(empty_events)) {
    empty <- data.frame(person_id = integer(), date = as.Date(character()))
    names(empty)[2] <- empty_events[[table]]
    DBI::dbWriteTable(con, table, empty)
  }

  con
}

failing <- function(checks, check, table) {
  checks$rows_failing[checks$check_name == check & checks$table_name == table]
}

test_that("each check flags exactly the planted rows", {
  con <- build_toy_cdm()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  checks <- run_dq_checks(con, repo_path("sql", "dq"))

  expect_equal(failing(checks, "events_outside_observation", "condition_occurrence"), 1)
  expect_equal(failing(checks, "events_outside_observation", "drug_exposure"), 0)

  expect_equal(failing(checks, "death_before_birth", "death"), 1)

  expect_equal(failing(checks, "events_after_death", "drug_exposure"), 1)
  expect_equal(failing(checks, "events_after_death", "condition_occurrence"), 0)

  expect_equal(failing(checks, "duplicate_records", "condition_occurrence"), 1)
  expect_equal(failing(checks, "duplicate_records", "drug_exposure"), 0)

  expect_equal(failing(checks, "implausible_age", "observation_period"), 1)

  # Five problems were planted, and nothing else fails anywhere.
  expect_equal(sum(checks$rows_failing), 5)
})

test_that("a missing birth month and day do not flag a death in the birth year", {
  con <- build_toy_cdm()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  # Person 2 has no birth month or day. A death on 1970-01-01 is not provably
  # before birth, so it must not be flagged.
  DBI::dbExecute(con, "UPDATE death SET death_date = DATE '1970-01-01' WHERE person_id = 2")
  checks <- run_sql_file(con, repo_path("sql", "dq", "death_before_birth.sql"))

  expect_equal(as.numeric(checks$rows_failing), 0)
})

# ---------------------------------------------------------------------------
# Checks on the written results. These need run_all.R to have run first.
# ---------------------------------------------------------------------------

test_that("M1 results have the expected columns and valid shares", {
  dq_file <- repo_path("results", "m1_dq_checks.csv")
  skip_if_not(file.exists(dq_file), "results not written yet")

  dq <- read.csv(dq_file)
  expect_named(dq, c("check_name", "rule", "table_name", "rows_checked",
                     "rows_failing", "share_failing",
                     "git_commit", "vocabulary_version"))
  expect_true(all(dq$rows_failing <= dq$rows_checked))
  expect_true(all(dq$share_failing >= 0 & dq$share_failing <= 1, na.rm = TRUE))

  # A share is NA only for an empty table, and between 0 and 1 otherwise.
  zero <- read.csv(repo_path("results", "m1_concept_id_zero.csv"))
  expect_identical(is.na(zero$share_concept_zero), zero$n_rows == 0)
  expect_true(all(zero$share_concept_zero >= 0 & zero$share_concept_zero <= 1, na.rm = TRUE))
  expect_true(all(zero$n_concept_zero <= zero$n_rows))

  counts <- read.csv(repo_path("results", "m1_row_counts.csv"))
  expect_true(all(counts$n_persons <= counts$n_rows))
})
