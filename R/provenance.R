# ---------------------------------------------------------------------------
# provenance.R
#
# Every output records which code and which vocabulary produced it.
#
# run_all.R builds the provenance once, at the start of a run, and stores it
# with options(). write_result() then adds two columns, git_commit and
# vocabulary_version, to every table it writes to results/. The full record
# goes to results/provenance.yaml.
#
# The commit is the one checked out during the run. It ends in "-dirty" when
# code had uncommitted changes. results/ and codelists/ are left out of that
# check, because the run itself rewrites them.
# ---------------------------------------------------------------------------

provenance_columns <- c("git_commit", "vocabulary_version")

git_commit <- function() {
  commit <- tryCatch(
    system2("git", c("rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE),
    error = function(e) character(0), warning = function(w) character(0)
  )
  if (length(commit) == 0) return("unknown")

  # system2() goes through the shell, so the pathspecs need quoting. Without
  # it the parentheses are a shell error and the check would wrongly say clean.
  changes <- system2("git", c("status", "--porcelain", "--", ".",
                              shQuote(":(exclude)results"),
                              shQuote(":(exclude)codelists")),
                     stdout = TRUE)
  if (length(changes) > 0) paste0(commit, "-dirty") else commit
}

build_provenance <- function(cdm) {
  meta <- cdm_metadata(cdm)
  packages <- c("CDMConnector", "duckdb", "CodelistGenerator", "CohortConstructor",
                "PatientProfiles", "CohortSurvival", "survival", "cards", "cardx")
  list(
    git_commit = git_commit(),
    vocabulary_version = meta$vocabulary_version_vocabulary,
    cdm_version = meta$cdm_version,
    dataset = meta$dataset,
    source_description = meta$source_description,
    r_version = paste(R.version$major, R.version$minor, sep = "."),
    packages = as.list(vapply(packages, function(p) as.character(packageVersion(p)),
                              character(1))),
    run_date = format(Sys.Date())
  )
}

current_provenance <- function() {
  provenance <- getOption("omop.provenance")
  if (is.null(provenance)) stop("No provenance set. Run the pipeline through run_all.R.")
  provenance
}

# Write a results table as CSV or Parquet, chosen by the file extension, with
# the two provenance columns added.
write_result <- function(data, path) {
  provenance <- current_provenance()
  data <- as.data.frame(data)
  # rep() so that a table with no rows still gets the two columns.
  data$git_commit <- rep(provenance$git_commit, nrow(data))
  data$vocabulary_version <- rep(provenance$vocabulary_version, nrow(data))

  if (grepl("\\.parquet$", path)) {
    arrow::write_parquet(data, path)
  } else {
    write.csv(data, path, row.names = FALSE)
  }
}

# Drop the provenance columns, for code that reads results back.
without_provenance <- function(data) {
  data[, setdiff(names(data), provenance_columns), drop = FALSE]
}

# One line for figure captions.
provenance_caption <- function() {
  provenance <- current_provenance()
  paste0("Commit ", substr(provenance$git_commit, 1, 12),
         if (grepl("-dirty$", provenance$git_commit)) "-dirty" else "",
         " | Vocabulary ", provenance$vocabulary_version,
         " | Synthetic data (Synthea)")
}
