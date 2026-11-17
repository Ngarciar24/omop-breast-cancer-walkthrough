# ---------------------------------------------------------------------------
# Known-answer tests for the codelist SQL
#
# A tiny in-memory vocabulary with a planted hierarchy.
#
#   1 ancestor (standard, Condition)
#   2 child of 1 (standard, Condition)            must be found
#   3 grandchild of 1 (standard, Condition)       must be found
#   4 unrelated (standard, Condition)             must not be found
#   5 child of 1 but not standard                 must not be found
#   6 child of 1 but in the Regimen domain        must not be found
#   7 child of 1 but retired (invalid_reason D)   must not be found
# ---------------------------------------------------------------------------

build_toy_vocabulary <- function() {
  con <- DBI::dbConnect(duckdb::duckdb())

  DBI::dbWriteTable(con, "concept", data.frame(
    concept_id       = 1:8,
    concept_name     = c("Ancestor", "Child", "Grandchild", "Unrelated",
                         "Non-standard child", "Regimen child", "Retired child",
                         "Tamoxifen"),
    domain_id        = c(rep("Condition", 5), "Regimen", "Condition", "Drug"),
    vocabulary_id    = c(rep("SNOMED", 5), "HemOnc", "SNOMED", "RxNorm"),
    concept_class_id = c(rep("Clinical Finding", 5), "Regimen", "Clinical Finding",
                         "Ingredient"),
    concept_code     = as.character(101:108),
    standard_concept = c("S", "S", "S", "S", NA, "S", "S", "S"),
    invalid_reason   = c(NA, NA, NA, NA, NA, NA, "D", NA)
  ))

  DBI::dbWriteTable(con, "concept_ancestor", data.frame(
    ancestor_concept_id      = c(1L, 1L, 1L, 1L, 1L, 1L, 4L),
    descendant_concept_id    = c(1L, 2L, 3L, 5L, 6L, 7L, 4L),
    min_levels_of_separation = c(0L, 1L, 2L, 1L, 1L, 1L, 0L)
  ))

  con
}

test_that("descendants.sql returns exactly the standard descendants in the ancestor's domain", {
  con <- build_toy_vocabulary()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  DBI::dbWriteTable(con, "codelist_ancestors", data.frame(
    codelist_name = "toy", class = NA_character_, ancestor_concept_id = 1L
  ))
  result <- run_sql_file(con, repo_path("sql", "codelists", "descendants.sql"))

  expect_setequal(result$concept_id, c(1, 2, 3))
})

test_that("ingredients.sql ignores case and reports names it cannot find", {
  con <- build_toy_vocabulary()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  DBI::dbWriteTable(con, "treatment_classes_input", data.frame(
    class = c("endocrine_therapy", "endocrine_therapy"),
    ingredient_name = c("tamoxifen", "tamoxifn")
  ))
  result <- run_sql_file(con, repo_path("sql", "codelists", "ingredients.sql"))

  expect_equal(nrow(result), 2)
  expect_equal(result$concept_id[result$ingredient_name == "tamoxifen"], 8)
  expect_true(is.na(result$concept_id[result$ingredient_name == "tamoxifn"]))
})

# ---------------------------------------------------------------------------
# Checks on the saved codelists against the real vocabulary. These need
# run_all.R to have written codelists/ first.
# ---------------------------------------------------------------------------

read_codelist <- function(file) read.csv(repo_path("codelists", file))

skip_without_codelists <- function() {
  skip_if_not(file.exists(repo_path("codelists", "breast_cancer.csv")),
              "codelists not written yet")
}

test_that("every codelist concept exists, is standard and is in the right domain", {
  skip_without_codelists()
  cdm <- open_cdm()
  on.exit(close_cdm(cdm))
  con <- CDMConnector::cdmCon(cdm)

  saved <- rbind(
    data.frame(concept_id = read_codelist("breast_cancer.csv")$concept_id,
               expected_domain = "Condition"),
    data.frame(concept_id = unique(read_codelist("treatment.csv")$concept_id),
               expected_domain = "Drug")
  )
  DBI::dbWriteTable(con, "test_saved_concepts", saved, temporary = TRUE, overwrite = TRUE)

  # Every saved row must find a valid standard concept in its expected domain.
  n_valid <- DBI::dbGetQuery(con, "
    SELECT COUNT(*) AS n
    FROM test_saved_concepts s
    INNER JOIN concept c
      ON c.concept_id = s.concept_id
     AND c.domain_id = s.expected_domain
     AND c.standard_concept = 'S'
     AND c.invalid_reason IS NULL
  ")$n
  expect_equal(n_valid, nrow(saved))
})

test_that("no ingredient sits in two classes", {
  skip_without_codelists()
  definition <- read_codelist("treatment_definition.csv")
  expect_equal(anyDuplicated(definition$concept_id[!is.na(definition$concept_id)]), 0)
  expect_equal(anyDuplicated(definition$ingredient_name), 0)
})

test_that("every codelist row carries the vocabulary version of the CDM", {
  skip_without_codelists()
  cdm <- open_cdm()
  on.exit(close_cdm(cdm))
  version <- cdm_metadata(cdm)$vocabulary_version_vocabulary

  for (file in c("breast_cancer_definition.csv", "breast_cancer.csv",
                 "treatment_definition.csv", "treatment.csv",
                 "breast_cancer_icd10cm_map.csv")) {
    expect_true(all(read_codelist(file)$vocabulary_version == version), info = file)
  }
})

test_that("the SQL breast cancer set equals CodelistGenerator::getDescendants()", {
  skip_without_codelists()
  cdm <- open_cdm()
  on.exit(close_cdm(cdm))

  parent_id <- read_codelist("breast_cancer_definition.csv")$concept_id
  from_package <- CodelistGenerator::getDescendants(cdm, conceptId = parent_id)

  expect_setequal(read_codelist("breast_cancer.csv")$concept_id,
                  from_package$concept_id)
})
