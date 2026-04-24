-- Final batch remap for remaining OCR-damaged / verbose institution names
-- These are OCR spacing artifacts vs. canonical MCC-bearing records

BEGIN;

-- AIIMS variants → canonical IDs
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 2101 WHERE institution_id = 2278;
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 2099 WHERE institution_id = 2279;
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 2105 WHERE institution_id = 2280;

-- ESIC variants → canonical IDs (using closest match)
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 2228 WHERE institution_id = 2282;
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 2229 WHERE institution_id = 2287;

-- Government Medical College variants → canonical IDs
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 2142 WHERE institution_id = 2288;
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 2143 WHERE institution_id = 2292;
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 2303 WHERE institution_id = 2309;

-- GMC variants → canonical IDs
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 2176 WHERE institution_id = 2299;
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1907 WHERE institution_id = 2301;

-- Pragjyotishpur → Guwahati Medical College (same campus)
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1647 WHERE institution_id = 2298;

-- Wayanad → Government Medical College, Wayanad (not in MCC yet)
-- 2290 remains as-is (no canonical match)

COMMIT;