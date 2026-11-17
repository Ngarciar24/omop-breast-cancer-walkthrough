# ---------------------------------------------------------------------------
# 30_cohort.R  (M3)
#
# Build the breast cancer cohort twice, once with hand-written SQL and once
# with CohortConstructor. A test checks that both give the same people and
# the same dates. Run from run_all.R, which has already opened `cdm`.
#
# Definition
#   Index date   first breast cancer record inside an observation period
#   Inclusion    365 days of prior observation, age 18 or older at index
#   End date     end of the observation period that contains the index date
#   Sex          recorded, not filtered on
#
# Both cohort tables stay in the DuckDB working copy. Only counts go to the
# results folder.
# ---------------------------------------------------------------------------

library(CohortConstructor)
source("R/sql.R")
source("R/cohort_sql.R")

con <- CDMConnector::cdmCon(cdm)
breast_cancer_ids <- read.csv("codelists/breast_cancer.csv")$concept_id

# --- Version 1: hand-written SQL ------------------------------------------
cohort_sql <- run_cohort_sql(con, breast_cancer_ids, "sql/cohort")
DBI::dbWriteTable(con, "breast_cancer_sql", cohort_sql$cohort, overwrite = TRUE)

# --- Version 2: CohortConstructor -----------------------------------------
# Each line matches one SQL step.
#   conceptCohort()          steps 1 and 2. Records outside observation are
#                            dropped by default.
#   requireIsFirstEntry()    step 3, the earliest record per person
#   requirePriorObservation  step 4
#   requireAge()             step 5. ageRange is inclusive, Inf means no top.
#   exitAtObservationEnd()   end date
cdm$breast_cancer_cc <- conceptCohort(
  cdm,
  conceptSet = list(breast_cancer = breast_cancer_ids),
  name = "breast_cancer_cc"
) |>
  requireIsFirstEntry() |>
  requirePriorObservation(minPriorObservation = 365) |>
  requireAge(ageRange = list(c(18, Inf))) |>
  exitAtObservationEnd()

attrition_cc <- omopgenerics::attrition(cdm$breast_cancer_cc)

# --- Summary --------------------------------------------------------------
in_cohort <- cohort_sql$candidates[cohort_sql$candidates$has_prior_observation &
                                     cohort_sql$candidates$is_adult, ]
sex_counts <- table(in_cohort$sex, useNA = "ifany")

# The prior-observation rule removes the most people, so describe them.
too_short <- cohort_sql$candidates[!cohort_sql$candidates$has_prior_observation, ]

cohort_summary <- rbind(
  data.frame(variable = "persons", level = "", value = nrow(in_cohort)),
  data.frame(variable = "sex", level = names(sex_counts),
             value = as.numeric(sex_counts)),
  data.frame(variable = "age_at_index",
             level = c("median", "min", "max"),
             value = c(median(in_cohort$age_at_index),
                       min(in_cohort$age_at_index),
                       max(in_cohort$age_at_index))),
  data.frame(variable = "index_year",
             level = c("min", "max"),
             value = as.numeric(format(range(in_cohort$index_date), "%Y"))),
  data.frame(variable = "excluded_for_prior_observation",
             level = c("persons", "median_prior_days", "with_0_prior_days"),
             value = c(nrow(too_short),
                       median(too_short$prior_observation_days),
                       sum(too_short$prior_observation_days == 0)))
)

write_result(cohort_sql$attrition, "results/m3_attrition_sql.csv")
write_result(attrition_cc, "results/m3_attrition_cohortconstructor.csv")
write_result(cohort_summary, "results/m3_cohort_summary.csv")

message("\nAttrition (SQL)")
print(cohort_sql$attrition, row.names = FALSE)
message("\nAttrition (CohortConstructor)")
print(as.data.frame(attrition_cc[, c("reason", "number_records", "number_subjects")]),
      row.names = FALSE)
message("\nCohort summary")
print(cohort_summary, row.names = FALSE)
