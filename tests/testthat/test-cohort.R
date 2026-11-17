# ---------------------------------------------------------------------------
# Known-answer test for the cohort SQL
#
# Hand-made people, each sitting on one boundary of the definition. Code 100
# is in the toy breast cancer codelist and code 999 is not.
#
#   person 1  first record outside observation, second inside   in, index 2018-06-01
#   person 2  exactly 364 days of prior observation             out
#   person 3  exactly 365 days of prior observation             in, index 2020-01-01
#   person 4  turns 18 on the index date                        in, index 2020-03-15
#   person 5  turns 18 the day after the index date             out
#   person 6  two records, the earlier one has the larger ID    in, index 2017-01-01
#   person 7  only a condition outside the codelist             not a candidate
# ---------------------------------------------------------------------------

d <- as.Date

build_toy_cohort_cdm <- function() {
  con <- DBI::dbConnect(duckdb::duckdb())

  DBI::dbWriteTable(con, "person", data.frame(
    person_id         = 1:7,
    gender_concept_id = c(8532L, 8532L, 8532L, 8532L, 8532L, 8507L, 8532L),
    year_of_birth     = c(1970L, 1960L, 1960L, 2002L, 2002L, 1950L, 1960L),
    month_of_birth    = c(1L, 1L, 1L, 3L, 3L, 1L, 1L),
    day_of_birth      = c(1L, 1L, 1L, 15L, 16L, 1L, 1L)
  ))

  DBI::dbWriteTable(con, "concept", data.frame(
    concept_id   = c(8532L, 8507L),
    concept_name = c("FEMALE", "MALE")
  ))

  # 2019 is not a leap year, so 2019-01-01 to 2019-12-31 is 364 days and
  # 2019-01-01 to 2020-01-01 is 365 days.
  DBI::dbWriteTable(con, "observation_period", data.frame(
    person_id                     = 1:7,
    observation_period_start_date = d(c("2016-01-01", "2019-01-01", "2019-01-01",
                                        "2010-01-01", "2010-01-01", "2010-01-01",
                                        "2010-01-01")),
    observation_period_end_date   = d(rep("2022-12-31", 7))
  ))

  DBI::dbWriteTable(con, "condition_occurrence", data.frame(
    condition_occurrence_id = c(1L, 2L, 3L, 4L, 5L, 6L, 8L, 7L, 9L),
    person_id               = c(1L, 1L, 2L, 3L, 4L, 5L, 6L, 6L, 7L),
    condition_concept_id    = c(100L, 100L, 100L, 100L, 100L, 100L, 100L, 100L, 999L),
    condition_start_date    = d(c("2015-01-01", "2018-06-01", "2019-12-31",
                                  "2020-01-01", "2020-03-15", "2020-03-15",
                                  "2017-01-01", "2018-01-01", "2020-01-01"))
  ))

  con
}

test_that("the cohort SQL includes and excludes exactly the planted people", {
  con <- build_toy_cohort_cdm()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  result <- run_cohort_sql(con, codelist_ids = 100L, repo_path("sql", "cohort"))

  expect_equal(result$cohort$subject_id, c(1, 3, 4, 6))
  expect_equal(result$cohort$cohort_start_date,
               d(c("2018-06-01", "2020-01-01", "2020-03-15", "2017-01-01")))
  expect_equal(result$cohort$cohort_end_date, d(rep("2022-12-31", 4)))
})

test_that("the boundary values are computed as planted", {
  con <- build_toy_cohort_cdm()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  candidates <- run_cohort_sql(con, 100L, repo_path("sql", "cohort"))$candidates
  value <- function(person, column) candidates[[column]][candidates$person_id == person]

  expect_equal(value(2, "prior_observation_days"), 364)
  expect_equal(value(3, "prior_observation_days"), 365)
  expect_equal(value(4, "age_at_index"), 18)
  expect_equal(value(5, "age_at_index"), 17)
  expect_false(7 %in% candidates$person_id)
})

test_that("the SQL attrition counts match the planted people", {
  con <- build_toy_cohort_cdm()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  attrition <- run_cohort_sql(con, 100L, repo_path("sql", "cohort"))$attrition

  # Records. Persons 1 and 6 have two records each, the others one.
  expect_equal(attrition$n_records, c(8, 7, 6, 5, 4))
  expect_equal(attrition$n_persons, c(6, 6, 6, 5, 4))
})

# ---------------------------------------------------------------------------
# SQL against CohortConstructor on the real data. Needs run_all.R first.
# ---------------------------------------------------------------------------

test_that("SQL and CohortConstructor give the same people and dates", {
  cdm <- open_cdm()
  on.exit(close_cdm(cdm))
  con <- CDMConnector::cdmCon(cdm)
  skip_if_not(all(c("breast_cancer_sql", "breast_cancer_cc") %in% DBI::dbListTables(con)),
              "cohorts not built yet")

  columns <- c("subject_id", "cohort_start_date", "cohort_end_date")
  from_sql <- DBI::dbReadTable(con, "breast_cancer_sql")[, columns]
  from_cc <- DBI::dbReadTable(con, "breast_cancer_cc")[, columns]

  from_sql <- from_sql[order(from_sql$subject_id), ]
  from_cc <- from_cc[order(from_cc$subject_id), ]
  rownames(from_sql) <- NULL
  rownames(from_cc) <- NULL

  expect_gt(nrow(from_sql), 0)
  expect_equal(from_sql$subject_id, as.numeric(from_cc$subject_id))
  expect_equal(from_sql$cohort_start_date, from_cc$cohort_start_date)
  expect_equal(from_sql$cohort_end_date, from_cc$cohort_end_date)
})

test_that("the cohort has one row per person and dates inside observation", {
  cdm <- open_cdm()
  on.exit(close_cdm(cdm))
  con <- CDMConnector::cdmCon(cdm)
  skip_if_not("breast_cancer_sql" %in% DBI::dbListTables(con), "cohort not built yet")

  cohort <- DBI::dbReadTable(con, "breast_cancer_sql")
  expect_equal(anyDuplicated(cohort$subject_id), 0)
  expect_true(all(cohort$cohort_start_date <= cohort$cohort_end_date))

  # Every start and end date must sit inside one observation period of the
  # same person.
  n_inside <- DBI::dbGetQuery(con, "
    SELECT COUNT(*) AS n
    FROM breast_cancer_sql c
    INNER JOIN observation_period op
      ON op.person_id = c.subject_id
     AND c.cohort_start_date BETWEEN op.observation_period_start_date
                                 AND op.observation_period_end_date
     AND c.cohort_end_date BETWEEN op.observation_period_start_date
                               AND op.observation_period_end_date
  ")$n
  expect_equal(n_inside, nrow(cohort))
})

test_that("the final attrition count agrees between the two versions", {
  sql_file <- repo_path("results", "m3_attrition_sql.csv")
  skip_if_not(file.exists(sql_file), "results not written yet")

  from_sql <- read.csv(sql_file)
  from_cc <- read.csv(repo_path("results", "m3_attrition_cohortconstructor.csv"))
  expect_equal(tail(from_sql$n_persons, 1), tail(from_cc$number_subjects, 1))
})
