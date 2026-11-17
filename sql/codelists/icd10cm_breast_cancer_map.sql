-- ICD-10-CM codes and the breast cancer set
--
-- This comes from the vocabulary alone. The data hold no ICD-10-CM codes.
--
-- It lists two groups of ICD-10-CM codes.
--   Codes whose "Maps to" target is in the breast cancer set.
--   Codes in the C50 category (malignant neoplasm of breast), whatever
--   their target. This shows whether the set misses any of them.
-- in_breast_cancer_set is 1 when the target is in the set, otherwise 0.
--
-- The join keys are
--   concept_relationship.concept_id_1 = ICD-10-CM concept
--   concept_relationship.concept_id_2 = standard target concept

WITH breast_cancer_set AS (
  SELECT DISTINCT concept_id
  FROM codelist_concepts
  WHERE codelist_name = 'breast_cancer'
),

icd_maps AS (
  SELECT src.concept_code AS icd10cm_code,
         src.concept_name AS icd10cm_name,
         tgt.concept_id   AS standard_concept_id,
         tgt.concept_name AS standard_concept_name,
         tgt.vocabulary_id AS standard_vocabulary_id
  FROM concept src
  LEFT JOIN concept_relationship cr
    ON cr.concept_id_1 = src.concept_id
   AND cr.relationship_id = 'Maps to'
   AND cr.invalid_reason IS NULL
  LEFT JOIN concept tgt
    ON tgt.concept_id = cr.concept_id_2
  WHERE src.vocabulary_id = 'ICD10CM'
)

SELECT m.*,
       CASE WHEN bcs.concept_id IS NULL THEN 0 ELSE 1 END AS in_breast_cancer_set
FROM icd_maps m
LEFT JOIN breast_cancer_set bcs
  ON bcs.concept_id = m.standard_concept_id
WHERE bcs.concept_id IS NOT NULL
   OR m.icd10cm_code LIKE 'C50%'
ORDER BY m.icd10cm_code, m.standard_concept_id
