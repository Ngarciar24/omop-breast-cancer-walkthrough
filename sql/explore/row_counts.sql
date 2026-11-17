-- Row counts per table
--
-- One row per table with the number of records and the number of distinct
-- people who have at least one record there. No joins. Each SELECT reads one
-- table and UNION ALL stacks the results.

SELECT 'person' AS table_name,
       COUNT(*) AS n_rows,
       COUNT(DISTINCT person_id) AS n_persons
FROM person

UNION ALL
SELECT 'observation_period', COUNT(*), COUNT(DISTINCT person_id)
FROM observation_period

UNION ALL
SELECT 'death', COUNT(*), COUNT(DISTINCT person_id)
FROM death

UNION ALL
SELECT 'visit_occurrence', COUNT(*), COUNT(DISTINCT person_id)
FROM visit_occurrence

UNION ALL
SELECT 'condition_occurrence', COUNT(*), COUNT(DISTINCT person_id)
FROM condition_occurrence

UNION ALL
SELECT 'drug_exposure', COUNT(*), COUNT(DISTINCT person_id)
FROM drug_exposure

UNION ALL
SELECT 'procedure_occurrence', COUNT(*), COUNT(DISTINCT person_id)
FROM procedure_occurrence

UNION ALL
SELECT 'measurement', COUNT(*), COUNT(DISTINCT person_id)
FROM measurement

UNION ALL
SELECT 'observation', COUNT(*), COUNT(DISTINCT person_id)
FROM observation

UNION ALL
SELECT 'device_exposure', COUNT(*), COUNT(DISTINCT person_id)
FROM device_exposure

-- UNION ALL does not promise an order, so sort the rows.
ORDER BY table_name
