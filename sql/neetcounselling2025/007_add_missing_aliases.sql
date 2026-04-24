-- Add aliases for top 15 missing-MCC institutions to resolve institution mappings
-- Strategy: Insert alias records pointing bad names to canonical institutions that have MCC codes.

BEGIN;

-- 1. Jagadguru variant 1 (2206) → canonical (2063)
INSERT INTO neetcounselling2025.institution_alias (institution_id, alias_raw, alias_normalized, source_document_id)
VALUES (2063, 'Jagadguru Gangadhar Mahaswamigalu Moor usavirmath Medical College, Hubballi', lower(regexp_replace('Jagadguru Gangadhar Mahaswamigalu Moor usavirmath Medical College, Hubballi', '[^a-zA-Z0-9]+', '', 'g')), NULL)
ON CONFLICT DO NOTHING;

-- 2. Jagadguru variant 2 (2314) → canonical (2063)
INSERT INTO neetcounselling2025.institution_alias (institution_id, alias_raw, alias_normalized, source_document_id)
VALUES (2063, 'Jagadguru Gangadhar Mahaswamigalu Moorusavirma th Medical College, Hubballi', lower(regexp_replace('Jagadguru Gangadhar Mahaswamigalu Moorusavirma th Medical College, Hubballi', '[^a-zA-Z0-9]+', '', 'g')), NULL)
ON CONFLICT DO NOTHING;

-- 3. AIIMS Guwahati spaced (2281) → canonical (1555)
INSERT INTO neetcounselling2025.institution_alias (institution_id, alias_raw, alias_normalized, source_document_id)
VALUES (1555, 'AIIMS Guwahati, PO- CHANGSARI', lower(regexp_replace('AIIMS Guwahati, PO- CHANGSARI', '[^a-zA-Z0-9]+', '', 'g')), NULL)
ON CONFLICT DO NOTHING;

-- 4. AIIMS Jammu verbose (2284) → canonical (2107)
INSERT INTO neetcounselling2025.institution_alias (institution_id, alias_raw, alias_normalized, source_document_id)
VALUES (2107, 'AIIMS Jammu, AIIMS', lower(regexp_replace('AIIMS Jammu, AIIMS', '[^a-zA-Z0-9]+', '', 'g')), NULL)
ON CONFLICT DO NOTHING;

-- 5. GMC Satna verbose (2294) → canonical (2132)
INSERT INTO neetcounselling2025.institution_alias (institution_id, alias_raw, alias_normalized, source_document_id)
VALUES (2132, 'Government Medical College Satna, Near Kendriya Vidyalaya No. 2', lower(regexp_replace('Government Medical College Satna, Near Kendriya Vidyalaya No. 2', '[^a-zA-Z0-9]+', '', 'g')), NULL)
ON CONFLICT DO NOTHING;

-- 6. GMC Machilipatnam verbose (2297) → canonical (2180)
INSERT INTO neetcounselling2025.institution_alias (institution_id, alias_raw, alias_normalized, source_document_id)
VALUES (2180, 'GOVERNMENT MEDICAL COLLEGE MACHILIPATNAM, KARA AGRAHARAM NEAR RADAR STATION MACHILIPATNAM', lower(regexp_replace('GOVERNMENT MEDICAL COLLEGE MACHILIPATNAM, KARA AGRAHARAM NEAR RADAR STATION MACHILIPATNAM', '[^a-zA-Z0-9]+', '', 'g')), NULL)
ON CONFLICT DO NOTHING;

-- 7. Tirunelveli spaced (2111) → canonical (1588)
INSERT INTO neetcounselling2025.institution_alias (institution_id, alias_raw, alias_normalized, source_document_id)
VALUES (1588, 'GOVT. MEDICAL COLLEGE, TIRUNEL VELI', lower(regexp_replace('GOVT. MEDICAL COLLEGE, TIRUNEL VELI', '[^a-zA-Z0-9]+', '', 'g')), NULL)
ON CONFLICT DO NOTHING;

