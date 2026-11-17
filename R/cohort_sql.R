# ---------------------------------------------------------------------------
# cohort_sql.R
#
# Run the hand-written cohort SQL in sql/cohort/ in the right order. Used by
# R/30_cohort.R on the real data and by the tests on hand-made data.
# ---------------------------------------------------------------------------

run_cohort_sql <- function(con, codelist_ids, sql_dir = "sql/cohort") {
  DBI::dbWriteTable(con, "breast_cancer_codelist",
                    data.frame(concept_id = codelist_ids),
                    temporary = TRUE, overwrite = TRUE)

  candidates <- run_sql_file(con, file.path(sql_dir, "candidates.sql"))
  DBI::dbWriteTable(con, "bc_candidates", candidates,
                    temporary = TRUE, overwrite = TRUE)

  list(
    candidates = candidates,
    attrition = run_sql_file(con, file.path(sql_dir, "attrition.sql")),
    cohort = run_sql_file(con, file.path(sql_dir, "cohort.sql"))
  )
}
