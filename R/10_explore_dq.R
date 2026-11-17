# ---------------------------------------------------------------------------
# 10_explore_dq.R  (M1)
#
# Describe the data and run the data-quality checks. Run from run_all.R, which
# has already opened `cdm`. Nothing here changes or filters the data. Failing
# rows are counted and reported, and later steps decide what to do with them.
#
# Writes five small tables to results/. They hold counts only, never rows
# about individual people.
# ---------------------------------------------------------------------------

source("R/sql.R")

con <- CDMConnector::cdmCon(cdm)
dir.create("results", showWarnings = FALSE)

# --- Exploration ----------------------------------------------------------
row_counts <- run_sql_file(con, "sql/explore/row_counts.sql")

observation_periods <- run_sql_file(con, "sql/explore/observation_periods.sql")

concept_id_zero <- run_sql_file(con, "sql/explore/concept_id_zero.sql")
# An empty table has no share. NA says so, where 0 / 0 would give NaN.
concept_id_zero$share_concept_zero <- ifelse(
  concept_id_zero$n_rows > 0,
  as.numeric(concept_id_zero$n_concept_zero) / as.numeric(concept_id_zero$n_rows),
  NA_real_
)

# --- Data-quality checks --------------------------------------------------
dq_checks <- run_dq_checks(con, "sql/dq")

# The duplicate check flags many drug records. This looks at what differs
# between the rows of each duplicate group.
drug_duplicate_detail <- run_sql_file(con, "sql/explore/drug_duplicate_detail.sql")

# --- Save and print -------------------------------------------------------
write.csv(row_counts, "results/m1_row_counts.csv", row.names = FALSE)
write.csv(observation_periods, "results/m1_observation_periods.csv", row.names = FALSE)
write.csv(concept_id_zero, "results/m1_concept_id_zero.csv", row.names = FALSE)
write.csv(dq_checks, "results/m1_dq_checks.csv", row.names = FALSE)
write.csv(drug_duplicate_detail, "results/m1_drug_duplicate_detail.csv", row.names = FALSE)

message("\nRow counts")
print(row_counts, row.names = FALSE)
message("\nObservation periods")
print(observation_periods, row.names = FALSE)
message("\nShare of records with concept_id = 0")
print(concept_id_zero, row.names = FALSE)
message("\nData-quality checks")
print(dq_checks[, c("check_name", "table_name", "rows_checked",
                    "rows_failing", "share_failing")], row.names = FALSE)
message("\nWhat differs inside duplicate drug groups")
print(drug_duplicate_detail, row.names = FALSE)
