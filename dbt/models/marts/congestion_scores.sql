{{
    config(
        materialized='incremental',
        schema='marts',
        alias='congestion_scores',
        unique_key=['port_code', 'score_hour'],
        incremental_strategy='delete+insert'
    )
}}

-- =============================================================================
-- congestion_scores  →  marts.congestion_scores
-- DDL-aligned: all columns match marts.congestion_scores exactly:
--   score_id UUID PK, port_code, score_hour TIMESTAMPTZ (hour boundary),
--   berth_capacity SMALLINT, active_vessels INT, arrivals_count INT,
--   departures_count INT, avg_wait_hours NUMERIC(6,2), max_wait_hours NUMERIC(6,2),
--   berth_utilisation_pct NUMERIC(5,2), congestion_score NUMERIC(5,2) CHECK 0–100,
--   congestion_level VARCHAR(10) CHECK LOW|MODERATE|HIGH|CRITICAL,
--   computed_at TIMESTAMPTZ
--
-- Formula (per DDL COMMENT):
--   score = (active/capacity)*0.40 + (avg_wait/24)*0.35 + (arrivals/avg_rate)*0.25
--   scaled to 100, clamped to [0,100]
-- =============================================================================

WITH port_hours AS (
    -- One row per port per hour across the full event history
    SELECT
        p.port_code,
        p.berth_count::SMALLINT                                 AS berth_capacity,
        h.score_hour
    FROM {{ source('raw', 'ports') }} p
    CROSS JOIN LATERAL (
        SELECT generate_series(
            date_trunc('hour', (
                SELECT MIN(event_timestamp)
                FROM {{ ref('stg_vessel_events') }}
            )),
            date_trunc('hour', NOW()),
            '1 hour'::INTERVAL
        ) AS score_hour
    ) h
),

-- Active vessels per port per hour:
-- vessel counted as active if arrived before end of hour AND
-- (not yet departed OR departed after start of hour)
active_per_hour AS (
    SELECT
        vt.port_code,
        h.score_hour,
        COUNT(*)::INTEGER                                       AS active_vessels
    FROM port_hours h
    JOIN {{ ref('vessel_turnaround') }} vt
        ON  vt.port_code  = h.port_code
        AND vt.arrived_at <= h.score_hour + INTERVAL '1 hour'
        AND (vt.departed_at IS NULL OR vt.departed_at > h.score_hour)
    GROUP BY vt.port_code, h.score_hour
),

-- Arrivals and departures per port per hour
events_per_hour AS (
    SELECT
        port_code,
        date_trunc('hour', event_timestamp)                     AS score_hour,
        COUNT(*) FILTER (WHERE event_type = 'ARRIVAL')::INTEGER AS arrivals_count,
        COUNT(*) FILTER (WHERE event_type = 'DEPARTURE')::INTEGER AS departures_count
    FROM {{ ref('stg_vessel_events') }}
    GROUP BY port_code, date_trunc('hour', event_timestamp)
),

-- 7-day rolling avg arrival rate per port — used as surge denominator
avg_arrival_rate AS (
    SELECT
        port_code,
        GREATEST(AVG(arrivals_count), 1.0)                     AS avg_rate
    FROM events_per_hour
    WHERE score_hour >= NOW() - INTERVAL '7 days'
    GROUP BY port_code
),

-- Avg and max wait time per port per hour (from vessel_turnaround)
-- Uses actual_duration_hrs when available, falls back to expected
wait_per_hour AS (
    SELECT
        vt.port_code,
        date_trunc('hour', vt.arrived_at)                      AS score_hour,
        AVG(
            COALESCE(vt.actual_duration_hrs, vt.expected_duration_hrs)
        )::NUMERIC(6,2)                                        AS avg_wait_hours,
        MAX(
            COALESCE(vt.actual_duration_hrs, vt.expected_duration_hrs)
        )::NUMERIC(6,2)                                        AS max_wait_hours
    FROM {{ ref('vessel_turnaround') }} vt
    GROUP BY vt.port_code, date_trunc('hour', vt.arrived_at)
),

