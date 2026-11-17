-- Check: events outside observation
--
-- Rule. An event should start inside one of the person's observation periods.
-- Outside those periods we do not expect to see everything that happens to
-- the person, so events there break that assumption.
--
-- Step 1 (events) stacks the start date of every event table into one list
-- with three columns: table_name, person_id, event_date.
-- Step 2 (flagged) marks each event with 1 if no observation period of the
-- same person contains its date, otherwise 0.
-- The final SELECT counts checked and failing rows per table.

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
           -- NOT EXISTS is true when the subquery finds no matching row.
           -- The subquery joins on person_id and asks whether the event date
           -- falls between the start and end of any period of that person.
           WHEN NOT EXISTS (
             SELECT 1
             FROM observation_period op
             WHERE op.person_id = e.person_id
               AND e.event_date BETWEEN op.observation_period_start_date
                                    AND op.observation_period_end_date
           ) THEN 1
           ELSE 0
         END AS failing
  FROM events e
)

SELECT 'events_outside_observation' AS check_name,
       'Event start date is not inside any observation period of the same person' AS rule,
       table_name,
       COUNT(*) AS rows_checked,
       SUM(failing) AS rows_failing
FROM flagged
GROUP BY table_name
ORDER BY table_name
