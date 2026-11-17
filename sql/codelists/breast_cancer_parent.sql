-- Breast cancer parent concept
--
-- Finds the parent concept of the breast cancer condition set by its name.
-- No concept_id is typed anywhere. The ID comes out of this query.
--
-- The filters ask for a SNOMED concept that is standard ('S') and in the
-- Condition domain. invalid_reason IS NULL drops concepts that were retired.
-- R stops if this does not return exactly one row.

SELECT concept_id,
       concept_name,
       vocabulary_id,
       domain_id,
       concept_class_id,
       concept_code
FROM concept
WHERE concept_name = 'Malignant tumor of breast'
  AND vocabulary_id = 'SNOMED'
  AND domain_id = 'Condition'
  AND standard_concept = 'S'
  AND invalid_reason IS NULL
