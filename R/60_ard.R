# ---------------------------------------------------------------------------
# 60_ard.R  (M6)
#
# Store the Table 1 statistics and the survival estimates as Analysis Results
# Data (ARD), with cards and cardx. Run from run_all.R, which has already
# opened `cdm`. The report builds its tables from these files and never from
# the patient-level data.
#
# Writes results/ard/ as Parquet (for code) and CSV (for people). The two hold
# the same rows.
# ---------------------------------------------------------------------------

source("R/survival_helpers.R")
source("R/ard_helpers.R")

con <- CDMConnector::cdmCon(cdm)
dir.create("results/ard", recursive = TRUE, showWarnings = FALSE)

adsl <- DBI::dbReadTable(con, "adsl_like")
adtte <- DBI::dbReadTable(con, "adtte_like")

# --- Table 1 --------------------------------------------------------------
ard_table1 <- flatten_ard(table1_ard(table1_input(adsl)))

# --- Survival -------------------------------------------------------------
# Time 0 is included, so the number at risk there is the size of each group.
fits <- os_fits(adsl, adtte, landmark_day = 90)
ard_survival <- survival_ard(fits, times_days = c(0, 1, 2, 3, 5, 10) * days_per_year)

# --- Save -----------------------------------------------------------------
arrow::write_parquet(ard_table1, "results/ard/m6_table1_ard.parquet")
write.csv(ard_table1, "results/ard/m6_table1_ard.csv", row.names = FALSE)
arrow::write_parquet(ard_survival, "results/ard/m6_survival_ard.parquet")
write.csv(ard_survival, "results/ard/m6_survival_ard.csv", row.names = FALSE)

message("\nARD rows: Table 1 ", nrow(ard_table1), ", survival ", nrow(ard_survival))
print(table1_from_ard(ard_table1), row.names = FALSE)
