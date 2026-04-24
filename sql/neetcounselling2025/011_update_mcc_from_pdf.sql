-- Update MCC codes for remaining missing institutions using the PDF data
-- This is a manual mapping based on institution name similarity

BEGIN;

-- 2287|ESIC MEDICAL COLLEGE & HOSPITAL, ANDHERI - Not in PDF (Mumbai ESIC, likely 904362 or new)
-- 2286|ESIC MEDICAL COLLEGE NARODA, BAPUNAGR - Not in PDF (Gujarat ESIC, likely 904366 or new)

-- 2302|Govt Medical College Vikarabad - Not in PDF
-- 2117|GOVT. MEDICAL COLLEGE, AURANG ABAD - Already exists in DB with MCC 200218
-- 2308|ESIC, Medical College and Hospital - Not in PDF (likely Indore ESIC)
-- 2106|COIMBATORE MEDICAL COLLEGE, COIMBAT ORE - Already exists in DB with MCC 200259
-- 2292|Govt Medical College Faizabad - Not in PDF
-- 2289|PT NEKI RAM SHARMA GOVT MEDICAL COLLEGE, BHIWANI - Not in PDF (Haryana)
-- 2299|GMC Jangaon - Not in PDF
-- 2122|KANYAKUMARI GOVT. MED. COLL., ASARIPALLA M - Already exists in DB with MCC 200274
-- 2100|GOVT.MEDICAL COLLEGE, THIRUVA NANTHAPURAM - Already exists in DB with MCC 200196
-- 2304|PABITRA MOHAN PRADHAN MEDICAL COLLEGE & HOSPITAL, TALCHER - Not in PDF (Odisha)
-- 2130|THOOTHUKUDI MEDICAL COLLEGE, THOOTH UKUDI - Already exists in DB with MCC 1717 or 200284
-- 2288|Government Medical College Chittorgarh - Not in PDF
-- 2303|GOVERNMENT MEDICAL COLLEGE & HOSPITAL, PHULBANI - Already in PDF as 904363
-- 2301|GOVERNMENT MEDICAL COLLEGE NANDYAL - Not in PDF
-- 2298|PRAGJYOTISHPUR MEDICAL COLLEGE, GUWAHATI - Not in PDF
-- 2305|Nagaon Medical college, Dipholu - Not in PDF (but exists in DB as 2181 with MCC 200649)
-- 2124|K.A.P. VISWANATHAM Govt Medical College, TIRUCHIRAP ALLI - Already exists in DB with MCC 1686
-- 2280|AIIMS Bathinda - Not in PDF (likely new AIIMS)
-- 2311|GOVERNMENT MEDICAL COLLEGE NANDYAL - Duplicate of 2301

-- Only actual new matches from PDF that are in the 21 missing list:

-- Phulbani (2303) -> 904363
UPDATE neetcounselling2025.institution SET mcc_institute_code = 904363 WHERE institution_id = 2303 AND mcc_institute_code IS NULL;

COMMIT;