assembled AS (
    SELECT
        h.port_code,
        h.score_hour,
        h.berth_capacity,
        COALESCE(a.active_vessels,        0)                   AS active_vessels,
        COALESCE(e.arrivals_count,        0)                   AS arrivals_count,
        COALESCE(e.departures_count,      0)                   AS departures_count,
        COALESCE(w.avg_wait_hours,        0)::NUMERIC(6,2)     AS avg_wait_hours,
        COALESCE(w.max_wait_hours,        0)::NUMERIC(6,2)     AS max_wait_hours,

        -- === Score components (each normalised to 0–1) ===

        -- C1: berth fill — active / capacity, capped at 1
        LEAST(
            COALESCE(a.active_vessels, 0)::NUMERIC
            / NULLIF(h.berth_capacity, 0),
            1.0
        )                                                      AS c_berth_fill,

        -- C2: normalised wait — avg_wait / 24h, capped at 1
        LEAST(
            COALESCE(w.avg_wait_hours, 0)::NUMERIC / 24.0,
            1.0
        )                                                      AS c_wait,

        -- C3: surge — arrivals this hour / 7d avg rate, capped at 1
        LEAST(
            COALESCE(e.arrivals_count, 0)::NUMERIC
            / NULLIF(COALESCE(ar.avg_rate, 1), 0),
            1.0
        )                                                      AS c_surge

    FROM port_hours h
    LEFT JOIN active_per_hour  a   ON a.port_code  = h.port_code
                                  AND a.score_hour = h.score_hour
    LEFT JOIN events_per_hour  e   ON e.port_code  = h.port_code
                                  AND e.score_hour = h.score_hour
    LEFT JOIN wait_per_hour    w   ON w.port_code  = h.port_code
                                  AND w.score_hour = h.score_hour
    LEFT JOIN avg_arrival_rate ar  ON ar.port_code = h.port_code
),

scored AS (
    SELECT
        -- score_id UUID PK — matches DDL DEFAULT gen_random_uuid()
        gen_random_uuid()::UUID                                 AS score_id,

        port_code,

        -- score_hour TIMESTAMPTZ — truncated to hour boundary per DDL comment
        score_hour,

        -- berth_capacity SMALLINT — from raw.ports.berth_count
        berth_capacity::SMALLINT                               AS berth_capacity,

        -- active_vessels INTEGER NOT NULL DEFAULT 0
        active_vessels::INTEGER                                AS active_vessels,

        -- arrivals_count INTEGER NOT NULL DEFAULT 0
        arrivals_count::INTEGER                                AS arrivals_count,

        -- departures_count INTEGER NOT NULL DEFAULT 0
        departures_count::INTEGER                              AS departures_count,

        -- avg_wait_hours NUMERIC(6,2) — nullable in DDL but we default 0
        avg_wait_hours,

        -- max_wait_hours NUMERIC(6,2) — nullable in DDL but we default 0
        max_wait_hours,

        -- berth_utilisation_pct NUMERIC(5,2) — active / capacity * 100
        ROUND(
            active_vessels::NUMERIC / NULLIF(berth_capacity, 0) * 100,
            2
        )::NUMERIC(5,2)                                        AS berth_utilisation_pct,

        -- congestion_score NUMERIC(5,2) CHECK (BETWEEN 0 AND 100)
        -- Formula from DDL COMMENT: weighted composite scaled to 100
        ROUND(
            LEAST(
                (c_berth_fill * 0.40 + c_wait * 0.35 + c_surge * 0.25) * 100,
                100.0
            ),
            2
        )::NUMERIC(5,2)                                        AS congestion_score,

        -- computed_at TIMESTAMPTZ — matches DDL DEFAULT NOW()
        NOW()                                                  AS computed_at

    FROM assembled
)

SELECT
    score_id,
    port_code,
    score_hour,
    berth_capacity,
    active_vessels,
    arrivals_count,
    departures_count,
    avg_wait_hours,
    max_wait_hours,
    berth_utilisation_pct,
    congestion_score,

    -- congestion_level VARCHAR(10) CHECK (LOW|MODERATE|HIGH|CRITICAL)
    -- Calls the marts.score_to_level() function defined in DDL
    marts.score_to_level(congestion_score)::VARCHAR(10)        AS congestion_level,

    computed_at

FROM scored
