# ---------------------------------------------------------------------------
# Known-answer test for adsl_like and adtte_like
#
# Hand-made cohort. Everyone has index 2020-01-01 and observation from
# 2010-01-01 to 2022-12-31. Concepts 300, 400 and 500 are endocrine therapy,
# CDK4/6 inhibitor and chemotherapy. 600 and 700 are ischaemic heart disease
# and atrial fibrillation.
#
#   person 1  dies 2021-06-01                           OS event
#   person 2  dies 2023-03-01, after observation ends   OS censored at 2022-12-31
#   person 3  no death                                  OS censored at 2022-12-31
#   person 4  endocrine on the index day                Endocrine only, TTFT 0
#   person 5  chemotherapy first on day 95              None within 90 days,
#                                                       TTFT event at day 95
#   person 6  CDK4/6 and endocrine on the same day      CDK4/6 inhibitor based
#   person 7  IHD in 2000, AF after index               CMIHDFL Y, CMAFFL N
#   person 8  dies 2020-06-01, drug record after death  TTFT censored at death
# ---------------------------------------------------------------------------

d <- as.Date
index <- d("2020-01-01")
obs_end <- d("2022-12-31")

build_toy_analysis_cdm <- function() {
  con <- DBI::dbConnect(duckdb::duckdb())

  DBI::dbWriteTable(con, "breast_cancer_sql", data.frame(
    cohort_definition_id = 1L, subject_id = 1:8,
    cohort_start_date = index, cohort_end_date = obs_end
  ))
  DBI::dbWriteTable(con, "observation_period", data.frame(
    person_id = 1:8,
    observation_period_start_date = d("2010-01-01"),
    observation_period_end_date = obs_end
  ))
  DBI::dbWriteTable(con, "person", data.frame(
    person_id = 1:8, gender_concept_id = 8532L,
    year_of_birth = 1960L, month_of_birth = 6L, day_of_birth = 15L
  ))
  DBI::dbWriteTable(con, "concept", data.frame(concept_id = 8532L, concept_name = "FEMALE"))
  DBI::dbWriteTable(con, "death", data.frame(
    person_id = c(1L, 2L, 8L),
    death_date = d(c("2021-06-01", "2023-03-01", "2020-06-01"))
  ))
  DBI::dbWriteTable(con, "condition_occurrence", data.frame(
    person_id = c(7L, 7L),
    condition_concept_id = c(600L, 700L),
    condition_start_date = d(c("2000-01-01", "2020-02-01"))
  ))
  DBI::dbWriteTable(con, "drug_exposure", data.frame(
    person_id = c(4L, 5L, 6L, 6L, 8L),
    drug_concept_id = c(300L, 500L, 400L, 300L, 500L),
    drug_exposure_start_date = d(c("2020-01-01", "2020-04-05", "2020-01-10",
                                   "2020-01-10", "2020-07-01"))
  ))

  con
}

toy_codelists <- list(
  comorbidity = data.frame(class = c("ischaemic_heart_disease", "atrial_fibrillation"),
                           concept_id = c(600L, 700L)),
  treatment = data.frame(class = c("endocrine_therapy", "cdk46_inhibitor", "chemotherapy"),
                         concept_id = c(300L, 400L, 500L))
)

run_toy <- function() {
  con <- build_toy_analysis_cdm()
  result <- run_analysis_sql(con, toy_codelists$comorbidity, toy_codelists$treatment,
                             repo_path("sql", "analysis"))
  DBI::dbDisconnect(con, shutdown = TRUE)
  result
}

row_of <- function(data, person, param = NULL) {
  keep <- data$USUBJID == as.character(person)
  if (!is.null(param)) keep <- keep & data$PARAMCD == param
  data[keep, ]
}

test_that("overall survival events and censoring follow the rules", {
  adtte <- run_toy()$adtte_like

  p1 <- row_of(adtte, 1, "OS")
  expect_equal(p1$CNSR, 0)
  expect_equal(p1$ADT, d("2021-06-01"))
  expect_equal(p1$AVAL, as.numeric(d("2021-06-01") - index))

  p2 <- row_of(adtte, 2, "OS")
  expect_equal(p2$CNSR, 1)
  expect_equal(p2$ADT, obs_end)

  p3 <- row_of(adtte, 3, "OS")
  expect_equal(p3$CNSR, 1)
  expect_equal(p3$CNSDTDSC, "END OF OBSERVATION")
})

test_that("time to first treatment follows the rules", {
  adtte <- run_toy()$adtte_like

  expect_equal(row_of(adtte, 4, "TTFT")$AVAL, 0)
  expect_equal(row_of(adtte, 4, "TTFT")$CNSR, 0)

  expect_equal(row_of(adtte, 5, "TTFT")$AVAL, 95)
  expect_equal(row_of(adtte, 5, "TTFT")$CNSR, 0)

  p8 <- row_of(adtte, 8, "TTFT")
  expect_equal(p8$CNSR, 1)
  expect_equal(p8$ADT, d("2020-06-01"))
  expect_equal(p8$CNSDTDSC, "DEATH")
})

