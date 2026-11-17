-- Attrition: persons and records left after each step
--
-- Steps 1 and 2 count records, so they repeat the first two CTEs of
-- candidates.sql. Steps 3 to 5 read bc_candidates, the table R wrote from
-- candidates.sql, which already has one row per person.
-- Each rule is applied on top of the ones before it.

WITH bc_records AS (
  SELECT co.condition_occurrence_id, co.person_id, co.condition_start_date
  FROM condition_occurrence co
  INNER JOIN breast_cancer_codelist bc
    ON bc.concept_id = co.condition_concept_id
),

in_observation AS (
  SELECT r.condition_occurrence_id, r.person_id
  FROM bc_records r
  INNER JOIN observation_period op
    ON op.person_id = r.person_id
   AND r.condition_start_date BETWEEN op.observation_period_start_date
                                  AND op.observation_period_end_date
)

SELECT 1 AS step,
       'Any breast cancer record' AS description,
       COUNT(DISTINCT person_id) AS n_persons,
       COUNT(*) AS n_records
FROM bc_records

UNION ALL
SELECT 2, 'Record inside an observation period',
       COUNT(DISTINCT person_id), COUNT(*)
FROM in_observation

UNION ALL
SELECT 3, 'First record per person (index date)',
       COUNT(*), COUNT(*)
FROM bc_candidates

UNION ALL
SELECT 4, 'At least 365 days of prior observation',
       COUNT(*), COUNT(*)
FROM bc_candidates
WHERE has_prior_observation

UNION ALL
SELECT 5, 'Age 18 or older at index',
       COUNT(*), COUNT(*)
FROM bc_candidates
WHERE has_prior_observation
  AND is_adult

ORDER BY step
