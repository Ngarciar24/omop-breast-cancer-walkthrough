-- The cohort, in the standard OMOP cohort table format
--
-- People from bc_candidates who pass every rule. The cohort starts on the
-- index date and ends at the end of the observation period that contains it.
-- cohort_definition_id is 1 because this table holds one cohort.

SELECT 1 AS cohort_definition_id,
       person_id AS subject_id,
       index_date AS cohort_start_date,
       observation_period_end_date AS cohort_end_date
FROM bc_candidates
WHERE has_prior_observation
  AND is_adult
ORDER BY subject_id
