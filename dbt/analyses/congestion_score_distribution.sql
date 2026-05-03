-- analyses/congestion_score_distribution.sql
-- [DX-04] Understand score spread across all ports and hours.
-- Run with: dbt compile --select analyses/congestion_score_distribution
-- Then execute the compiled SQL in your DB client.

SELECT
    width_bucket(congestion_score, 0, 100, 10) * 10 - 10  AS bucket_start,
    width_bucket(congestion_score, 0, 100, 10) * 10        AS bucket_end,
    COUNT(*)                                                AS observations,
    ROUND(COUNT(*)::NUMERIC / SUM(COUNT(*)) OVER () * 100, 1) AS share_pct
FROM {{ ref('congestion_scores') }}
GROUP BY bucket_start, bucket_end
ORDER BY bucket_start
