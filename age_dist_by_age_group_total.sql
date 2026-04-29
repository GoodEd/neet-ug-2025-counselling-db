-- Age group distribution for ALL students (total) by state and year
-- This is the most comprehensive view - shows what percentage of the entire qualified list falls into each age bracket
WITH classified AS (
    SELECT 
        state,
        year,
        CASE WHEN age_at_cutoff <= 19 THEN '<= 19' ELSE '> 19' END AS age_group
    FROM neetstatecouncelling.candidate_raw
)
SELECT 
    state,
    year,
    age_group,
    COUNT(*) AS student_count,
    SUM(COUNT(*)) OVER (PARTITION BY state, year) AS total_students,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY state, year), 2) AS pct_of_total
FROM classified
GROUP BY state, year, age_group
ORDER BY state, year DESC, CASE WHEN age_group = '<= 19' THEN 1 ELSE 2 END;
