-- Cohort candidates: one row per person with their first breast cancer record
--
-- R loads the concept IDs of codelists/breast_cancer.csv into a temporary
-- table called breast_cancer_codelist (one column, concept_id).
--
-- Each step below is a CTE (a named subquery). Each one reads the one before.
-- The result has one row per person and one true/false column per inclusion
-- rule. Nobody is removed for failing a rule here. That happens in cohort.sql,
-- so attrition.sql can count what each rule removes.

WITH bc_records AS (
  -- Step 1. Every condition record whose concept is in the breast cancer set.
  -- The join key is condition_occurrence.condition_concept_id = concept_id.
  SELECT co.condition_occurrence_id,
         co.person_id,
         co.condition_start_date
  FROM condition_occurrence co
  INNER JOIN breast_cancer_codelist bc
    ON bc.concept_id = co.condition_concept_id
),

in_observation AS (
  -- Step 2. Keep records that start inside an observation period of the same
  -- person, and attach that period. Records outside every period drop out,
  -- because the INNER JOIN finds no partner for them.
  SELECT r.condition_occurrence_id,
         r.person_id,
         r.condition_start_date,
         op.observation_period_start_date,
         op.observation_period_end_date
  FROM bc_records r
  INNER JOIN observation_period op
    ON op.person_id = r.person_id
   AND r.condition_start_date BETWEEN op.observation_period_start_date
                                  AND op.observation_period_end_date
),

ranked AS (
  -- Step 3a. Number each person's records from earliest to latest.
  -- ROW_NUMBER() is a window function. PARTITION BY restarts the numbering for
  -- every person. ORDER BY sets the order inside each person. Two records on
  -- the same day are ordered by their ID, so the choice is always the same.
  SELECT io.*,
         ROW_NUMBER() OVER (
           PARTITION BY io.person_id
           ORDER BY io.condition_start_date, io.condition_occurrence_id
         ) AS record_rank
  FROM in_observation io
),

first_record AS (
  -- Step 3b. Keep the earliest record. Its date is the index date.
  SELECT person_id,
         condition_start_date AS index_date,
         observation_period_start_date,
         observation_period_end_date
  FROM ranked
  WHERE record_rank = 1
),

with_person AS (
  -- Step 4. Add birth date and sex from person. The join key is person_id.
  -- A missing birth month or day is set to 1, as in the M1 checks.
  -- Sex is read from the label of gender_concept_id in concept. LEFT JOIN
  -- keeps the person even if the label is missing.
  SELECT f.*,
         MAKE_DATE(p.year_of_birth,
                   COALESCE(p.month_of_birth, 1),
                   COALESCE(p.day_of_birth, 1)) AS birth_date,
         g.concept_name AS sex
  FROM first_record f
  INNER JOIN person p
    ON p.person_id = f.person_id
  LEFT JOIN concept g
    ON g.concept_id = p.gender_concept_id
),

with_measures AS (
  -- Step 5. Days of prior observation and age in completed years at index.
  -- Age is the difference in calendar years, minus 1 if the birthday has not
  -- yet come round in the index year. Month * 100 + day turns a date into a
  -- number such as 315 for 15 March, which makes that comparison simple.
  SELECT wp.*,
         wp.index_date - wp.observation_period_start_date AS prior_observation_days,
         EXTRACT(YEAR FROM wp.index_date) - EXTRACT(YEAR FROM wp.birth_date)
           - CASE
               WHEN EXTRACT(MONTH FROM wp.index_date) * 100 + EXTRACT(DAY FROM wp.index_date)
                  < EXTRACT(MONTH FROM wp.birth_date) * 100 + EXTRACT(DAY FROM wp.birth_date)
               THEN 1
               ELSE 0
             END AS age_at_index
  FROM with_person wp
)

-- The inclusion rules, as true/false columns.
SELECT person_id,
       index_date,
       observation_period_start_date,
       observation_period_end_date,
       birth_date,
       sex,
       prior_observation_days,
       age_at_index,
       prior_observation_days >= 365 AS has_prior_observation,
       age_at_index >= 18 AS is_adult
FROM with_measures
ORDER BY person_id
