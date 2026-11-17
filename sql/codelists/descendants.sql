-- Descendants of a set of ancestor concepts
--
-- R writes the ancestors into a temporary table called codelist_ancestors,
-- with the columns codelist_name, class and ancestor_concept_id.
--
-- concept_ancestor holds one row for every ancestor and descendant pair in the
-- hierarchy, at any distance. It also holds a row linking each concept to
-- itself (min_levels_of_separation = 0), so the ancestor is in the result too.
--
-- The join keys are
--   codelist_ancestors.ancestor_concept_id = concept_ancestor.ancestor_concept_id
--   concept_ancestor.descendant_concept_id = concept.concept_id (descendant)
--   codelist_ancestors.ancestor_concept_id = concept.concept_id (ancestor)
--
-- Two filters apply to the descendants.
--   Only standard concepts, because clinical tables store standard ones.
--   Only the domain of the ancestor. Drug ingredients also have HemOnc
--   regimens below them, which sit in the Regimen domain and are not drugs.

SELECT a.codelist_name,
       a.class,
       a.ancestor_concept_id,
       ca.min_levels_of_separation,
       c.concept_id,
       c.concept_name,
       c.vocabulary_id,
       c.domain_id,
       c.concept_class_id,
       c.concept_code
FROM codelist_ancestors a
INNER JOIN concept_ancestor ca
  ON ca.ancestor_concept_id = a.ancestor_concept_id
INNER JOIN concept c
  ON c.concept_id = ca.descendant_concept_id
INNER JOIN concept anc
  ON anc.concept_id = a.ancestor_concept_id
WHERE c.standard_concept = 'S'
  AND c.invalid_reason IS NULL
  AND c.domain_id = anc.domain_id
ORDER BY a.codelist_name, a.class, ca.min_levels_of_separation, c.concept_name
