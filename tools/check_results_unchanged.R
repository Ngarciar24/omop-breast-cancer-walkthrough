# ---------------------------------------------------------------------------
# check_results_unchanged.R
#
#   Rscript tools/check_results_unchanged.R
#
# Run after run_all.R. Compares every table in results/ and codelists/ with
# the version committed at HEAD. The provenance columns are left out, because
# they name the commit of each run. Any other difference fails, so the numbers
# in the repository cannot drift away from the code that makes them.
#
# Not compared
#   figures (PNG), because their captions name the commit
#   results/provenance.yaml, because it names the commit and run date
# ---------------------------------------------------------------------------

provenance_columns <- c("git_commit", "vocabulary_version")

files <- sort(c(
  list.files("results", pattern = "\\.(csv|parquet)$", recursive = TRUE, full.names = TRUE),
  list.files("codelists", pattern = "\\.csv$", full.names = TRUE)
))

read_table <- function(path) {
  data <- if (grepl("\\.parquet$", path)) {
    as.data.frame(arrow::read_parquet(path))
  } else {
    read.csv(path, colClasses = "character")
  }
  data[, setdiff(names(data), provenance_columns), drop = FALSE]
}

committed_copy <- function(path) {
  in_head <- system2("git", c("cat-file", "-e", shQuote(paste0("HEAD:", path))),
                     stdout = FALSE, stderr = FALSE) == 0
  if (!in_head) return(NULL)
  copy <- tempfile(fileext = paste0(".", tools::file_ext(path)))
  system2("git", c("show", shQuote(paste0("HEAD:", path))), stdout = copy)
  copy
}

problems <- character(0)
for (path in files) {
  copy <- committed_copy(path)
  if (is.null(copy)) {
    problems <- c(problems, paste("not committed:", path))
    next
  }
  same <- isTRUE(all.equal(read_table(path), read_table(copy), check.attributes = FALSE))
  if (!same) problems <- c(problems, paste("differs from HEAD:", path))
}

# A file in HEAD that the run no longer writes is also a problem.
tracked <- system2("git", c("ls-files", "results", "codelists"), stdout = TRUE)
tracked <- tracked[grepl("\\.(csv|parquet)$", tracked)]
gone <- setdiff(tracked, files)
problems <- c(problems, if (length(gone) > 0) paste("committed but not rebuilt:", gone))

message("Compared ", length(files), " files with HEAD.")
if (length(problems) > 0) {
  message(paste(problems, collapse = "\n"))
  quit(status = 1)
}
message("All results and codelists match the committed versions.")
