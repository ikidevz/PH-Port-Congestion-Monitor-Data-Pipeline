\c ph_port_monitor

-- ---------------------------------------------------------------------------
-- marts.congestion_scores
-- One row per port per hour. Primary analytics table.
-- ---------------------------------------------------------------------------

CREATE TABLE marts.congestion_scores (
    score_id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    port_code             VARCHAR(5)   NOT NULL  REFERENCES raw.ports(port_code),
    score_hour            TIMESTAMPTZ  NOT NULL,
    berth_capacity        SMALLINT     NOT NULL,
    active_vessels        INTEGER      NOT NULL DEFAULT 0,
    arrivals_count        INTEGER      NOT NULL DEFAULT 0,
    departures_count      INTEGER      NOT NULL DEFAULT 0,
    avg_wait_hours        NUMERIC(6,2),
    max_wait_hours        NUMERIC(6,2),
    berth_utilisation_pct NUMERIC(5,2),                 
    congestion_score      NUMERIC(5,2) NOT NULL DEFAULT 0
                            CHECK (congestion_score BETWEEN 0 AND 100),
    congestion_level      VARCHAR(10)  NOT NULL DEFAULT 'LOW'
                            CHECK (congestion_level IN ('LOW','MODERATE','HIGH','CRITICAL')),
    computed_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (port_code, score_hour)
);