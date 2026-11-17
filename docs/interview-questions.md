# Interview questions

Questions an interviewer might ask about this repository. The answers are left
empty on purpose.

## Index date and cohort

**1. Why is the index date the first breast cancer record inside an
observation period, and not the first record at any time?**

Answer.

**2. More than half of the people with a breast cancer record fail the
365-day prior-observation rule. What does that tell you about the data, and
would you change the rule for a real study?**

Answer.

## Censoring

**3. In `adtte_like`, what does `CNSR = 1` mean, and why does the code pass
`1 - CNSR` to `survival::Surv()`?**

Answer.

**4. Time to first treatment is censored at death. Why is that a
simplification, and what would you use instead?**

Answer.

## Immortal time

**5. What is immortal-time bias, and where would it appear in the naive "ever
treated against never treated" comparison?**

Answer.

**6. The landmark analysis at day 90 changes the treated group's survival only
a little in this data. Why, and what does the landmark approach cost you?**

Answer.

## Concept sets

**7. How is the breast cancer concept set built from `concept` and
`concept_ancestor`, and why is no concept ID typed by hand?**

Answer.

**8. The ischaemic heart disease set has two parent concepts. Why was one not
enough, and how did you find out?**

Answer.

## Mapping

**9. What does the "Maps to" relationship do, and what would change if the
source data were coded in ICD-10-CM instead of SNOMED?**

Answer.

## Data quality

**10. More than half of the drug records repeat another record on person,
drug, start date and type. How did you check what they are, and how would they
affect your analyses?**

Answer.

**11. Why do the data-quality checks report failing rows instead of removing
them?**

Answer.

## Analysis Results Data

**12. What is Analysis Results Data, and what does building the report tables
from it, rather than from patient-level data, protect against?**

Answer.
