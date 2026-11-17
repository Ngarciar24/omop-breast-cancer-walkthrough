-- Observation periods
--
-- An observation period is a span of time in which we expect to see every
-- recorded event for a person. Cohort entry in M3 needs 365 days of prior
-- observation, so the length of these periods matters.
--
-- Step 1 (periods) works out the length of each period in days.
-- Step 2 (per_person) counts how many periods each person has.
-- The final SELECT returns a single summary row.

WITH periods AS (
  SELECT person_id,
         observation_period_start_date,
         observation_period_end_date,
         -- In DuckDB, subtracting one date from another gives whole days.
         observation_period_end_date - observation_period_start_date AS length_days
  FROM observation_period
),

per_person AS (
  SELECT person_id,
         COUNT(*) AS n_periods
  FROM periods
  GROUP BY person_id
)

SELECT
  (SELECT COUNT(*) FROM per_person)                   AS n_persons,
  (SELECT COUNT(*) FROM periods)                      AS n_periods,
  (SELECT COUNT(*) FROM per_person WHERE n_periods > 1) AS n_persons_with_more_than_one_period,
  (SELECT COUNT(*) FROM periods WHERE length_days = 0) AS n_zero_length_periods,
  (SELECT MIN(length_days) FROM periods)              AS min_length_days,
  (SELECT MEDIAN(length_days) FROM periods)           AS median_length_days,
  (SELECT MAX(length_days) FROM periods)              AS max_length_days,
  (SELECT MIN(observation_period_start_date) FROM periods) AS earliest_start,
  (SELECT MAX(observation_period_end_date) FROM periods)   AS latest_end
