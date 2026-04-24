BEGIN;

-- Remap Salem OCR typo (2114 → 1592)
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1592 WHERE institution_id = 2114;

-- Cleanup stale MISSING_MCC_CODE flags after remap
UPDATE neetcounselling2025.allotment_result_effective ae
SET data_quality_flags = array_remove(ae.data_quality_flags, 'MISSING_MCC_CODE')
FROM neetcounselling2025.institution i
WHERE ae.institution_id = i.institution_id
  AND i.mcc_institute_code IS NOT NULL
  AND 'MISSING_MCC_CODE' = ANY(ae.data_quality_flags);

COMMIT;