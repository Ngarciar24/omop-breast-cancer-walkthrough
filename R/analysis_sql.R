# ---------------------------------------------------------------------------
# analysis_sql.R
#
# Run the SQL in sql/analysis/ in the right order. Used by
# R/40_analysis_data.R on the real data and by the tests on hand-made data.
# Expects the cohort table breast_cancer_sql to exist already.
# ---------------------------------------------------------------------------

run_analysis_sql <- function(con, comorbidity, treatment, sql_dir = "sql/analysis") {
  DBI::dbWriteTable(con, "comorbidity_codelist", unique(comorbidity[, c("class", "concept_id")]),
                    temporary = TRUE, overwrite = TRUE)
  DBI::dbWriteTable(con, "treatment_codelist", unique(treatment[, c("class", "concept_id")]),
                    temporary = TRUE, overwrite = TRUE)

  adsl_like <- run_sql_file(con, file.path(sql_dir, "adsl_like.sql"))
  DBI::dbWriteTable(con, "adsl_like", adsl_like, overwrite = TRUE)

  adtte_like <- run_sql_file(con, file.path(sql_dir, "adtte_like.sql"))
  DBI::dbWriteTable(con, "adtte_like", adtte_like, overwrite = TRUE)

  list(adsl_like = adsl_like, adtte_like = adtte_like)
}
