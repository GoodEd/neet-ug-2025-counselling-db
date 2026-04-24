BEGIN;

-- Remap remaining OCR-damaged institution names to canonical MCC-bearing records

-- Purnea variants → canonical (1845)
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1845 WHERE institution_id IN (2158, 2296, 2310);

-- Nagaon variant → canonical (2181)
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 2181 WHERE institution_id = 2305;

COMMIT;