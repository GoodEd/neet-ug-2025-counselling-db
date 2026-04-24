BEGIN;
UPDATE neetcounselling2025.institution_alias
SET institution_id = 2291
WHERE institution_alias_id IN (3557, 2984, 4449);

UPDATE neetcounselling2025.institution_alias
SET institution_id = 1589
WHERE institution_alias_id IN (4056);

UPDATE neetcounselling2025.institution
SET mcc_institute_code = NULL
WHERE institution_id = 1589;

UPDATE neetcounselling2025.institution
SET mcc_institute_code = 200281
WHERE institution_id = 2291;

UPDATE neetcounselling2025.institution
SET mcc_institute_code = 200258
WHERE institution_id = 1589;

DELETE FROM neetcounselling2025.institution_alias
WHERE alias_raw ILIKE '%chengalpattu%' AND institution_id = 2291;

DELETE FROM neetcounselling2025.institution_alias
WHERE alias_raw ILIKE '%thanjavur%' AND institution_id = 1589;

UPDATE neetcounselling2025.institution_alias
SET institution_id = 1589
WHERE institution_id = 2112;

UPDATE neetcounselling2025.allotment_raw_parsed
SET institute_id = 1589
WHERE institute_id = 2112;

DO $$ BEGIN
  ASSERT (SELECT COUNT(*) FROM neetcounselling2025.allotment_result_effective WHERE institution_id = 2112) = 0,
    'institution 2112 still has allotment_result_effective rows';
END $$;

DELETE FROM neetcounselling2025.institution
WHERE institution_id = 2112;

UPDATE neetcounselling2025.allotment_result_effective
SET data_quality_flags = array_remove(data_quality_flags, 'MCC_CONFLICT'),
    mcc_institute_code = 200281
WHERE institution_id = 2291 AND 'MCC_CONFLICT' = ANY(data_quality_flags);

UPDATE neetcounselling2025.allotment_result_effective
SET data_quality_flags = array_remove(data_quality_flags, 'MCC_CONFLICT'),
    mcc_institute_code = 200258
WHERE institution_id = 1589 AND 'MCC_CONFLICT' = ANY(data_quality_flags);

COMMIT;
