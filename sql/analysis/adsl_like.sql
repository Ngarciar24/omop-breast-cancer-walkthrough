-- adsl_like: one row per person in the cohort
--
-- Follows ADaM naming as a convention only. It is not a CDISC-conformant ADSL.
--
-- Inputs
--   breast_cancer_sql     the M3 cohort (subject_id, start and end dates)
--   comorbidity_codelist  temporary table from codelists/comorbidity.csv
--   treatment_codelist    temporary table from codelists/treatment.csv
-- Each CTE adds one group of variables. The final SELECT joins them on
-- person_id and names the columns.

WITH cohort AS (
  SELECT subject_id        AS person_id,
         cohort_start_date AS index_date,
         cohort_end_date   AS obs_end_date
  FROM breast_cancer_sql
),

obs AS (
  -- The observation period that contains the index date. Its start gives
  -- PRIOROBS. Join on person_id with the index date inside the period.
  SELECT c.person_id,
         op.observation_period_start_date AS obs_start_date
  FROM cohort c
  INNER JOIN observation_period op
    ON op.person_id = c.person_id
   AND c.index_date BETWEEN op.observation_period_start_date
                        AND op.observation_period_end_date
),

demographics AS (
  -- Birth date and sex from person, same rules as sql/cohort/candidates.sql.
  SELECT c.person_id,
         MAKE_DATE(p.year_of_birth,
                   COALESCE(p.month_of_birth, 1),
                   COALESCE(p.day_of_birth, 1)) AS birth_date,
         CASE g.concept_name
           WHEN 'FEMALE' THEN 'F'
           WHEN 'MALE'   THEN 'M'
           ELSE 'U'
         END AS sex
  FROM cohort c
  INNER JOIN person p
    ON p.person_id = c.person_id
  LEFT JOIN concept g
    ON g.concept_id = p.gender_concept_id
),

age AS (
  -- Age in completed years at index. Explained in candidates.sql step 5.
  SELECT c.person_id,
         EXTRACT(YEAR FROM c.index_date) - EXTRACT(YEAR FROM d.birth_date)
           - CASE
               WHEN EXTRACT(MONTH FROM c.index_date) * 100 + EXTRACT(DAY FROM c.index_date)
                  < EXTRACT(MONTH FROM d.birth_date) * 100 + EXTRACT(DAY FROM d.birth_date)
               THEN 1
               ELSE 0
             END AS age
  FROM cohort c
  INNER JOIN demographics d
    ON d.person_id = c.person_id
),

death_in_followup AS (
  -- A death counts only between index and the end of observation. A death
  -- after the end of observation is outside follow-up and is not seen.
  SELECT c.person_id,
         d.death_date
  FROM cohort c
  INNER JOIN death d
    ON d.person_id = c.person_id
   AND d.death_date BETWEEN c.index_date AND c.obs_end_date
),

comorbidity AS (
  -- One row per person with any comorbidity record before the index date, in
  -- all available history. MAX over the 0/1 values gives 1 if any record of
  -- that flag exists. People with no record at all are filled in as 'N' below.
  SELECT c.person_id,
         MAX(CASE WHEN cc.class = 'ischaemic_heart_disease' THEN 1 ELSE 0 END) AS ihd,
         MAX(CASE WHEN cc.class = 'cerebrovascular_disease' THEN 1 ELSE 0 END) AS cvd,
         MAX(CASE WHEN cc.class = 'atrial_fibrillation'     THEN 1 ELSE 0 END) AS af
  FROM cohort c
  INNER JOIN condition_occurrence co
    ON co.person_id = c.person_id
   AND co.condition_start_date < c.index_date
  INNER JOIN comorbidity_codelist cc
    ON cc.concept_id = co.condition_concept_id
  GROUP BY c.person_id
),

early_treatment AS (
  -- Treatment records from the index date to 90 days after it.
  SELECT DISTINCT
         c.person_id,
         de.drug_exposure_start_date AS start_date,
         tc.class
  FROM cohort c
  INNER JOIN drug_exposure de
    ON de.person_id = c.person_id
   AND de.drug_exposure_start_date BETWEEN c.index_date AND c.index_date + 90
  INNER JOIN treatment_codelist tc
    ON tc.concept_id = de.drug_concept_id
),

first_day AS (
  -- Keep only the classes started on each person's first treatment day.
  -- The subquery finds that day with MIN.
  SELECT et.*
  FROM early_treatment et
  WHERE et.start_date = (
    SELECT MIN(e2.start_date)
    FROM early_treatment e2
    WHERE e2.person_id = et.person_id
  )
),

first_treatment AS (
  -- One row per treated person. STRING_AGG lists every class started that
  -- day. The priority number picks one class when several start together.
  -- Lower wins: anti-HER2 1, CDK4/6 inhibitor 2, chemotherapy 3, endocrine 4.
  SELECT person_id,
         MIN(start_date) AS first_date,
         STRING_AGG(class, ' + ' ORDER BY class) AS all_classes,
         MIN(CASE class
               WHEN 'anti_her2'         THEN 1
               WHEN 'cdk46_inhibitor'   THEN 2
               WHEN 'chemotherapy'      THEN 3
               WHEN 'endocrine_therapy' THEN 4
             END) AS priority
  FROM first_day
  GROUP BY person_id
)

SELECT CAST(c.person_id AS VARCHAR)                        AS USUBJID,
       d.sex                                               AS SEX,
       a.age                                               AS AGE,
       'YEARS'                                             AS AGEU,
       CASE
         WHEN a.age < 50 THEN '<50'
         WHEN a.age < 65 THEN '50-64'
         WHEN a.age < 75 THEN '65-74'
         ELSE '>=75'
       END                                                 AS AGEGR1,
       c.index_date                                        AS INDEXDT,
       o.obs_start_date                                    AS OBSSTDT,
       c.obs_end_date                                      AS OBSENDDT,
       c.index_date - o.obs_start_date                     AS PRIOROBS,
       CASE WHEN dt.person_id IS NULL THEN 'N' ELSE 'Y' END AS DTHFL,
       dt.death_date                                       AS DTHDT,
       CASE WHEN cm.ihd = 1 THEN 'Y' ELSE 'N' END          AS CMIHDFL,
       CASE WHEN cm.cvd = 1 THEN 'Y' ELSE 'N' END          AS CMCVDFL,
       CASE WHEN cm.af  = 1 THEN 'Y' ELSE 'N' END          AS CMAFFL,
       CASE WHEN ft.person_id IS NULL THEN 'N' ELSE 'Y' END AS FTRTFL,
       ft.first_date                                       AS FTRTDT,
       ft.all_classes                                      AS FTRTALL,
       CASE ft.priority
         WHEN 1 THEN 'Anti-HER2 based'
         WHEN 2 THEN 'CDK4/6 inhibitor based'
         WHEN 3 THEN 'Chemotherapy'
         WHEN 4 THEN 'Endocrine only'
         ELSE 'None within 90 days'
       END                                                 AS FTRTCLS
FROM cohort c
INNER JOIN obs o           ON o.person_id = c.person_id
INNER JOIN demographics d  ON d.person_id = c.person_id
INNER JOIN age a           ON a.person_id = c.person_id
-- LEFT JOINs, because most people have no death, comorbidity or early
-- treatment row, and they must stay in the dataset.
LEFT JOIN death_in_followup dt ON dt.person_id = c.person_id
LEFT JOIN comorbidity cm       ON cm.person_id = c.person_id
LEFT JOIN first_treatment ft   ON ft.person_id = c.person_id
ORDER BY c.person_id
