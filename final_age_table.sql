-- Combined age analysis: total students + top 100k breakdown by age group
-- Shows both the overall age distribution and how top performers (AI rank <= 100k) are distributed
-- Key metric: pct_within_top100k shows what % of each age group makes it to top 100k
WITH classified AS (
    SELECT 
        state,
        year,
        CASE WHEN age_at_cutoff <= 19 THEN '<= 19' ELSE '> 19' END AS age_group,
        CASE WHEN ai_rank > 0 AND ai_rank <= 100000 THEN 1 ELSE 0 END AS in_top100k
    FROM neetstatecouncelling.candidate_raw
),
agg AS (
    SELECT 
        state,
        year,
        age_group,
        COUNT(*) AS all_students,
        SUM(in_top100k) AS top100k_students
    FROM classified
    GROUP BY state, year, age_group
),
totals AS (
    SELECT 
        state,
        year,
        SUM(all_students) AS total_students,
        SUM(top100k_students) AS total_in_top100k
    FROM agg
    GROUP BY state, year
)
SELECT 
    a.state,
    a.year,
    a.age_group,
    a.all_students,
    ROUND(100.0 * a.all_students / t.total_students, 2) AS pct_all,
    a.top100k_students,
    t.total_in_top100k,
    ROUND(100.0 * a.top100k_students / NULLIF(t.total_in_top100k, 0), 2) AS pct_within_top100k,
    ROUND(100.0 * a.top100k_students / t.total_students, 2) AS pct_of_meritlist,
    t.total_students
FROM agg a
JOIN totals t ON a.state = t.state AND a.year = t.year
ORDER BY a.state, a.year DESC, CASE WHEN a.age_group = '<= 19' THEN 1 ELSE 2 END;
