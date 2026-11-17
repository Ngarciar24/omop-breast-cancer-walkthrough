-- Breast cancer concepts used in the data
--
-- R writes the expanded codelists into a temporary table called
-- codelist_concepts (codelist_name, class, ancestor_concept_id, concept_id).
--
-- For each concept of the breast cancer set that occurs in condition_occurrence,
-- count records and people. Concepts of the set that never occur are not listed.
-- The join key is condition_occurrence.condition_concept_id = concept_id.

SELECT cc.concept_id,
       c.concept_name,
       c.vocabulary_id,
       COUNT(*) AS n_records,
       COUNT(DISTINCT co.person_id) AS n_persons
FROM condition_occurrence co
INNER JOIN codelist_concepts cc
  ON cc.concept_id = co.condition_concept_id
 AND cc.codelist_name = 'breast_cancer'
INNER JOIN concept c
  ON c.concept_id = cc.concept_id
GROUP BY cc.concept_id, c.concept_name, c.vocabulary_id
ORDER BY n_persons DESC
