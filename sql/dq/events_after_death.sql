-- Check: events after death
--
-- Rule. No event should start after the person's death date. The rule is
-- strict, with no grace window. Some real databases record administrative
-- events a few days after death, so a grace window is a common choice.
--
-- Step 1 (events) is the same stacked list as in events_outside_observation.
-- Step 2 (flagged) does a LEFT JOIN to death on person_id. People without a
-- death record keep their events, with death_date NULL, and are never flagged.
-- In CDM 5.3 the death table has at most one row per person.

WITH events AS (
  SELECT 'visit_occurrence' AS table_name, person_id, visit_start_date AS event_date
  FROM visit_occurrence
  UNION ALL
  SELECT 'condition_occurrence', person_id, condition_start_date
  FROM condition_occurrence
  UNION ALL
  SELECT 'drug_exposure', person_id, drug_exposure_start_date
  FROM drug_exposure
  UNION ALL
  SELECT 'procedure_occurrence', person_id, procedure_date
  FROM procedure_occurrence
  UNION ALL
  SELECT 'measurement', person_id, measurement_date
  FROM measurement
  UNION ALL
  SELECT 'observation', person_id, observation_date
  FROM observation
  UNION ALL
  SELECT 'device_exposure', person_id, device_exposure_start_date
  FROM device_exposure
),

flagged AS (
  SELECT e.table_name,
         CASE
           WHEN d.death_date IS NOT NULL AND e.event_date > d.death_date THEN 1
           ELSE 0
         END AS failing
  FROM events e
  LEFT JOIN death d
    ON d.person_id = e.person_id
)

SELECT 'events_after_death' AS check_name,
       'Event start date is after the death date of the same person' AS rule,
       table_name,
       COUNT(*) AS rows_checked,
       SUM(failing) AS rows_failing
FROM flagged
GROUP BY table_name
ORDER BY table_name
