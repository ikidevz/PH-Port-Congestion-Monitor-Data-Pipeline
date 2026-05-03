{{
    config(
        materialized='view',
        schema='staging'
    )
}}

-- =============================================================================
-- stg_vessel_events
-- Cleans raw.vessel_events: adds derived date/hour/peak-hour fields.
-- Materialized as a view so it always reflects the latest raw data.
-- =============================================================================

WITH source AS (
    SELECT * FROM {{ source('raw', 'vessel_events') }}
),

cleaned AS (
    SELECT
        event_id,
        vessel_name,
        imo_number,
        port_code,
        berth_id,
        event_type,
        cargo_type,
        shipping_line,
        gross_tonnage,
        draft_meters,
        expected_duration_hrs,

        -- Derived: calendar fields in PH local time (PHT = UTC+8)
        (event_timestamp AT TIME ZONE 'Asia/Manila')::DATE  AS event_date,
        EXTRACT(HOUR FROM event_timestamp AT TIME ZONE 'Asia/Manila')::SMALLINT AS event_hour,

        -- Derived: peak hours 06:00–20:00 PHT
        EXTRACT(HOUR FROM event_timestamp AT TIME ZONE 'Asia/Manila') BETWEEN 6 AND 20
            AS is_peak_hour,

        event_timestamp,
        ingested_at
    FROM source
    WHERE
        -- Basic quality gates
        vessel_name IS NOT NULL
        AND imo_number IS NOT NULL
        AND port_code IS NOT NULL
        AND event_type IN ('ARRIVAL', 'DEPARTURE')
        AND gross_tonnage > 0
        AND draft_meters > 0
        AND expected_duration_hrs > 0
)

SELECT * FROM cleaned
