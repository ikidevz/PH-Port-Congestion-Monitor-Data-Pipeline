-- tests/assert_congestion_score_in_range.sql
-- Fails if any congestion_score falls outside [0, 100]

SELECT *
FROM {{ ref('congestion_scores') }}
WHERE congestion_score < 0
   OR congestion_score > 100
