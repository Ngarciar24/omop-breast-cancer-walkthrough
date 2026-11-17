-- Share of records with concept_id = 0
--
-- concept_id = 0 means the source code did not map to a standard concept.
-- Concept sets in M2 are built from standard concepts, so these records can
-- never be found by them. One row per event table, no joins.
-- COALESCE turns the NULL that SUM gives on an empty table into 0.

SELECT 'visit_occurrence' AS table_name,
       'visit_concept_id' AS concept_column,
       COUNT(*) AS n_rows,
       COALESCE(SUM(CASE WHEN visit_concept_id = 0 THEN 1 ELSE 0 END), 0) AS n_concept_zero
FROM visit_occurrence

UNION ALL
SELECT 'condition_occurrence', 'condition_concept_id', COUNT(*),
       COALESCE(SUM(CASE WHEN condition_concept_id = 0 THEN 1 ELSE 0 END), 0)
FROM condition_occurrence

UNION ALL
SELECT 'drug_exposure', 'drug_concept_id', COUNT(*),
       COALESCE(SUM(CASE WHEN drug_concept_id = 0 THEN 1 ELSE 0 END), 0)
FROM drug_exposure

UNION ALL
SELECT 'procedure_occurrence', 'procedure_concept_id', COUNT(*),
       COALESCE(SUM(CASE WHEN procedure_concept_id = 0 THEN 1 ELSE 0 END), 0)
FROM procedure_occurrence

UNION ALL
SELECT 'measurement', 'measurement_concept_id', COUNT(*),
       COALESCE(SUM(CASE WHEN measurement_concept_id = 0 THEN 1 ELSE 0 END), 0)
FROM measurement

UNION ALL
SELECT 'observation', 'observation_concept_id', COUNT(*),
       COALESCE(SUM(CASE WHEN observation_concept_id = 0 THEN 1 ELSE 0 END), 0)
FROM observation

UNION ALL
SELECT 'device_exposure', 'device_concept_id', COUNT(*),
       COALESCE(SUM(CASE WHEN device_concept_id = 0 THEN 1 ELSE 0 END), 0)
FROM device_exposure

-- UNION ALL does not promise an order, so sort the rows.
ORDER BY table_name
