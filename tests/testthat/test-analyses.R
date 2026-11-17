# ---------------------------------------------------------------------------
# Known-answer test for the landmark dataset
#
#   A  dies on day 30                        out, not at risk after day 90
#   B  dies on day 90                        out, not at risk after day 90
#   C  treated on day 60, alive to day 500   in, treated by day 90, time 410
#   D  treated on day 120, dies on day 300   in, not treated by day 90, time 210
#   E  never treated, censored on day 1000   in, not treated by day 90, time 910
# ---------------------------------------------------------------------------

test_that("landmark_data keeps the right people, groups and times", {
  index <- as.Date("2020-01-01")
  adsl <- data.frame(
    USUBJID = c("A", "B", "C", "D", "E"),
    FTRTFL = c("N", "N", "Y", "N", "N"),
    FTRTDT = index + c(NA, NA, 60, NA, NA),
    INDEXDT = index
  )
  # FTRTDT is only set within 90 days, so D's day-120 treatment is not in it.
  adtte <- data.frame(
    USUBJID = c("A", "B", "C", "D", "E"),
    PARAMCD = "OS",
    AVAL = c(30, 90, 500, 300, 1000),
    CNSR = c(0, 0, 1, 0, 1)
  )

  landmark <- landmark_data(adsl, adtte, day = 90)
  landmark <- landmark[order(landmark$USUBJID), ]

  expect_equal(landmark$USUBJID, c("C", "D", "E"))
  expect_equal(landmark$group, c("Treated by day 90", "Not treated by day 90",
                                 "Not treated by day 90"))
  expect_equal(landmark$AVAL_LM, c(410, 210, 910))
  expect_equal(landmark$CNSR, c(1, 0, 1))
})

test_that("km_summary counts everyone at risk at time 0", {
  data <- data.frame(time = c(5, 10, 15, 20), event = c(1, 0, 1, 1),
                     group = c("a", "a", "b", "b"))
  fit <- survival::survfit(survival::Surv(time, event) ~ group, data = data)
  at_zero <- km_summary(fit, times = 0)
  expect_equal(at_zero$n_risk, c(2, 2))
  expect_equal(at_zero$survival, c(1, 1))
})

# ---------------------------------------------------------------------------
# Checks on the real results. These need run_all.R first.
# ---------------------------------------------------------------------------

test_that("CohortSurvival and survfit agree to 3 decimal places", {
  file <- repo_path("results", "m5_survival_comparison.csv")
  skip_if_not(file.exists(file), "results not written yet")

  comparison <- read.csv(file)
  expect_equal(nrow(comparison), 4)
  expect_false(anyNA(comparison$cohort_survival))
  # 3 decimal places means the difference rounds to zero at the third decimal.
  expect_true(all(abs(comparison$difference) < 5e-4))
})

test_that("group sizes add up to the cohort and match the numbers at risk", {
  cdm <- open_cdm()
  on.exit(close_cdm(cdm))
  con <- CDMConnector::cdmCon(cdm)
  skip_if_not("adsl_like" %in% DBI::dbListTables(con), "datasets not built yet")

  adsl <- DBI::dbReadTable(con, "adsl_like")
  adtte <- DBI::dbReadTable(con, "adtte_like")
  os <- merge(adtte[adtte$PARAMCD == "OS", ], adsl[, c("USUBJID", "FTRTCLS")])

  group_sizes <- table(adsl$FTRTCLS)
  expect_equal(sum(group_sizes), nrow(adsl))

  fit <- survival::survfit(survival::Surv(AVAL, 1 - CNSR) ~ FTRTCLS, data = os)
  at_zero <- km_summary(fit, times = 0)
  expect_equal(at_zero$n_risk, as.numeric(group_sizes[at_zero$strata]))
})

test_that("the report uses no causal language", {
  report <- tolower(paste(readLines(repo_path("report", "report.qmd")), collapse = " "))
  causal_phrases <- c("effect of", "caused by", "causes", "reduces the risk",
                      "increases the risk", "protective", "improves survival",
                      "worsens survival", "leads to", "benefit of")
  for (phrase in causal_phrases) {
    expect_false(grepl(phrase, report, fixed = TRUE), info = phrase)
  }
})
