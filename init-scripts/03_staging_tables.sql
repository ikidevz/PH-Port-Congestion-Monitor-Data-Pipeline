\c ph_port_monitor

-- staging.vessel_events
-- Cleaned, typed, with derived fields. Rebuilt on each dbt run.
-- ---------------------------------------------------------------------------

CREATE TABLE staging.vessel_events (
    event_id              UUID         PRIMARY KEY,
    vessel_name           VARCHAR(120) NOT NULL,
    imo_number            VARCHAR(20)  NOT NULL,
    port_code             VARCHAR(5)   NOT NULL  REFERENCES raw.ports(port_code),
    berth_id              SMALLINT     NOT NULL,
    event_type            VARCHAR(15)  NOT NULL,
    cargo_type            VARCHAR(20)  NOT NULL,
    shipping_line         VARCHAR(80),
    gross_tonnage         INTEGER      NOT NULL,
    draft_meters          NUMERIC(4,1) NOT NULL,
    expected_duration_hrs NUMERIC(5,1) NOT NULL,
    event_date            DATE         NOT NULL,          -- derived: date part of event_timestamp
    event_hour            SMALLINT     NOT NULL,          -- derived: 0–23 (PH local)
    is_peak_hour          BOOLEAN      NOT NULL,          -- derived: 06–20 PHT
    event_timestamp       TIMESTAMPTZ  NOT NULL,
    ingested_at           TIMESTAMPTZ  NOT NULL,
    dbt_updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);