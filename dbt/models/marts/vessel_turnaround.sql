{{
    config(
        materialized='table',
        schema='marts',
        alias='vessel_turnaround',
        unique_key='turnaround_id'
    )
}}

-- =============================================================================
-- vessel_turnaround  →  marts.vessel_turnaround
-- DDL-aligned: all columns match marts.vessel_turnaround exactly:
--   turnaround_id UUID PK, imo_number, vessel_name, port_code, berth_id,
--   cargo_type, shipping_line, arrived_at, departed_at (nullable),
--   actual_duration_hrs (nullable), expected_duration_hrs,
--   delay_hrs (nullable), is_delayed (nullable), computed_at
-- Pairs ARRIVAL → DEPARTURE per IMO + port_code using visit_rank.
-- departed_at = NULL means vessel is still in port.
-- =============================================================================

WITH arrivals AS (
    SELECT
        imo_number,
        vessel_name,
        port_code,
        berth_id,
        cargo_type,
        shipping_line,
        expected_duration_hrs,
        event_timestamp                                         AS arrived_at,
        -- Rank visits: same vessel may call the same port multiple times
        ROW_NUMBER() OVER (
            PARTITION BY imo_number, port_code
            ORDER BY event_timestamp ASC
        )                                                       AS visit_rank
    FROM {{ ref('stg_vessel_events') }}
    WHERE event_type = 'ARRIVAL'
),

departures AS (
    SELECT
        imo_number,
        port_code,
        event_timestamp                                         AS departed_at,
        ROW_NUMBER() OVER (
            PARTITION BY imo_number, port_code
            ORDER BY event_timestamp ASC
        )                                                       AS visit_rank
    FROM {{ ref('stg_vessel_events') }}
    WHERE event_type = 'DEPARTURE'
),

paired AS (
    -- LEFT JOIN so vessels still in port (no departure yet) are included
    SELECT
        a.imo_number,
        a.vessel_name,
        a.port_code,
        a.berth_id,
        a.cargo_type,
        a.shipping_line,
        a.arrived_at,
        a.expected_duration_hrs,
        d.departed_at                                           -- NULL if still in port
    FROM arrivals a
    LEFT JOIN departures d
        ON  a.imo_number  = d.imo_number
        AND a.port_code   = d.port_code
        AND a.visit_rank  = d.visit_rank
),

with_metrics AS (
    SELECT
        -- turnaround_id UUID PK — matches DDL DEFAULT gen_random_uuid()
        gen_random_uuid()::UUID                                 AS turnaround_id,

        imo_number,
        vessel_name,
        port_code,
        berth_id::SMALLINT                                      AS berth_id,
        cargo_type,
        shipping_line,
        arrived_at,

        -- departed_at TIMESTAMPTZ nullable — NULL if vessel still in port
        departed_at,

        expected_duration_hrs::NUMERIC(5,1)                     AS expected_duration_hrs,

        -- actual_duration_hrs NUMERIC(6,2) nullable — matches DDL
        CASE
            WHEN departed_at IS NOT NULL
            THEN ROUND(
                EXTRACT(EPOCH FROM (departed_at - arrived_at)) / 3600.0,
                2
            )::NUMERIC(6,2)
            ELSE NULL
        END                                                     AS actual_duration_hrs,

        -- delay_hrs NUMERIC(6,2) nullable — actual - expected; negative = early
        CASE
            WHEN departed_at IS NOT NULL
            THEN ROUND(
                EXTRACT(EPOCH FROM (departed_at - arrived_at)) / 3600.0
                - expected_duration_hrs,
                2
            )::NUMERIC(6,2)
            ELSE NULL
        END                                                     AS delay_hrs,

        -- is_delayed BOOLEAN nullable — matches DDL; NULL if still in port
        CASE
            WHEN departed_at IS NOT NULL
            THEN (
                EXTRACT(EPOCH FROM (departed_at - arrived_at)) / 3600.0
                > expected_duration_hrs
            )
            ELSE NULL
        END                                                     AS is_delayed,

        -- computed_at TIMESTAMPTZ — matches DDL DEFAULT NOW()
        NOW()                                                   AS computed_at

    FROM paired
)

SELECT * FROM with_metrics