test_that("first treatment class, flags and death follow the rules", {
  adsl <- run_toy()$adsl_like

  expect_equal(row_of(adsl, 4)$FTRTCLS, "Endocrine only")
  expect_equal(row_of(adsl, 5)$FTRTCLS, "None within 90 days")
  expect_equal(row_of(adsl, 5)$FTRTFL, "N")
  expect_equal(row_of(adsl, 6)$FTRTCLS, "CDK4/6 inhibitor based")
  expect_equal(row_of(adsl, 6)$FTRTALL, "cdk46_inhibitor + endocrine_therapy")

  expect_equal(row_of(adsl, 7)$CMIHDFL, "Y")
  expect_equal(row_of(adsl, 7)$CMAFFL, "N")

  expect_equal(row_of(adsl, 1)$DTHFL, "Y")
  expect_equal(row_of(adsl, 2)$DTHFL, "N")
  expect_true(is.na(row_of(adsl, 2)$DTHDT))

  # Born 1960-06-15, so 59 on 2020-01-01.
  expect_true(all(adsl$AGE == 59))
  expect_true(all(adsl$AGEGR1 == "50-64"))
})

# ---------------------------------------------------------------------------
# Checks on the real datasets. These need run_all.R first.
# ---------------------------------------------------------------------------

read_analysis_tables <- function() {
  cdm <- open_cdm()
  con <- CDMConnector::cdmCon(cdm)
  if (!all(c("adsl_like", "adtte_like") %in% DBI::dbListTables(con))) {
    close_cdm(cdm)
    return(NULL)
  }
  out <- list(
    adsl_like = DBI::dbReadTable(con, "adsl_like"),
    adtte_like = DBI::dbReadTable(con, "adtte_like"),
    cohort = DBI::dbReadTable(con, "breast_cancer_sql")
  )
  close_cdm(cdm)
  out
}

test_that("one row per person, and one per person and parameter", {
  tables <- read_analysis_tables()
  skip_if(is.null(tables), "analysis datasets not built yet")

  expect_equal(nrow(tables$adsl_like), nrow(tables$cohort))
  expect_equal(anyDuplicated(tables$adsl_like$USUBJID), 0)

  expect_equal(nrow(tables$adtte_like), 2 * nrow(tables$adsl_like))
  expect_equal(anyDuplicated(tables$adtte_like[, c("USUBJID", "PARAMCD")]), 0)
})

test_that("no negative times, and every date inside follow-up", {
  tables <- read_analysis_tables()
  skip_if(is.null(tables), "analysis datasets not built yet")

  adtte <- merge(tables$adtte_like, tables$adsl_like[, c("USUBJID", "OBSENDDT")],
                 by = "USUBJID")
  expect_true(all(adtte$AVAL >= 0))
  expect_true(all(adtte$ADT >= adtte$STARTDT))
  expect_true(all(adtte$ADT <= adtte$OBSENDDT))
  expect_true(all(adtte$CNSR %in% c(0, 1)))
  expect_identical(!is.na(adtte$EVNTDESC), adtte$CNSR == 0)
  expect_identical(!is.na(adtte$CNSDTDSC), adtte$CNSR == 1)
})

test_that("the data dictionary and the datasets list the same variables", {
  tables <- read_analysis_tables()
  skip_if(is.null(tables), "analysis datasets not built yet")
  dictionary <- yaml::read_yaml(repo_path("data-dictionary.yaml"))$datasets

  is_type <- function(x, type) {
    switch(type,
           character = is.character(x),
           integer = is.numeric(x) && all(x == round(x), na.rm = TRUE),
           date = inherits(x, "Date"))
  }

  for (dataset in c("adsl_like", "adtte_like")) {
    variables <- dictionary[[dataset]]$variables
    names_in_dictionary <- vapply(variables, function(v) v$name, character(1))

    # Both directions. Nothing undocumented, nothing documented but missing.
    expect_setequal(names_in_dictionary, names(tables[[dataset]]))

    for (v in variables) {
      expect_true(is_type(tables[[dataset]][[v$name]], v$type),
                  info = paste(dataset, v$name, v$type))
      expect_true(nzchar(v$label) && nzchar(v$derivation),
                  info = paste(dataset, v$name))
    }
  }
})

test_that("age, sex and comorbidity flags equal PatientProfiles", {
  tables <- read_analysis_tables()
  skip_if(is.null(tables), "analysis datasets not built yet")

  cdm <- open_cdm()
  on.exit(close_cdm(cdm))
  cdm <- CDMConnector::cdmFromCon(CDMConnector::cdmCon(cdm), cdmSchema = "main",
                                  writeSchema = "main",
                                  cohortTables = "breast_cancer_cc")

  comorbidity <- read.csv(repo_path("codelists", "comorbidity.csv"))
  concept_set <- split(comorbidity$concept_id, comorbidity$class)

  # window c(-Inf, -1) is any time up to the day before index.
  # inObservation = FALSE matches "all available history".
  from_package <- cdm$breast_cancer_cc |>
    PatientProfiles::addAge(ageMissingMonth = 1, ageMissingDay = 1) |>
    PatientProfiles::addSex() |>
    PatientProfiles::addConceptIntersectFlag(
      conceptSet = concept_set,
      window = list(c(-Inf, -1)),
      inObservation = FALSE,
      nameStyle = "{concept_name}"
    ) |>
    dplyr::collect()

  from_package$USUBJID <- as.character(from_package$subject_id)
  both <- merge(tables$adsl_like, from_package, by = "USUBJID")
  expect_equal(nrow(both), nrow(tables$adsl_like))

  expect_equal(both$AGE, as.numeric(both$age))
  expect_equal(both$SEX, substr(toupper(both$sex), 1, 1))
  yn <- function(x) ifelse(x == 1, "Y", "N")
  expect_equal(both$CMIHDFL, yn(both$ischaemic_heart_disease))
  expect_equal(both$CMCVDFL, yn(both$cerebrovascular_disease))
  expect_equal(both$CMAFFL, yn(both$atrial_fibrillation))
})
