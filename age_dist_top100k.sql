-- Age distribution for top 100k AI ranks with percentage of total merit list (all years)
-- Compares age demographics of top performers vs entire merit list for each state+year
WITH age_top100k AS (
    SELECT 
        state,
        year,
        CASE 
            WHEN age_at_cutoff <= 19 THEN '<= 19' 
            ELSE '> 19' 
        END AS age_group,
        COUNT(*) AS student_count
    FROM neetstatecouncelling.candidate_raw
    WHERE ai_rank > 0
      AND ai_rank <= 100000
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
    a.state,
    a.year,
    a.age_group,
    a.student_count,
    t.total_students,
    ROUND(100.0 * a.student_count / SUM(a.student_count) OVER (PARTITION BY a.state, a.year), 2) AS pct_within_top100k,
    ROUND(100.0 * a.student_count / t.total_students, 2) AS pct_of_total_merit_list
FROM age_top100k a
JOIN totals t ON a.state = t.state AND a.year = t.year
ORDER BY a.state, a.year DESC, a.age_group ASC;