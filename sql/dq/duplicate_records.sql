-- Check: duplicate records
--
-- Rule. Two rows with the same person, concept, start date and type concept
-- are counted as duplicates. In each such group the first row is kept as the
-- original and every further row counts as failing.
--
-- This rule can flag real records. A person may, for example, be given the
-- same drug twice on one day. The check reports the count and does not decide.

WITH condition_groups AS (
  SELECT person_id,
         condition_concept_id,
         condition_start_date,
         condition_type_concept_id,
         COUNT(*) AS n
  FROM condition_occurrence
  GROUP BY person_id, condition_concept_id, condition_start_date, condition_type_concept_id
),

drug_groups AS (
  SELECT person_id,
         drug_concept_id,
         drug_exposure_start_date,
         drug_type_concept_id,
         COUNT(*) AS n
  FROM drug_exposure
  GROUP BY person_id, drug_concept_id, drug_exposure_start_date, drug_type_concept_id
)

SELECT 'duplicate_records' AS check_name,
       'More than one row with the same person, concept, start date and type concept' AS rule,
       'condition_occurrence' AS table_name,
       COALESCE(SUM(n), 0) AS rows_checked,
       COALESCE(SUM(n - 1), 0) AS rows_failing
FROM condition_groups

UNION ALL
SELECT 'duplicate_records',
       'More than one row with the same person, concept, start date and type concept',
       'drug_exposure',
       COALESCE(SUM(n), 0),
       COALESCE(SUM(n - 1), 0)
FROM drug_groups

-- UNION ALL does not promise an order, so sort the rows.
ORDER BY table_name
