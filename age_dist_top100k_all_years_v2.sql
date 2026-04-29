SELECT 
    t.state,
    t.year,
    COALESCE(a.age_group, 'N/A') AS age_group,
    COALESCE(a.student_count, 0) AS student_count,
    t.total_students,
    CASE 
        WHEN t.total_in_top100k > 0 THEN ROUND(100.0 * COALESCE(a.student_count, 0) / t.total_in_top100k, 2)
        ELSE 0.00 
    END AS pct_within_top100k,
    ROUND(100.0 * COALESCE(a.student_count, 0) / t.total_students, 2) AS pct_of_total_merit_list
FROM totals t
LEFT JOIN age_top100k a ON t.state = a.state AND t.year = a.year
ORDER BY t.state, t.year DESC, CASE WHEN a.age_group = '<= 19' THEN 1 ELSE 2 END;
