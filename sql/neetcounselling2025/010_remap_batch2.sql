BEGIN;

-- Batch 2: Additional clear OCR-typo remappings for remaining MISSING_MCC_CODE rows

-- 16. Thiruvananthapuram typo
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1540 WHERE institution_id = 2100;

-- 17. Coimbatore typo
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1562 WHERE institution_id = 2106;

-- 18. Kolkata typo
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1580 WHERE institution_id = 2109;

-- 19. Chengalpattu spacing
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1589 WHERE institution_id = 2112;

-- 20. Aurangabad spacing
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1625 WHERE institution_id = 2117;

-- 21. Kanyakumari spacing
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1681 WHERE institution_id = 2122;

-- 22. KAP Viswanatham spacing
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1686 WHERE institution_id = 2124;

-- 23. MGM Jamshedpur spacing
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1743 WHERE institution_id = 2126;

-- 24. Thoothukudi spacing
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1717 WHERE institution_id = 2130;

-- 25. Maharshi Devraha Deoria spacing
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1840 WHERE institution_id = 2148;

-- 26. Dental Aurangabad spacing
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1746 WHERE institution_id = 2156;

-- 27. Agartala spacing
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1857 WHERE institution_id = 2160;

-- 28. SCB Dental Cuttack spacing
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1760 WHERE institution_id = 2179;

-- 29. North Bengal Dental Sushrutnagar spacing
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1997 WHERE institution_id = 2190;

-- 30. Vikarabad verbose
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 2182 WHERE institution_id = 2302;

-- 31. Gandhi Secunderabad verbose  
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1581 WHERE institution_id = 2306;

-- 32. Thiruvananthapuram verbose (second variant)
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1540 WHERE institution_id = 2307;

-- 33. Purnea email typo
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1845 WHERE institution_id = 2310;

-- 34. Nandyal email typo
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1907 WHERE institution_id = 2311;

-- 35. Kokrajhar spacing
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1970 WHERE institution_id = 2312;

-- 36. North Bengal Dental Sushrutnagar spacing
UPDATE neetcounselling2025.allotment_result_effective SET institution_id = 1997 WHERE institution_id = 2313;

COMMIT;