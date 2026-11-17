# ---------------------------------------------------------------------------
# 50_analyses.R  (M5)
#
# Descriptive analyses on adsl_like and adtte_like. Run from run_all.R, which
# has already opened `cdm`. No p-values, no causal language. The data are
# synthetic and support no clinical conclusion.
#
#   1  Kaplan-Meier figures, overall and by first treatment group
#   2  CohortSurvival against our own survfit
#   3  Immortal-time bias figures, naive against a 90-day landmark
#
# Table 1 and the survival estimates are stored as Analysis Results Data in
# M6 (R/60_ard.R). The report builds its tables from there.
# ---------------------------------------------------------------------------

source("R/survival_helpers.R")

con <- CDMConnector::cdmCon(cdm)
dir.create("results/figures", recursive = TRUE, showWarnings = FALSE)

adsl <- DBI::dbReadTable(con, "adsl_like")
adtte <- DBI::dbReadTable(con, "adtte_like")
fits <- os_fits(adsl, adtte, landmark_day = 90)

# Every figure carries the commit and vocabulary version in its caption.
stamp <- provenance_caption()

# --- 1. Kaplan-Meier figures ----------------------------------------------
ggsave("results/figures/m5_km_os_overall.png",
       km_plot(fits$overall, "Overall survival, all people", caption = stamp),
       width = 8, height = 5.5, dpi = 150, bg = "white")
ggsave("results/figures/m5_km_os_by_treatment.png",
       km_plot(fits$by_treatment, "Overall survival by first treatment group",
               caption = stamp),
       width = 8, height = 7, dpi = 150, bg = "white")

# --- 2. CohortSurvival against our own survfit ----------------------------
# The death cohort starts on each person's death date. CohortSurvival follows
# people from cohort start to the end of their observation period, which is
# the same rule as OS in adtte_like.
cdm$death_cohort <- CohortConstructor::deathCohort(cdm, name = "death_cohort")
cdm <- CDMConnector::cdmFromCon(con, cdmSchema = "main", writeSchema = "main",
                                cohortTables = c("breast_cancer_cc", "death_cohort"))

cs_result <- CohortSurvival::estimateSingleEventSurvival(
  cdm,
  targetCohortTable = "breast_cancer_cc",
  outcomeCohortTable = "death_cohort"
)
cs_estimates <- CohortSurvival::asSurvivalResult(cs_result)

comparison_days <- round(c(1, 2, 3, 5) * days_per_year)
from_cohort_survival <- cs_estimates[cs_estimates$time %in% comparison_days,
                                     c("time", "estimate")]
from_survfit <- km_summary(fits$overall, comparison_days)

survival_comparison <- data.frame(
  time_days = comparison_days,
  survfit = from_survfit$survival,
  cohort_survival = from_cohort_survival$estimate[match(comparison_days,
                                                        from_cohort_survival$time)]
)
survival_comparison$difference <- survival_comparison$survfit -
  survival_comparison$cohort_survival
write_result(survival_comparison, "results/m5_survival_comparison.csv")

# --- 3. Immortal-time bias figures ----------------------------------------
ggsave("results/figures/m5_os_naive.png",
       km_plot(fits$naive, "Naive: ever against never treated, from index",
               caption = stamp),
       width = 8, height = 5.5, dpi = 150, bg = "white")
ggsave("results/figures/m5_os_landmark.png",
       km_plot(fits$landmark, "Landmark: treated by day 90 or not, from day 90",
               x_label = "Years from day 90", caption = stamp),
       width = 8, height = 5.5, dpi = 150, bg = "white")

message("\nCohortSurvival against survfit")
print(survival_comparison, row.names = FALSE)
