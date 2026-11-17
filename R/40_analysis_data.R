# ---------------------------------------------------------------------------
# 40_analysis_data.R  (M4)
#
# Build adsl_like (one row per person) and adtte_like (one row per person and
# parameter) from the M3 cohort. Run from run_all.R, which has already opened
# `cdm`. The variables follow ADaM naming as a convention only. These are not
# CDISC-conformant datasets.
#
# Both datasets are person-level, so they stay as tables in the DuckDB working
# copy. Only counts go to results/. Every variable is described in
# data-dictionary.yaml.
# ---------------------------------------------------------------------------

source("R/sql.R")
source("R/analysis_sql.R")

con <- CDMConnector::cdmCon(cdm)

analysis <- run_analysis_sql(
  con,
  comorbidity = read.csv("codelists/comorbidity.csv"),
  treatment = read.csv("codelists/treatment.csv"),
  sql_dir = "sql/analysis"
)
adsl_like <- analysis$adsl_like
adtte_like <- analysis$adtte_like

# --- Counts for the report ------------------------------------------------
comorbidity_lookback <- run_sql_file(con, "sql/analysis/comorbidity_lookback.sql")

first_treatment <- as.data.frame(
  table(FTRTCLS = adsl_like$FTRTCLS, FTRTALL = adsl_like$FTRTALL, useNA = "ifany"),
  responseName = "n_persons"
)
first_treatment <- first_treatment[first_treatment$n_persons > 0, ]

tte_summary <- do.call(rbind, lapply(split(adtte_like, adtte_like$PARAMCD), function(x) {
  data.frame(
    PARAMCD = x$PARAMCD[1],
    n_persons = nrow(x),
    n_events = sum(x$CNSR == 0),
    n_censored = sum(x$CNSR == 1),
    median_aval_events = median(x$AVAL[x$CNSR == 0]),
    min_aval = min(x$AVAL),
    max_aval = max(x$AVAL)
  )
}))

censoring_reasons <- as.data.frame(
  table(PARAMCD = adtte_like$PARAMCD[adtte_like$CNSR == 1],
        CNSDTDSC = adtte_like$CNSDTDSC[adtte_like$CNSR == 1]),
  responseName = "n_persons"
)
censoring_reasons <- censoring_reasons[censoring_reasons$n_persons > 0, ]

write.csv(comorbidity_lookback, "results/m4_comorbidity_lookback.csv", row.names = FALSE)
write.csv(first_treatment, "results/m4_first_treatment.csv", row.names = FALSE)
write.csv(tte_summary, "results/m4_tte_summary.csv", row.names = FALSE)
write.csv(censoring_reasons, "results/m4_censoring_reasons.csv", row.names = FALSE)

message("\nadsl_like: ", nrow(adsl_like), " rows, adtte_like: ", nrow(adtte_like), " rows")
message("\nComorbidity look-back")
print(comorbidity_lookback, row.names = FALSE)
message("\nFirst treatment within 90 days")
print(first_treatment, row.names = FALSE)
message("\nTime-to-event parameters")
print(tte_summary, row.names = FALSE)
print(censoring_reasons, row.names = FALSE)
