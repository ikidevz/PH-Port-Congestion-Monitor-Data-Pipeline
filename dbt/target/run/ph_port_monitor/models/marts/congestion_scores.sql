
  
    

  create  table "ph_port_monitor"."public_marts"."congestion_scores__dbt_tmp"
  
  
    as
  
  (
    

-- =============================================================================
-- congestion_scores
-- One row per port per hour. Computes the weighted composite congestion score:
--
--   score = (
--       (active_vessels / berth_capacity)         * 0.40   -- berth fill
--     + (avg_wait_hours / 24.0)                   * 0.35   -- normalised wait
--     + (arrivals_this_hour / avg_arrival_rate)   * 0.25   -- surge factor
--   ) * 100
--
-- Clamped to [0, 100].
-- =============================================================================

WITH hours AS (
    -- Generate one row per port per hour in the raw data range
    SELECT
        p.port_code,
        p.berth_count AS berth_capacity,
        h.score_hour
    FROM raw.ports p
    CROSS JOIN LATERAL (
        SELECT generate_series(
            date_trunc('hour', (SELECT MIN(event_timestamp) FROM "ph_port_monitor"."public_staging"."stg_vessel_events")),
            date_trunc('hour', NOW()),
            '1 hour'::interval
        ) AS score_hour
    ) h
),

-- Active vessels per port per hour (arrived but not yet departed)
active_per_hour AS (
    SELECT
        vt.port_code,
        h.score_hour,
        COUNT(*) AS active_vessels
    FROM hours h
    JOIN "ph_port_monitor"."public_marts"."vessel_turnaround" vt
        ON  vt.port_code  = h.port_code
        AND vt.arrived_at <= h.score_hour + INTERVAL '1 hour'
        AND (vt.departed_at IS NULL OR vt.departed_at > h.score_hour)
    GROUP BY vt.port_code, h.score_hour
),

-- Arrivals per port per hour (surge detection)
arrivals_per_hour AS (
    SELECT
        port_code,
        date_trunc('hour', event_timestamp) AS score_hour,
        COUNT(*) AS arrivals_count,
        COUNT(*) FILTER (WHERE event_type = 'DEPARTURE') AS departures_count
    FROM "ph_port_monitor"."public_staging"."stg_vessel_events"
    GROUP BY port_code, score_hour
),

-- Average arrival rate per port (baseline, last 7 days)
avg_arrival_rate AS (
    SELECT
        port_code,
        GREATEST(AVG(arrivals_count), 1) AS avg_rate  -- avoid div-by-zero
    FROM arrivals_per_hour
    WHERE score_hour >= NOW() - INTERVAL '7 days'
    GROUP BY port_code
),

-- Average wait time per port per hour (from turnaround)
wait_per_hour AS (
    SELECT
        vt.port_code,
        date_trunc('hour', vt.arrived_at) AS score_hour,
        AVG(
            COALESCE(vt.actual_duration_hrs, vt.expected_duration_hrs)
        )                                 AS avg_wait_hours,
        MAX(
            COALESCE(vt.actual_duration_hrs, vt.expected_duration_hrs)
        )                                 AS max_wait_hours
    FROM "ph_port_monitor"."public_marts"."vessel_turnaround" vt
    GROUP BY vt.port_code, score_hour
),

-- Assemble all components
assembled AS (
    SELECT
        h.port_code,
        h.score_hour,
        h.berth_capacity,
        COALESCE(a.active_vessels, 0)      AS active_vessels,
        COALESCE(ar.arrivals_count, 0)     AS arrivals_count,
        COALESCE(ar.departures_count, 0)   AS departures_count,
        COALESCE(w.avg_wait_hours, 0)      AS avg_wait_hours,
        COALESCE(w.max_wait_hours, 0)      AS max_wait_hours,
        COALESCE(avg.avg_rate, 1)          AS avg_arrival_rate,

        -- Component 1: berth fill (0–1)
        LEAST(
            COALESCE(a.active_vessels, 0)::NUMERIC / NULLIF(h.berth_capacity, 0),
            1.0
        )                                  AS c_berth_fill,

        -- Component 2: normalised wait (0–1, capped at 1 = 24hr wait)
        LEAST(COALESCE(w.avg_wait_hours, 0) / 24.0, 1.0) AS c_wait,

        -- Component 3: surge (0–1, capped at 1 = 2× average rate)
        LEAST(
            COALESCE(ar.arrivals_count, 0)::NUMERIC / NULLIF(COALESCE(avg.avg_rate, 1), 0),
            1.0
        )                                  AS c_surge

    FROM hours h
    LEFT JOIN active_per_hour   a   ON a.port_code = h.port_code AND a.score_hour = h.score_hour
    LEFT JOIN arrivals_per_hour ar  ON ar.port_code = h.port_code AND ar.score_hour = h.score_hour
    LEFT JOIN wait_per_hour     w   ON w.port_code = h.port_code AND w.score_hour = h.score_hour
    LEFT JOIN avg_arrival_rate  avg ON avg.port_code = h.port_code
),

scored AS (
    SELECT
        gen_random_uuid()                        AS score_id,
        port_code,
        score_hour,
        berth_capacity,
        active_vessels,
        arrivals_count,
        departures_count,
        ROUND(avg_wait_hours::NUMERIC, 2)        AS avg_wait_hours,
        ROUND(max_wait_hours::NUMERIC, 2)        AS max_wait_hours,

        -- Berth utilisation %
        ROUND(
            (active_vessels::NUMERIC / NULLIF(berth_capacity, 0)) * 100, 2
        )                                        AS berth_utilisation_pct,

        -- Composite congestion score [0–100]
        ROUND(
            LEAST(
                (c_berth_fill * 0.40 + c_wait * 0.35 + c_surge * 0.25) * 100,
                100
            )::NUMERIC, 2
        )                                        AS congestion_score,

        NOW()                                    AS computed_at
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
    marts.score_to_level(congestion_score) AS congestion_level,
    computed_at
FROM scored
  );
  