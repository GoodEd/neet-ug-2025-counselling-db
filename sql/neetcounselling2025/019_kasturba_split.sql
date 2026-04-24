BEGIN;

-- Fix: Use candidate_rank_cleaned (integer) instead of candidate_rank (text)
UPDATE neetcounselling2025.allotment_result_effective ae
SET institution_id = 2315,
    data_quality_flags = array_remove(ae.data_quality_flags, 'MCC_CONFLICT'),
    mcc_institute_code = 200339
FROM neetcounselling2025.allotment_raw_parsed arp
JOIN neetcounselling2025.source_document sd ON arp.source_pdf = sd.file_name
WHERE ae.institution_id = 1569
  AND 'MCC_CONFLICT' = ANY(ae.data_quality_flags)
  AND ae.candidate_rank = arp.candidate_rank_cleaned
  AND ae.source_document_id = sd.document_id
  AND arp.allotted_institute_raw ILIKE '%mangalore%';

UPDATE neetcounselling2025.allotment_result_effective ae
SET data_quality_flags = array_remove(ae.data_quality_flags, 'MCC_CONFLICT'),
    mcc_institute_code = 200340
WHERE 'MCC_CONFLICT' = ANY(ae.data_quality_flags)
  AND ae.institution_id IN (1569, 2315);

COMMIT;