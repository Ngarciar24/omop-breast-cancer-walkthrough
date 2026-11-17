-- Comorbidity look-back: all history against 365 days
--
-- For each comorbidity flag, count the people in the cohort with a record
-- any time before index and within the 365 days before index. The second
-- window was the original plan. It finds far fewer people in this data,
-- where a chronic condition appears to be recorded once, around onset.

SELECT cc.class AS flag,
       COUNT(DISTINCT c.subject_id) AS n_persons_all_history,
       COUNT(DISTINCT CASE
               WHEN co.condition_start_date >= c.cohort_start_date - 365
               THEN c.subject_id
             END) AS n_persons_365_days
FROM breast_cancer_sql c
INNER JOIN condition_occurrence co
  ON co.person_id = c.subject_id
 AND co.condition_start_date < c.cohort_start_date
INNER JOIN comorbidity_codelist cc
  ON cc.concept_id = co.condition_concept_id
GROUP BY cc.class
ORDER BY cc.class
