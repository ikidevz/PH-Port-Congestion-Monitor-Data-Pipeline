-- tests/assert_no_negative_turnaround.sql
-- Fails if any completed turnaround has actual_duration_hrs <= 0

SELECT *
FROM {{ ref('vessel_turnaround') }}
WHERE departed_at IS NOT NULL
  AND actual_duration_hrs <= 0
