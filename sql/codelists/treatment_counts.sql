-- Treatment classes and ingredients among people with breast cancer
--
-- Step 1 (bc_persons) lists everyone with at least one record from the breast
-- cancer set, at any time.
-- Step 2 (treated) keeps their drug records that fall in the treatment set.
-- The join key to the codelist is drug_exposure.drug_concept_id = concept_id.
-- The final SELECT counts people per class and per ingredient. It counts each
-- level separately, because one person can take several ingredients of a class.
--
-- A drug concept can sit under two classes. A co-pack of letrozole and
-- ribociclib is one example. Its records count towards both classes.

WITH bc_persons AS (
  SELECT DISTINCT co.person_id
  FROM condition_occurrence co
  INNER JOIN codelist_concepts cc
    ON cc.concept_id = co.condition_concept_id
   AND cc.codelist_name = 'breast_cancer'
),

treated AS (
  SELECT de.person_id,
         cc.class,
         cc.ancestor_concept_id
  FROM drug_exposure de
  INNER JOIN bc_persons bp
    ON bp.person_id = de.person_id
  INNER JOIN codelist_concepts cc
    ON cc.concept_id = de.drug_concept_id
   AND cc.codelist_name = 'treatment'
)

SELECT 'class' AS level,
       class,
       NULL AS ingredient_concept_id,
       NULL AS ingredient_name,
       COUNT(*) AS n_records,
       COUNT(DISTINCT person_id) AS n_persons
FROM treated
GROUP BY class

UNION ALL
SELECT 'ingredient',
       t.class,
       t.ancestor_concept_id,
       c.concept_name,
       COUNT(*),
       COUNT(DISTINCT t.person_id)
FROM treated t
INNER JOIN concept c
  ON c.concept_id = t.ancestor_concept_id
GROUP BY t.class, t.ancestor_concept_id, c.concept_name

ORDER BY level, class, ingredient_name
