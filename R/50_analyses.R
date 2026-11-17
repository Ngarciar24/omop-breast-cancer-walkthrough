# ---------------------------------------------------------------------------
# 50_analyses.R  (M5)
#
# Descriptive analyses on adsl_like and adtte_like. Run from run_all.R, which
# has already opened `cdm`. No p-values, no causal language. The data are
# synthetic and support no clinical conclusion.
#
#   1  Table 1 by first treatment group
#   2  Kaplan-Meier overall survival, overall and by first treatment group
#   3  CohortSurvival against our own survfit
#   4  Immortal-time bias, naive comparison against a 90-day landmark
# ---------------------------------------------------------------------------

library(gtsummary)
source("R/survival_helpers.R")

con <- CDMConnector::cdmCon(cdm)
dir.create("results/figures", recursive = TRUE, showWarnings = FALSE)

adsl <- DBI::dbReadTable(con, "adsl_like")
adtte <- DBI::dbReadTable(con, "adtte_like")
os <- merge(adtte[adtte$PARAMCD == "OS", ], adsl[, c("USUBJID", "FTRTCLS")], by = "USUBJID")

treatment_levels <- c("Anti-HER2 based", "CDK4/6 inhibitor based", "Chemotherapy",
                      "Endocrine only", "None within 90 days")
summary_years <- c(1, 2, 3, 5, 10)

# --- 1. Table 1 -----------------------------------------------------------
table1_data <- data.frame(
  FTRTCLS = factor(adsl$FTRTCLS, levels = treatment_levels),
  AGE = adsl$AGE,
  AGEGR1 = factor(adsl$AGEGR1, levels = c("<50", "50-64", "65-74", ">=75")),
  SEX = adsl$SEX,
  CMIHDFL = adsl$CMIHDFL == "Y",
  CMCVDFL = adsl$CMCVDFL == "Y",
  CMAFFL = adsl$CMAFFL == "Y",
  PRIOROBS = adsl$PRIOROBS,
  INDEXYR = as.numeric(format(adsl$INDEXDT, "%Y"))
)
table1_labels <- list(
  AGE ~ "Age at index, years",
  AGEGR1 ~ "Age group",
  SEX ~ "Sex",
  CMIHDFL ~ "Ischaemic heart disease before index",
  CMCVDFL ~ "Cerebrovascular disease before index",
  CMAFFL ~ "Atrial fibrillation before index",
  PRIOROBS ~ "Prior observation, days",
  INDEXYR ~ "Index year"
)

# tbl_summary only describes. No add_p(), on purpose.
table1 <- tbl_summary(
  table1_data,
  by = FTRTCLS,
  label = table1_labels,
  statistic = list(all_continuous() ~ "{median} ({p25}, {p75})")
) |>
  add_overall()

# Keep the group names and sizes as column headers, without the markdown bold
# and line breaks gtsummary puts in them.
table1_out <- as.data.frame(as_tibble(table1, col_labels = TRUE))
names(table1_out) <- gsub("\\s+", " ", trimws(gsub("\\*\\*", "", names(table1_out))))
write.csv(table1_out, "results/m5_table1.csv", row.names = FALSE)

# --- 2. Kaplan-Meier overall survival -------------------------------------
# Surv() wants 1 for an event. ADaM CNSR is 1 for censored, so use 1 - CNSR.
os$FTRTCLS <- factor(os$FTRTCLS, levels = treatment_levels)
fit_overall <- survfit(Surv(AVAL, 1 - CNSR) ~ 1, data = os)
fit_by_treatment <- survfit(Surv(AVAL, 1 - CNSR) ~ FTRTCLS, data = os)

km_os <- rbind(
  km_summary(fit_overall, summary_years * days_per_year),
  km_summary(fit_by_treatment, summary_years * days_per_year)
)
km_os$years <- km_os$time_days / days_per_year
write.csv(km_os, "results/m5_km_os.csv", row.names = FALSE)

ggsave("results/figures/m5_km_os_overall.png",
       km_plot(fit_overall, "Overall survival, all people"),
       width = 8, height = 5.5, dpi = 150, bg = "white")
ggsave("results/figures/m5_km_os_by_treatment.png",
       km_plot(fit_by_treatment, "Overall survival by first treatment group"),
       width = 8, height = 7, dpi = 150, bg = "white")

# --- 3. CohortSurvival against our own survfit ----------------------------
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
from_survfit <- km_summary(fit_overall, comparison_days)

survival_comparison <- data.frame(
  time_days = comparison_days,
  survfit = from_survfit$survival,
  cohort_survival = from_cohort_survival$estimate[match(comparison_days,
                                                        from_cohort_survival$time)]
)
survival_comparison$difference <- survival_comparison$survfit -
  survival_comparison$cohort_survival
write.csv(survival_comparison, "results/m5_survival_comparison.csv", row.names = FALSE)

# --- 4. Immortal-time bias ------------------------------------------------
# Naive version. "Ever treated" uses the whole follow-up, including time after
# index that the person had to survive before treatment started.
ttft <- adtte[adtte$PARAMCD == "TTFT", c("USUBJID", "CNSR")]
naive <- merge(adtte[adtte$PARAMCD == "OS", ], ttft, by = "USUBJID",
               suffixes = c("", "_TTFT"))
naive$group <- ifelse(naive$CNSR_TTFT == 0, "Ever treated", "Never treated")
fit_naive <- survfit(Surv(AVAL, 1 - CNSR) ~ group, data = naive)

# Landmark version. Only people still at risk after day 90, grouped by what
# they had received by day 90, followed from day 90.
landmark <- landmark_data(adsl, adtte, day = 90)
fit_landmark <- survfit(Surv(AVAL_LM, 1 - CNSR) ~ group, data = landmark)

immortal_time <- rbind(
  cbind(analysis = "Naive, from index",
        km_summary(fit_naive, c(2, 5) * days_per_year)),
  cbind(analysis = "Landmark at day 90, from day 90",
        km_summary(fit_landmark, c(2, 5) * days_per_year))
)
immortal_time$years <- immortal_time$time_days / days_per_year
group_sizes <- rbind(
  data.frame(analysis = "Naive, from index", as.data.frame(table(strata = naive$group),
                                                           responseName = "n_persons")),
  data.frame(analysis = "Landmark at day 90, from day 90",
             as.data.frame(table(strata = landmark$group), responseName = "n_persons"))
)
write.csv(immortal_time, "results/m5_immortal_time.csv", row.names = FALSE)
write.csv(group_sizes, "results/m5_immortal_time_groups.csv", row.names = FALSE)

ggsave("results/figures/m5_os_naive.png",
       km_plot(fit_naive, "Naive: ever against never treated, from index"),
       width = 8, height = 5.5, dpi = 150, bg = "white")
ggsave("results/figures/m5_os_landmark.png",
       km_plot(fit_landmark, "Landmark: treated by day 90 or not, from day 90",
               x_label = "Years from day 90"),
       width = 8, height = 5.5, dpi = 150, bg = "white")

message("\nKaplan-Meier OS")
print(km_os, row.names = FALSE)
message("\nCohortSurvival against survfit")
print(survival_comparison, row.names = FALSE)
message("\nImmortal-time bias")
print(group_sizes, row.names = FALSE)
print(immortal_time, row.names = FALSE)
