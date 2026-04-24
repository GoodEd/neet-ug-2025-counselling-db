-- Clear MISSING_MCC_CODE flag for rows now remapped to institutions with MCC codes
BEGIN;

UPDATE neetcounselling2025.allotment_result_effective ae
SET data_quality_flags = array_remove(ae.data_quality_flags, 'MISSING_MCC_CODE')
FROM neetcounselling2025.institution i
WHERE ae.institution_id = i.institution_id
  AND i.mcc_institute_code IS NOT NULL
  AND 'MISSING_MCC_CODE' = ANY(ae.data_quality_flags);

COMMIT;