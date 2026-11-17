# ---------------------------------------------------------------------------
# 20_codelists.R  (M2)
#
# Build the concept sets from the vocabulary tables and show how source codes
# map to standard concepts. Run from run_all.R, which has already opened `cdm`.
#
# No concept_id is typed in this file or in the SQL. The breast cancer parent
# and the comorbidity parents (used in M4) are found by name, the drug
# ingredients are found by the names in
# codelists/treatment_classes_input.csv, and everything else follows from
# concept_ancestor and concept_relationship.
# ---------------------------------------------------------------------------

source("R/sql.R")

con <- CDMConnector::cdmCon(cdm)
vocabulary_version <- cdm_metadata(cdm)$vocabulary_version_vocabulary

# Small inputs go into temporary tables, so the SQL files can join to them.
# Temporary tables vanish when the connection closes.
write_temp <- function(name, data) {
  DBI::dbWriteTable(con, name, data, temporary = TRUE, overwrite = TRUE)
}

# --- Breast cancer parent -------------------------------------------------
breast_cancer_parent <- run_sql_file(con, "sql/codelists/breast_cancer_parent.sql")
if (nrow(breast_cancer_parent) != 1) {
  stop("Expected one breast cancer parent concept, found ", nrow(breast_cancer_parent))
}

# --- Drug ingredients -----------------------------------------------------
treatment_input <- read.csv("codelists/treatment_classes_input.csv")
if (anyDuplicated(treatment_input$ingredient_name)) {
  stop("An ingredient is listed in more than one class")
}
write_temp("treatment_classes_input", treatment_input)
ingredients <- run_sql_file(con, "sql/codelists/ingredients.sql")

not_found <- ingredients$ingredient_name[is.na(ingredients$concept_id)]
if (length(not_found) > 0) {
  message("No standard RxNorm ingredient found for: ",
          paste(not_found, collapse = ", "))
}

# --- Comorbidity parents (used in M4) -------------------------------------
comorbidity_input <- read.csv("codelists/comorbidity_input.csv")
write_temp("comorbidity_input", comorbidity_input)
comorbidity_parents <- run_sql_file(con, "sql/codelists/condition_parents.sql")
if (anyNA(comorbidity_parents$concept_id)) {
  stop("No standard SNOMED condition found for: ",
       paste(comorbidity_parents$parent_name[is.na(comorbidity_parents$concept_id)],
             collapse = ", "))
}

# --- Descendants ----------------------------------------------------------
found <- ingredients[!is.na(ingredients$concept_id), ]
write_temp("codelist_ancestors", rbind(
  data.frame(codelist_name = "breast_cancer", class = NA_character_,
             ancestor_concept_id = breast_cancer_parent$concept_id),
  data.frame(codelist_name = "treatment", class = found$class,
             ancestor_concept_id = found$concept_id),
  data.frame(codelist_name = "comorbidity", class = comorbidity_parents$flag,
             ancestor_concept_id = comorbidity_parents$concept_id)
))
descendants <- run_sql_file(con, "sql/codelists/descendants.sql")

breast_cancer <- descendants[descendants$codelist_name == "breast_cancer", ]
treatment <- descendants[descendants$codelist_name == "treatment", ]
comorbidity <- descendants[descendants$codelist_name == "comorbidity", ]

# --- Flag breast cancer concepts for review -------------------------------
# The SNOMED hierarchy puts some concepts under "Malignant tumor of breast"
# that are not primary breast cancer. They stay in the set. The flag only
# marks them so a person can decide. The name patterns are the rule.
review_reason <- function(name) {
  reason <- rep("", length(name))
  secondary <- grepl("secondary malignant neoplasm|metastasis to breast|metastatic site",
                     name, ignore.case = TRUE)
  # (?<!carcino) skips carcinosarcoma, which is a carcinoma.
  non_carcinoma <- grepl("lymphoma|melanoma|(?<!carcino)sarcoma",
                         name, ignore.case = TRUE, perl = TRUE)
  no_breast <- !grepl("breast|mamma|nipple|areola", name, ignore.case = TRUE)
  reason[no_breast] <- "name does not mention the breast"
  reason[non_carcinoma] <- "lymphoma, melanoma or sarcoma"
  reason[secondary] <- "secondary tumour in the breast"
  reason
}
breast_cancer$review_reason <- review_reason(breast_cancer$concept_name)

# --- Counts in the data ---------------------------------------------------
codelist_columns <- c("codelist_name", "class", "ancestor_concept_id", "concept_id")
write_temp("codelist_concepts", rbind(breast_cancer[, codelist_columns],
                                      treatment[, codelist_columns]))

breast_cancer_counts <- run_sql_file(con, "sql/codelists/breast_cancer_counts.sql")
treatment_counts <- run_sql_file(con, "sql/codelists/treatment_counts.sql")

# Keep only the classes that occur among people with breast cancer.
classes_present <- treatment_counts$class[treatment_counts$level == "class" &
                                            treatment_counts$n_persons > 0]
