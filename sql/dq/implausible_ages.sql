-- Check: implausible ages
--
-- Rule. A person should be at least 0 and at most 110 years old during every
-- observation period. One row per observation period is checked.
--
-- Age here is the calendar year of the date minus year_of_birth. It can be one
-- year too high, but that is close enough for a plausibility check.
-- The join key is observation_period.person_id = person.person_id.

SELECT 'implausible_age' AS check_name,
       'Age at the start of an observation period is below 0, or age at its end is above 110' AS rule,
       'observation_period' AS table_name,
       COUNT(*) AS rows_checked,
       COALESCE(SUM(
         CASE
           WHEN EXTRACT(YEAR FROM op.observation_period_start_date) - p.year_of_birth < 0
             OR EXTRACT(YEAR FROM op.observation_period_end_date) - p.year_of_birth > 110
           THEN 1
           ELSE 0
         END
       ), 0) AS rows_failing
FROM observation_period op
INNER JOIN person p
  ON p.person_id = op.person_id
