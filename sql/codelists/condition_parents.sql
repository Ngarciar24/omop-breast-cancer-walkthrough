-- Comorbidity parent concepts by name
--
-- Looks up each parent name from codelists/comorbidity_input.csv. R loads that
-- file into a temporary table called comorbidity_input.
--
-- A flag may have more than one parent. In this SNOMED version "Coronary
-- arteriosclerosis" does not sit below "Ischemic heart disease", so the
-- ischaemic heart disease flag lists both.
--
-- Same pattern as ingredients.sql. The LEFT JOIN keeps every input row, so a
-- name with no standard SNOMED condition comes back with concept_id NULL and
-- is reported.

SELECT i.flag,
       i.parent_name,
       c.concept_id,
       c.concept_name,
       c.vocabulary_id,
       c.domain_id,
       c.concept_class_id,
       c.concept_code
FROM comorbidity_input i
LEFT JOIN concept c
  ON c.concept_name = i.parent_name
 AND c.vocabulary_id = 'SNOMED'
 AND c.domain_id = 'Condition'
 AND c.standard_concept = 'S'
 AND c.invalid_reason IS NULL
ORDER BY i.flag, i.parent_name
