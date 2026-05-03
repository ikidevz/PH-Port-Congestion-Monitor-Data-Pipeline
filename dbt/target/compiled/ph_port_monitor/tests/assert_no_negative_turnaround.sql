-- tests/assert_no_negative_turnaround.sql
-- Fails if any completed turnaround has actual_duration_hrs <= 0

SELECT *
FROM "ph_port_monitor"."public_marts"."vessel_turnaround"
WHERE departed_at IS NOT NULL
  AND actual_duration_hrs <= 0