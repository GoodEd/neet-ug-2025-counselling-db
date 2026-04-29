-- Age group distribution for ALL students (total) by state and year
-- This shows what percentage of the entire merit/qualified list falls into each age bracket

WITH age_all AS (
    SELECT 
        state,
        year,
        CASE 
            WHEN age_at_cutoff <= 19 THEN '<= 19' 
            ELSE '> 19' 
        END AS age_group,
        COUNT(*) AS student_count
    FROM neetstatecouncelling.candidate_raw
    GROUP BY state, year, age_group
),
totals AS (
    SELECT 
        state,
        year,
        COUNT(*) AS total_students
    FROM neetstatecouncelling.candidate_raw
    GROUP BY state, year
)
SELECT 
    t.state,
    t.year,
    COALESCE(a.age_group, 'N/A') AS age_group,
    COALESCE(a.student_count, 0) AS student_count,
    t.total_students,
    ROUND(100.0 * COALESCE(a.student_count, 0) / t.total_students, 2) AS pct_of_total
FROM totals t
LEFT JOIN age_all a ON t.state = a.state AND t.year = a.year
ORDER BY t.state, t.year DESC, CASE WHEN a.age_group = '<= 19' THEN 1 ELSE 2 END;
