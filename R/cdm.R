# ---------------------------------------------------------------------------
# cdm.R
#
# Open the synthetic OMOP CDM and describe where it came from.
#
# The data are Synthea records in the OMOP Common Data Model, shipped by
# CDMConnector as a DuckDB database. They are synthetic. No clinical conclusion
# may be drawn from them.
# ---------------------------------------------------------------------------

library(DBI)
library(dplyr)

default_dataset <- "synthea-breast_cancer-10k"

# --- Open the CDM ---------------------------------------------------------
# CDMConnector::eunomiaDir() does the downloading. It keeps the zip and a built
# DuckDB file in EUNOMIA_DATA_FOLDER, then copies that DuckDB file to the path
# given in `databaseFile`. We keep that copy in data/cdm/ and reuse it, so the
# copy only happens on the first run. Cohort tables we create later are written
# into this working copy, never into the cached original.
open_cdm <- function(dataset = default_dataset) {
  data_folder <- Sys.getenv("EUNOMIA_DATA_FOLDER")
  if (data_folder == "") {
    stop("EUNOMIA_DATA_FOLDER is not set. Copy .Renviron.example to .Renviron.")
  }
  dir.create(data_folder, recursive = TRUE, showWarnings = FALSE)

  working_dir <- file.path(dirname(data_folder), "cdm")
  dir.create(working_dir, recursive = TRUE, showWarnings = FALSE)
  db_file <- file.path(working_dir, paste0(dataset, ".duckdb"))

  if (!file.exists(db_file)) {
    message("Creating working copy of ", dataset, " in ", db_file)
    CDMConnector::eunomiaDir(datasetName = dataset, databaseFile = db_file)
  }

  # shared_home = FALSE keeps DuckDB extensions in a temporary folder and
  # silences the notice DuckDB prints about it. We use no extensions.
  con <- dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = db_file)

  # cdmSchema holds the OMOP tables. writeSchema is where our own tables go.
  # DuckDB has one schema called "main", so both point there.
  CDMConnector::cdmFromCon(
    con,
    cdmSchema = "main",
    writeSchema = "main",
    cdmName = dataset
  )
}

close_cdm <- function(cdm) {
  CDMConnector::cdmDisconnect(cdm)
}

# --- Describe the source --------------------------------------------------
# cdm_source has one row describing the database. The vocabulary table lists
# every vocabulary loaded. By OMOP convention the row with
# vocabulary_id = 'None' carries the version of the whole vocabulary release.
cdm_metadata <- function(cdm) {
  source <- cdm$cdm_source |>
    select(
      "cdm_source_name",
      "source_description",
      "cdm_version",
      "vocabulary_version"
    ) |>
    collect()

  vocabulary_release <- cdm$vocabulary |>
    filter(.data$vocabulary_id == "None") |>
    pull("vocabulary_version")

  list(
    dataset = omopgenerics::cdmName(cdm),
    source_name = source$cdm_source_name,
    source_description = source$source_description,
    cdm_version = source$cdm_version,
    vocabulary_version_cdm_source = source$vocabulary_version,
    vocabulary_version_vocabulary = vocabulary_release
  )
}

print_cdm_metadata <- function(meta) {
  message("Dataset:             ", meta$dataset)
  message("Source name:         ", meta$source_name)
  message("Source description:  ", meta$source_description)
  message("CDM version:         ", meta$cdm_version)
  message("Vocabulary version:  ", meta$vocabulary_version_vocabulary,
          " (vocabulary table)")
  message("                     ", meta$vocabulary_version_cdm_source,
          " (cdm_source table)")
}
