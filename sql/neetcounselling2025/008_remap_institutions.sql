-- Remap institution IDs for bad OCR names to canonical institutions with MCC codes
-- Fixes MISSING_MCC_CODE flag for ~740 rows

BEGIN;

-- 1. Jagadguru spacing artifact 1
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 2063 WHERE institution_id = 2206;

-- 2. Jagadguru spacing artifact 2
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 2063 WHERE institution_id = 2314;

-- 3. AIIMS Guwahati spacing
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1555 WHERE institution_id = 2281;

-- 4. AIIMS Jammu verbose
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 2107 WHERE institution_id = 2284;

-- 5. GMC Satna verbose
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 2132 WHERE institution_id = 2294;

-- 6. GMC Machilipatnam verbose
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 2180 WHERE institution_id = 2297;

-- 7. Tirunelveli spacing
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1588 WHERE institution_id = 2111;

-- 8. Osmania Hyderabad spacing
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 2103 WHERE institution_id = 2283;

-- 9. Dr BR Ambedkar verbose
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 2116 WHERE institution_id = 2285;

-- 10. Rampurhat verbose
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 2169 WHERE institution_id = 2300;

-- 11. Sh Vasant Rao Naik spacing
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1772 WHERE institution_id = 2139;

-- 12. Burdwan spacing
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1755 WHERE institution_id = 2135;

-- 13. North Bengal spacing
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1712 WHERE institution_id = 2128;

-- 14. GMC Sheopur typo
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1837 WHERE institution_id = 2295;

-- 15. Thanjavur spacing
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1774 WHERE institution_id = 2291;

COMMIT;