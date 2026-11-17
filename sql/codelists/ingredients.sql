-- Drug ingredients by name
--
-- Looks up each ingredient name from codelists/treatment_classes_input.csv.
-- R loads that file into a temporary table called treatment_classes_input.
--
-- The LEFT JOIN keeps every input row. A name with no matching standard
-- RxNorm ingredient comes back with concept_id NULL, so a typo or a missing
-- ingredient is reported and never dropped without notice.
-- LOWER on both sides makes the match ignore upper and lower case.

SELECT i.class,
       i.ingredient_name,
       c.concept_id,
       c.concept_name,
       c.vocabulary_id,
       c.domain_id,
       c.concept_class_id,
       c.concept_code
FROM treatment_classes_input i
LEFT JOIN concept c
  ON LOWER(c.concept_name) = LOWER(i.ingredient_name)
 AND c.vocabulary_id = 'RxNorm'
 AND c.concept_class_id = 'Ingredient'
 AND c.standard_concept = 'S'
 AND c.invalid_reason IS NULL
ORDER BY i.class, i.ingredient_name
