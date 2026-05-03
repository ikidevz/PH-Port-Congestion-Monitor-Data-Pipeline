
  
    

  create  table "ph_port_monitor"."public_marts"."vessel_turnaround__dbt_tmp"
  
  
    as
  
  (
    

-- =============================================================================
-- vessel_turnaround
-- Pairs ARRIVAL → DEPARTURE for the same IMO + port_code.
-- Uses DISTINCT ON to handle duplicate IMO calls (same vessel, multiple visits).
-- Vessels still in port have departed_at = NULL.
-- =============================================================================

WITH arrivals AS (
    SELECT
        event_id,
        imo_number,
        vessel_name,
        port_code,
        berth_id,
        cargo_type,
        shipping_line,
        expected_duration_hrs,
        event_timestamp AS arrived_at,
        ROW_NUMBER() OVER (
            PARTITION BY imo_number, port_code
            ORDER BY event_timestamp
        ) AS visit_rank
    FROM "ph_port_monitor"."public_staging"."stg_vessel_events"
    WHERE event_type = 'ARRIVAL'
),

departures AS (
    SELECT
        imo_number,
        port_code,
        event_timestamp AS departed_at,
        ROW_NUMBER() OVER (
            PARTITION BY imo_number, port_code
            ORDER BY event_timestamp
        ) AS visit_rank
    FROM "ph_port_monitor"."public_staging"."stg_vessel_events"
    WHERE event_type = 'DEPARTURE'
),

paired AS (
    SELECT
        a.imo_number,
        a.vessel_name,
        a.port_code,
        a.berth_id,
        a.cargo_type,
        a.shipping_line,
        a.arrived_at,
        a.expected_duration_hrs,
        d.departed_at
    FROM arrivals a
    LEFT JOIN departures d
        ON  a.imo_number = d.imo_number
        AND a.port_code  = d.port_code
        AND a.visit_rank = d.visit_rank
),

with_metrics AS (
    SELECT
        gen_random_uuid()                                    AS turnaround_id,
        imo_number,
        vessel_name,
        port_code,
        berth_id,
        cargo_type,
        shipping_line,
        arrived_at,
        departed_at,
        expected_duration_hrs,

        -- Actual duration: NULL if vessel still in port
        ROUND(
            EXTRACT(EPOCH FROM (departed_at - arrived_at)) / 3600.0,
            2
        )::NUMERIC(6,2)                                      AS actual_duration_hrs,

        -- Delay: positive = late, negative = early
        ROUND(
            EXTRACT(EPOCH FROM (departed_at - arrived_at)) / 3600.0
            - expected_duration_hrs,
            2
        )::NUMERIC(6,2)                                      AS delay_hrs,

        -- Is delayed flag
        CASE
            WHEN departed_at IS NOT NULL
            THEN EXTRACT(EPOCH FROM (departed_at - arrived_at)) / 3600.0
                 > expected_duration_hrs
            ELSE NULL
        END                                                  AS is_delayed,

        NOW()                                                AS computed_at
    FROM paired
)

SELECT * FROM with_metrics
  );
  