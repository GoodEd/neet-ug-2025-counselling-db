BEGIN;
UPDATE neetcounselling2025.institution
SET mcc_institute_code = 904368
WHERE institution_id = 2290 AND mcc_institute_code IS NULL;
UPDATE neetcounselling2025.institution
SET mcc_institute_code = 904364
WHERE institution_id = 2304 AND mcc_institute_code IS NULL;
UPDATE neetcounselling2025.institution
SET mcc_institute_code = 904365
WHERE institution_id = 2289 AND mcc_institute_code IS NULL;
UPDATE neetcounselling2025.institution
SET mcc_institute_code = 904548
WHERE institution_id = 2308 AND mcc_institute_code IS NULL;
UPDATE neetcounselling2025.allotment_result_effective ae
SET data_quality_flags = array_remove(ae.data_quality_flags, 'MISSING_MCC_CODE')
FROM neetcounselling2025.institution i
WHERE ae.institution_id = i.institution_id
  AND i.mcc_institute_code IS NOT NULL
  AND 'MISSING_MCC_CODE' = ANY(ae.data_quality_flags);
COMMIT;
