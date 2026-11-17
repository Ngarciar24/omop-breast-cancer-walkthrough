# ---------------------------------------------------------------------------
# sql.R
#
# Run the plain SQL files in sql/. Each file holds one SELECT statement. Table
# names in the files are unqualified, so they resolve to the default schema of
# the connection ("main" in DuckDB).
# ---------------------------------------------------------------------------

run_sql_file <- function(con, path) {
  sql <- paste(readLines(path, warn = FALSE), collapse = "\n")
  DBI::dbGetQuery(con, sql)
}

# Run every check in sql/dq/ and stack the results into one table. Every file
# returns the same five columns, and the share is added here.
run_dq_checks <- function(con, dq_dir = "sql/dq") {
  files <- sort(list.files(dq_dir, pattern = "\\.sql$", full.names = TRUE))
  results <- lapply(files, function(path) run_sql_file(con, path))
  checks <- do.call(rbind, results)

  checks$rows_checked <- as.numeric(checks$rows_checked)
  checks$rows_failing <- as.numeric(checks$rows_failing)
  checks$share_failing <- ifelse(
    checks$rows_checked > 0,
    checks$rows_failing / checks$rows_checked,
    NA_real_
  )
  checks
}
