-- Are ICD-10 and ICD-10-CM available?
--
-- Step 1 (wanted) is a small inline list of the two vocabulary names.
-- For each one the final SELECT reports whether the vocabulary table lists it,
-- its version, how many concepts it has and how many condition records in the
-- data arrived with a source code from it.
-- The LEFT JOIN keeps a vocabulary that is not loaded, with NULL version.

WITH wanted AS (
  SELECT * FROM (VALUES ('ICD10'), ('ICD10CM')) AS t(vocabulary_id)
)

SELECT w.vocabulary_id,
       CASE WHEN v.vocabulary_id IS NULL THEN 'no' ELSE 'yes' END AS loaded,
       v.vocabulary_version,
       (SELECT COUNT(*)
        FROM concept c
        WHERE c.vocabulary_id = w.vocabulary_id) AS n_concepts,
       (SELECT COUNT(*)
        FROM condition_occurrence co
        INNER JOIN concept s
          ON s.concept_id = co.condition_source_concept_id
        WHERE s.vocabulary_id = w.vocabulary_id) AS n_condition_records_in_data
FROM wanted w
LEFT JOIN vocabulary v
  ON v.vocabulary_id = w.vocabulary_id
ORDER BY w.vocabulary_id
