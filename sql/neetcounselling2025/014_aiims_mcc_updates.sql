BEGIN;

-- Update AIIMS Mangalagiri (2278/2101)
UPDATE neetcounselling2025.institution SET mcc_institute_code = 200510 WHERE institution_id = 2101 AND mcc_institute_code IS NULL;

-- Update AIIMS-Bhopal (2279)
UPDATE neetcounselling2025.institution SET mcc_institute_code = 200503 WHERE institution_id = 2099 AND mcc_institute_code IS NULL;

-- Update AIIMS Bathinda (2280)
UPDATE neetcounselling2025.institution SET mcc_institute_code = 200511 WHERE institution_id = 2105 AND mcc_institute_code IS NULL;

-- Clear stale MISSING_MCC_CODE flags for institutions now with MCC codes
UPDATE neetcounselling2025.allotment_result_effective ae
SET data_quality_flags = array_remove(ae.data_quality_flags, 'MISSING_MCC_CODE')
FROM neetcounselling2025.institution i
WHERE ae.institution_id = i.institution_id
  AND i.mcc_institute_code IS NOT NULL
  AND 'MISSING_MCC_CODE' = ANY(ae.data_quality_flags);

COMMIT;