classes_dropped <- setdiff(unique(treatment_input$class), classes_present)
if (length(classes_dropped) > 0) {
  message("Treatment classes with no one treated, dropped: ",
          paste(classes_dropped, collapse = ", "))
}
treatment <- treatment[treatment$class %in% classes_present, ]
write_temp("codelist_concepts", rbind(breast_cancer[, codelist_columns],
                                      treatment[, codelist_columns]))

# --- Mapping --------------------------------------------------------------
source_to_standard <- run_sql_file(con, "sql/codelists/source_to_standard_in_data.sql")
icd_vocabularies <- run_sql_file(con, "sql/codelists/icd_vocabularies.sql")
icd10cm_map <- run_sql_file(con, "sql/codelists/icd10cm_breast_cancer_map.sql")

# --- Save codelists -------------------------------------------------------
codelist_file <- function(data, columns) {
  out <- data[, columns]
  out$vocabulary_version <- vocabulary_version
  out
}

write.csv(
  codelist_file(cbind(breast_cancer_parent, include_descendants = TRUE),
                c("concept_id", "concept_name", "vocabulary_id", "domain_id",
                  "concept_class_id", "concept_code", "include_descendants")),
  "codelists/breast_cancer_definition.csv", row.names = FALSE
)
write.csv(
  codelist_file(breast_cancer,
                c("concept_id", "concept_name", "vocabulary_id", "domain_id",
                  "concept_class_id", "concept_code", "min_levels_of_separation",
                  "review_reason")),
  "codelists/breast_cancer.csv", row.names = FALSE
)
write.csv(
  codelist_file(cbind(ingredients, include_descendants = TRUE),
                c("class", "ingredient_name", "concept_id", "concept_name",
                  "vocabulary_id", "domain_id", "concept_class_id",
                  "concept_code", "include_descendants")),
  "codelists/treatment_definition.csv", row.names = FALSE
)
write.csv(
  codelist_file(treatment,
                c("class", "ancestor_concept_id", "concept_id", "concept_name",
                  "vocabulary_id", "domain_id", "concept_class_id",
                  "concept_code")),
  "codelists/treatment.csv", row.names = FALSE
)
write.csv(
  codelist_file(icd10cm_map, names(icd10cm_map)),
  "codelists/breast_cancer_icd10cm_map.csv", row.names = FALSE
)
write.csv(
  codelist_file(cbind(comorbidity_parents, include_descendants = TRUE),
                c("flag", "parent_name", "concept_id", "concept_name",
                  "vocabulary_id", "domain_id", "concept_class_id",
                  "concept_code", "include_descendants")),
  "codelists/comorbidity_definition.csv", row.names = FALSE
)
write.csv(
  codelist_file(comorbidity,
                c("class", "ancestor_concept_id", "concept_id", "concept_name",
                  "vocabulary_id", "domain_id", "concept_class_id",
                  "concept_code")),
  "codelists/comorbidity.csv", row.names = FALSE
)

# --- Save results ---------------------------------------------------------
codelist_summary <- rbind(
  data.frame(codelist_name = "breast_cancer", class = NA_character_,
             n_concepts = nrow(breast_cancer),
             n_flagged_for_review = sum(breast_cancer$review_reason != "")),
  do.call(rbind, lapply(split(treatment, treatment$class), function(x) {
    data.frame(codelist_name = "treatment", class = x$class[1],
               n_concepts = nrow(x), n_flagged_for_review = NA_integer_)
  })),
  do.call(rbind, lapply(split(comorbidity, comorbidity$class), function(x) {
    data.frame(codelist_name = "comorbidity", class = x$class[1],
               n_concepts = nrow(x), n_flagged_for_review = NA_integer_)
  }))
)
review_summary <- as.data.frame(table(
  review_reason = breast_cancer$review_reason[breast_cancer$review_reason != ""]
), responseName = "n_concepts")

write.csv(codelist_summary, "results/m2_codelist_summary.csv", row.names = FALSE)
write.csv(review_summary, "results/m2_breast_cancer_review.csv", row.names = FALSE)
write.csv(breast_cancer_counts, "results/m2_breast_cancer_counts.csv", row.names = FALSE)
write.csv(treatment_counts, "results/m2_treatment_counts.csv", row.names = FALSE)
write.csv(source_to_standard, "results/m2_source_to_standard.csv", row.names = FALSE)
write.csv(icd_vocabularies, "results/m2_icd_vocabularies.csv", row.names = FALSE)
write.csv(data.frame(ingredient_name = not_found), "results/m2_ingredients_not_found.csv",
          row.names = FALSE)

message("\nCodelists")
print(codelist_summary, row.names = FALSE)
message("\nBreast cancer concepts flagged for review")
print(review_summary, row.names = FALSE)
message("\nBreast cancer concepts used in the data")
print(breast_cancer_counts, row.names = FALSE)
message("\nTreatment among people with breast cancer")
print(treatment_counts, row.names = FALSE)
message("\nSource to standard in the data")
print(source_to_standard, row.names = FALSE)
message("\nICD vocabularies")
print(icd_vocabularies, row.names = FALSE)
message("\nICD-10-CM codes linked to the breast cancer set: ",
        sum(icd10cm_map$in_breast_cancer_set == 1),
        " rows, C50 rows outside the set: ",
        sum(icd10cm_map$in_breast_cancer_set == 0))
