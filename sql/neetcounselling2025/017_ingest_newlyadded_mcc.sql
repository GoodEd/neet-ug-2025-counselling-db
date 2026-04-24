BEGIN;
UPDATE neetcounselling2025.institution
SET mcc_institute_code = 904355
WHERE institution_id = 2293 AND mcc_institute_code IS NULL;

UPDATE neetcounselling2025.institution
SET mcc_institute_code = 904352
WHERE institution_name ILIKE '%sheopur%' AND mcc_institute_code IS NULL;

UPDATE neetcounselling2025.institution
SET mcc_institute_code = 904351
WHERE institution_name ILIKE '%singrauli%' AND mcc_institute_code IS NULL;

UPDATE neetcounselling2025.institution
SET mcc_institute_code = 904350
WHERE institution_name ILIKE '%jodhpur%' AND institution_name ILIKE '%dental%' AND mcc_institute_code IS NULL;

UPDATE neetcounselling2025.institution
SET mcc_institute_code = 904360
WHERE institution_name ILIKE '%jaisalmer%' AND mcc_institute_code IS NULL;

UPDATE neetcounselling2025.institution
SET mcc_institute_code = 904359
WHERE institution_name ILIKE '%pragjyotishpur%' AND mcc_institute_code IS NULL;

UPDATE neetcounselling2025.institution
SET mcc_institute_code = 904358
WHERE institution_name ILIKE '%shilong%' AND mcc_institute_code IS NULL;
COMMIT;