-- 8. Osmania Hyderabad spaced (2283) → canonical (2103)
INSERT INTO neetcounselling2025.institution_alias (institution_id, alias_raw, alias_normalized, source_document_id)
VALUES (2103, 'Osmania Medical College Koti, HYDERABAD', lower(regexp_replace('Osmania Medical College Koti, HYDERABAD', '[^a-zA-Z0-9]+', '', 'g')), NULL)
ON CONFLICT DO NOTHING;

-- 9. Dr B.R. Ambedkar verbose (2285) → canonical (2116)
INSERT INTO neetcounselling2025.institution_alias (institution_id, alias_raw, alias_normalized, source_document_id)
VALUES (2116, 'Dr. B.R. Ambedkar State Institute of Medical Sciences, Sector 56 Mohali', lower(regexp_replace('Dr. B.R. Ambedkar State Institute of Medical Sciences, Sector 56 Mohali', '[^a-zA-Z0-9]+', '', 'g')), NULL)
ON CONFLICT DO NOTHING;

-- 10. Rampurhat verbose (2300) → canonical (2169)
INSERT INTO neetcounselling2025.institution_alias (institution_id, alias_raw, alias_normalized, source_document_id)
VALUES (2169, 'RAMPURHAT GOVT MEDICAL COLLEGE RAMPURHAT, RAMPURHAT GOVERNMENT MEDICAL COLLEGE AND HOSPITAL PO RAMPURHAT PS RAMPURHAT PIN 731224 DIST BIRBHUM', lower(regexp_replace('RAMPURHAT GOVT MEDICAL COLLEGE RAMPURHAT, RAMPURHAT GOVERNMENT MEDICAL COLLEGE AND HOSPITAL PO RAMPURHAT PS RAMPURHAT PIN 731224 DIST BIRBHUM', '[^a-zA-Z0-9]+', '', 'g')), NULL)
ON CONFLICT DO NOTHING;

-- 11. Sh Vasant Rao Naik spaced (2139) → canonical (1772)
INSERT INTO neetcounselling2025.institution_alias (institution_id, alias_raw, alias_normalized, source_document_id)
VALUES (1772, 'SH VASANT RAO NAIK GOVT.M.C., YAVATM AL', lower(regexp_replace('SH VASANT RAO NAIK GOVT.M.C., YAVATM AL', '[^a-zA-Z0-9]+', '', 'g')), NULL)
ON CONFLICT DO NOTHING;

-- 12. Burdwan spaced (2135) → canonical (1755)
INSERT INTO neetcounselling2025.institution_alias (institution_id, alias_raw, alias_normalized, source_document_id)
VALUES (1755, 'BURDWAN MEDICAL COLLEGE, BURDWA N', lower(regexp_replace('BURDWAN MEDICAL COLLEGE, BURDWA N', '[^a-zA-Z0-9]+', '', 'g')), NULL)
ON CONFLICT DO NOTHING;

-- 13. North Bengal spaced (2128) → canonical (1712)
INSERT INTO neetcounselling2025.institution_alias (institution_id, alias_raw, alias_normalized, source_document_id)
VALUES (1712, 'NORTH BENGAL MED.COLL, DARJEE LING', lower(regexp_replace('NORTH BENGAL MED.COLL, DARJEE LING', '[^a-zA-Z0-9]+', '', 'g')), NULL)
ON CONFLICT DO NOTHING;

-- 14. GMC Sheopur typo (2295) → canonical (1837)
INSERT INTO neetcounselling2025.institution_alias (institution_id, alias_raw, alias_normalized, source_document_id)
VALUES (1837, 'Goverment Medical College Sheopur, M.P', lower(regexp_replace('Goverment Medical College Sheopur, M.P', '[^a-zA-Z0-9]+', '', 'g')), NULL)
ON CONFLICT DO NOTHING;

-- 15. Thanjavur spaced (2291) → canonical (1774)
INSERT INTO neetcounselling2025.institution_alias (institution_id, alias_raw, alias_normalized, source_document_id)
VALUES (1774, 'THANJAVUR MEDICAL COLL., THANJAVUR', lower(regexp_replace('THANJAVUR MEDICAL COLL., THANJAVUR', '[^a-zA-Z0-9]+', '', 'g')), NULL)
ON CONFLICT DO NOTHING;

COMMIT;
