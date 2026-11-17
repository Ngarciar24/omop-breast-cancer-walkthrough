-- Check: death before birth
--
-- Rule. A death date cannot be earlier than the date of birth.
--
-- person stores birth as separate year, month and day columns. Month and day
-- may be missing, so we treat a missing value as 1 (the earliest possible).
-- That way a death is only flagged when it is before birth for certain.
-- The join key is death.person_id = person.person_id.

SELECT 'death_before_birth' AS check_name,
       'Death date is earlier than the date of birth' AS rule,
       'death' AS table_name,
       COUNT(*) AS rows_checked,
       -- COALESCE turns the NULL that SUM gives on an empty table into 0.
       COALESCE(SUM(
         CASE
           WHEN d.death_date < MAKE_DATE(p.year_of_birth,
                                         COALESCE(p.month_of_birth, 1),
                                         COALESCE(p.day_of_birth, 1))
           THEN 1
           ELSE 0
         END
       ), 0) AS rows_failing
FROM death d
INNER JOIN person p
  ON p.person_id = d.person_id
