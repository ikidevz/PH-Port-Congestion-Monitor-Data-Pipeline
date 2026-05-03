\c ph_port_monitor

-- ---------------------------------------------------------------------------
-- marts.vessel_turnaround
-- Per-vessel stay duration. Paired ARRIVAL → DEPARTURE per IMO + port.
-- ---------------------------------------------------------------------------

CREATE TABLE marts.vessel_turnaround (
    turnaround_id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    imo_number            VARCHAR(20)  NOT NULL,
    vessel_name           VARCHAR(120) NOT NULL,
    port_code             VARCHAR(5)   NOT NULL  REFERENCES raw.ports(port_code),
    berth_id              SMALLINT     NOT NULL,
    cargo_type            VARCHAR(20)  NOT NULL,
    shipping_line         VARCHAR(80),
    arrived_at            TIMESTAMPTZ  NOT NULL,
    departed_at           TIMESTAMPTZ,                    -- NULL if vessel still in port
    actual_duration_hrs   NUMERIC(6,2),                   -- departed_at - arrived_at
    expected_duration_hrs NUMERIC(5,1) NOT NULL,
    delay_hrs             NUMERIC(6,2),                   -- actual - expected (negative = early)
    is_delayed            BOOLEAN,                        -- actual > expected
    computed_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);


-- ---------------------------------------------------------------------------
-- marts.alert_log
-- Immutable record of every threshold breach. Append-only.
-- ---------------------------------------------------------------------------

CREATE TABLE marts.alert_log (
    alert_id        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    port_code       VARCHAR(5)  NOT NULL REFERENCES raw.ports(port_code),
    alert_type      VARCHAR(30) NOT NULL,   -- CONGESTION_HIGH | BERTH_FULL | WAIT_TIME_EXCEEDED
    congestion_score NUMERIC(5,2),
    threshold_value NUMERIC(5,2),
    message         TEXT        NOT NULL,
    notified        BOOLEAN     NOT NULL DEFAULT FALSE,
    notified_at     TIMESTAMPTZ,
    triggered_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);



-- =============================================================================
-- Congestion level helper function
-- Used by dbt model via {{ ref() }} or called directly
-- =============================================================================

CREATE OR REPLACE FUNCTION marts.score_to_level(score NUMERIC)
RETURNS VARCHAR(10) LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN score >= 80 THEN 'CRITICAL'
        WHEN score >= 60 THEN 'HIGH'
        WHEN score >= 40 THEN 'MODERATE'
        ELSE 'LOW'
    END
$$;