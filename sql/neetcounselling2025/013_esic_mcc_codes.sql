-- Update MCC codes from Newly Added Seats PDF
BEGIN;

UPDATE neetcounselling2025.institution SET mcc_institute_code = 904366 WHERE institution_id = 2286 AND mcc_institute_code IS NULL;

COMMIT;