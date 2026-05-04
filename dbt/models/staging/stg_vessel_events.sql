{{
    config(
        materialized='incremental',
        schema='staging',
        alias='vessel_events',
        unique_key='event_id',
        incremental_strategy='delete+insert',
        post_hook="UPDATE staging.vessel_events SET dbt_updated_at = NOW()"
    )
}}

-- =============================================================================
-- stg_vessel_events  →  staging.vessel_events
-- DDL-aligned: all columns match staging.vessel_events exactly including
-- event_date (DATE), event_hour (SMALLINT 0-23 PHT), is_peak_hour (BOOLEAN),
-- dbt_updated_at (TIMESTAMPTZ).
-- Incremental: only processes new events since last MAX(event_timestamp).
-- COALESCE handles empty table on first run (MAX returns NULL).
-- =============================================================================

WITH source AS (
    SELECT * FROM {{ source('raw', 'vessel_events') }}

    {% if is_incremental() %}
    -- Only fetch rows newer than what's already in staging.
    -- COALESCE to epoch ensures ALL rows load on first run when table is empty.
    WHERE event_timestamp > COALESCE(
        (SELECT MAX(event_timestamp) FROM {{ this }}),
        '1970-01-01'::TIMESTAMPTZ
    )
    {% endif %}
),

cleaned AS (
    SELECT
        -- === Direct columns from raw.vessel_events ===
        event_id::UUID                                                  AS event_id,
        TRIM(vessel_name)                                               AS vessel_name,
        TRIM(imo_number)                                                AS imo_number,
        port_code,
        berth_id::SMALLINT                                              AS berth_id,
        event_type,
        cargo_type,
        shipping_line,
        gross_tonnage,
        draft_meters,
        expected_duration_hrs,

        -- === Derived: date/time in PH local time (UTC+8) ===
        (event_timestamp AT TIME ZONE 'Asia/Manila')::DATE              AS event_date,
        EXTRACT(HOUR FROM event_timestamp AT TIME ZONE 'Asia/Manila')::SMALLINT
                                                                        AS event_hour,
        (EXTRACT(HOUR FROM event_timestamp AT TIME ZONE 'Asia/Manila')
            BETWEEN 6 AND 20)::BOOLEAN                                  AS is_peak_hour,

        -- === Timestamps ===
        event_timestamp,
        ingested_at,
        NOW()                                                           AS dbt_updated_at

    FROM source
    WHERE
        -- Quality gates matching DDL NOT NULL + CHECK constraints
        vessel_name           IS NOT NULL
        AND imo_number        IS NOT NULL
        AND port_code         IS NOT NULL
        AND berth_id          IS NOT NULL
        AND event_type        IN ('ARRIVAL', 'DEPARTURE')
        AND cargo_type        IN ('CONTAINER','RORO','BULK','TANKER','PASSENGER','GENERAL')
        AND gross_tonnage     > 0
        AND draft_meters      > 0
        AND expected_duration_hrs > 0
        AND event_timestamp   IS NOT NULL
)

SELECT * FROM cleaned