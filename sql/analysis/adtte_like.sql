-- adtte_like: one row per person and time-to-event parameter
--
-- Follows ADaM naming as a convention only. It is not a CDISC-conformant ADTTE.
-- CNSR follows the ADaM convention. 1 means censored and 0 means event.
--
-- Inputs
--   adsl_like             the table R wrote from adsl_like.sql
--   treatment_codelist    temporary table from codelists/treatment.csv
--
-- OS, overall survival
--   Event        death within follow-up (DTHFL = 'Y')
--   Censored at  end of observation
-- TTFT, time to first treatment
--   Event        first start of any treatment class after index, not limited
--                to 90 days, on or before the censoring date
--   Censored at  death or end of observation, whichever comes first. Death
--                is really a competing risk. Censoring at death is a
--                simplification and the report says so.

WITH first_treatment_any AS (
  -- Earliest treatment start on or after the index date, within follow-up.
  SELECT a.USUBJID,
         MIN(de.drug_exposure_start_date) AS first_date
  FROM adsl_like a
  INNER JOIN drug_exposure de
    ON CAST(de.person_id AS VARCHAR) = a.USUBJID
   AND de.drug_exposure_start_date BETWEEN a.INDEXDT AND a.OBSENDDT
  INNER JOIN treatment_codelist tc
    ON tc.concept_id = de.drug_concept_id
  GROUP BY a.USUBJID
),

ttft AS (
  -- The censoring date is the earlier of death and end of observation.
  -- LEAST ignores NULL in DuckDB, so people without a death get OBSENDDT.
  SELECT a.USUBJID,
         a.INDEXDT,
         f.first_date,
         LEAST(a.DTHDT, a.OBSENDDT) AS censor_date,
         CASE WHEN a.DTHFL = 'Y' THEN 'DEATH' ELSE 'END OF OBSERVATION' END AS censor_reason
  FROM adsl_like a
  LEFT JOIN first_treatment_any f
    ON f.USUBJID = a.USUBJID
)

SELECT USUBJID,
       'OS'                                   AS PARAMCD,
       'Overall survival (days)'              AS PARAM,
       INDEXDT                                AS STARTDT,
       CASE WHEN DTHFL = 'Y' THEN DTHDT ELSE OBSENDDT END AS ADT,
       CASE WHEN DTHFL = 'Y' THEN DTHDT ELSE OBSENDDT END - INDEXDT AS AVAL,
       'DAYS'                                 AS AVALU,
       CASE WHEN DTHFL = 'Y' THEN 0 ELSE 1 END AS CNSR,
       CASE WHEN DTHFL = 'Y' THEN 'DEATH' END AS EVNTDESC,
       CASE WHEN DTHFL = 'Y' THEN NULL ELSE 'END OF OBSERVATION' END AS CNSDTDSC
FROM adsl_like

UNION ALL
SELECT USUBJID,
       'TTFT',
       'Time to first treatment (days)',
       INDEXDT,
       CASE WHEN first_date <= censor_date THEN first_date ELSE censor_date END,
       CASE WHEN first_date <= censor_date THEN first_date ELSE censor_date END - INDEXDT,
       'DAYS',
       -- first_date is NULL for people never treated. NULL <= date is not true,
       -- so they fall to the ELSE branch and are censored.
       CASE WHEN first_date <= censor_date THEN 0 ELSE 1 END,
       CASE WHEN first_date <= censor_date THEN 'FIRST TREATMENT' END,
       CASE WHEN first_date <= censor_date THEN NULL ELSE censor_reason END
FROM ttft

ORDER BY USUBJID, PARAMCD
