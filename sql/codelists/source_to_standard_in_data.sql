-- Source-to-standard mapping in the data
--
-- Every clinical record keeps two concepts. The source concept is the code
-- the record arrived with. The standard concept is the one it was mapped to
-- through the "Maps to" relationship in concept_relationship.
--
-- Step 1 (records) takes the breast cancer condition records and the
-- treatment drug records, with both concepts.
-- The final SELECT groups them by source and standard vocabulary. It also
-- checks each record against concept_relationship. A record is confirmed when
-- a valid "Maps to" row links its source concept to its standard concept.
--
-- The join keys are
--   records.source_concept_id   = concept.concept_id (source side)
--   records.standard_concept_id = concept.concept_id (standard side)
--   concept_relationship.concept_id_1 = source, concept_id_2 = standard

WITH records AS (
  SELECT 'condition_occurrence' AS table_name,
         co.condition_source_concept_id AS source_concept_id,
         co.condition_concept_id AS standard_concept_id
  FROM condition_occurrence co
  WHERE co.condition_concept_id IN (
    SELECT concept_id FROM codelist_concepts WHERE codelist_name = 'breast_cancer'
  )

  UNION ALL
  SELECT 'drug_exposure',
         de.drug_source_concept_id,
         de.drug_concept_id
  FROM drug_exposure de
  WHERE de.drug_concept_id IN (
    SELECT concept_id FROM codelist_concepts WHERE codelist_name = 'treatment'
  )
)

SELECT r.table_name,
       src.vocabulary_id AS source_vocabulary_id,
       std.vocabulary_id AS standard_vocabulary_id,
       COUNT(*) AS n_records,
       COUNT(DISTINCT r.source_concept_id) AS n_source_concepts,
       COUNT(DISTINCT r.standard_concept_id) AS n_standard_concepts,
       SUM(CASE WHEN r.source_concept_id = r.standard_concept_id THEN 1 ELSE 0 END)
         AS n_source_equals_standard,
       SUM(CASE WHEN cr.concept_id_1 IS NOT NULL THEN 1 ELSE 0 END)
         AS n_confirmed_by_maps_to
FROM records r
-- LEFT JOIN, so records whose source concept is 0 or unknown are still counted.
LEFT JOIN concept src
  ON src.concept_id = r.source_concept_id
INNER JOIN concept std
  ON std.concept_id = r.standard_concept_id
LEFT JOIN concept_relationship cr
  ON cr.concept_id_1 = r.source_concept_id
 AND cr.concept_id_2 = r.standard_concept_id
 AND cr.relationship_id = 'Maps to'
 AND cr.invalid_reason IS NULL
GROUP BY r.table_name, src.vocabulary_id, std.vocabulary_id
ORDER BY r.table_name, n_records DESC
