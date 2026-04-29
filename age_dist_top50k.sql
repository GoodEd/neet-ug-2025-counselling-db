-- Age distribution for top 50k AI ranks (2025 only)
-- Shows what percentage of top-ranked students in each state fall into each age bracket
-- Useful for: analyzing age demographics of high-performers for NEET 2025
SELECT 
    state,
    CASE 
        WHEN age_at_cutoff <= 19 THEN '<= 19' 
        ELSE '> 19' 
    END AS age_group,
    COUNT(*) AS student_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY state), 2) AS percentage
FROM neetstatecouncelling.candidate_raw
WHERE year = 2025
  AND ai_rank > 0
  AND ai_rank <= 100000
GROUP BY state, age_group
ORDER BY state, age_group ASC;
