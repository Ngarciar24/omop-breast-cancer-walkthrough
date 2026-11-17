-- What differs between duplicate drug records?
--
-- The duplicate_records check groups drug_exposure by person, drug, start date
-- and type concept. This query looks inside the groups with more than one row.
-- For each group it counts the distinct values of other columns. If a column
-- has more than one value in a group, the rows differ in that column and may
-- be separate records. If no column differs, the rows are copies.
--
-- Step 1 (dup_groups) builds one row per duplicate group.
-- The final SELECT counts how many groups differ in each column.

WITH dup_groups AS (
  SELECT person_id,
         drug_concept_id,
         drug_exposure_start_date,
         drug_type_concept_id,
         COUNT(*)                                     AS n_rows,
         COUNT(DISTINCT visit_occurrence_id)          AS n_visits,
         COUNT(DISTINCT drug_exposure_end_date)       AS n_end_dates,
         COUNT(DISTINCT drug_exposure_start_datetime) AS n_start_datetimes,
         COUNT(DISTINCT quantity)                     AS n_quantities,
         COUNT(DISTINCT drug_source_value)            AS n_source_values
  FROM drug_exposure
  GROUP BY person_id, drug_concept_id, drug_exposure_start_date, drug_type_concept_id
  -- HAVING filters groups after GROUP BY, the way WHERE filters rows before it.
  HAVING COUNT(*) > 1
)

SELECT COUNT(*)                                             AS n_duplicate_groups,
       MAX(n_rows)                                          AS max_rows_in_one_group,
       SUM(CASE WHEN n_visits > 1 THEN 1 ELSE 0 END)          AS groups_differing_in_visit,
       SUM(CASE WHEN n_end_dates > 1 THEN 1 ELSE 0 END)       AS groups_differing_in_end_date,
       SUM(CASE WHEN n_start_datetimes > 1 THEN 1 ELSE 0 END) AS groups_differing_in_start_time,
       SUM(CASE WHEN n_quantities > 1 THEN 1 ELSE 0 END)      AS groups_differing_in_quantity,
       SUM(CASE WHEN n_source_values > 1 THEN 1 ELSE 0 END)   AS groups_differing_in_source_value
FROM dup_groups
