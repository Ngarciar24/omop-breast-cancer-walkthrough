# ---------------------------------------------------------------------------
# run_all.R: rebuild every step from the OMOP data, then run the tests
#
#   Rscript run_all.R
#
# Steps are numbered and run in order. A step whose script does not exist yet
# is skipped with a message, so the pipeline runs end to end from the start.
# ---------------------------------------------------------------------------

source("R/cdm.R")

steps <- c(
  "R/10_explore_dq.R",    # M1 row counts and data-quality checks
  "R/20_codelists.R",     # M2 concept sets and mapping
  "R/30_cohort.R",        # M3 cohort, SQL and CohortConstructor
  "R/40_analysis_data.R", # M4 adsl_like, adtte_like, data dictionary
  "R/50_analyses.R",      # M5 Table 1, Kaplan-Meier, immortal time
  "R/60_ard.R"            # M6 Analysis Results Data
)

cdm <- open_cdm()
print_cdm_metadata(cdm_metadata(cdm))

for (path in steps) {
  if (!file.exists(path)) {
    message("SKIP (not written yet): ", path)
    next
  }
  message("\n==> ", path)
  source(path)
}

# The tests open their own connection, so close this one first.
close_cdm(cdm)

message("\n==> tests")
testthat::test_dir("tests/testthat", stop_on_failure = TRUE)

message("\nAll steps run and all tests passed.")
