-- Age distribution for ALL ranks (not just top 100k) across all years
-- Useful for: understanding overall demographic trends regardless of rank performance
WITH all_ages AS (
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
state_totals AS (
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
    ROUND(100.0 * a.student_count / t.total_students, 2) AS pct_of_total_merit_list
FROM all_ages a
JOIN state_totals t ON a.state = t.state AND a.year = t.year
ORDER BY a.state, a.year DESC, CASE WHEN a.age_group = '<= 19' THEN 1 ELSE 2 END;