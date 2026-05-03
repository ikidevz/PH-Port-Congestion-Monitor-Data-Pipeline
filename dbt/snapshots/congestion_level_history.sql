-- snapshots/congestion_level_history.sql
-- Tracks when a port's congestion_level changes (SCD Type 2).
-- Useful for: "how long was MNL in CRITICAL state last week?"
-- Run with: dbt snapshot

{% snapshot congestion_level_history %}

{{
    config(
        target_schema='snapshots',
        unique_key='port_code',
        strategy='check',
        check_cols=['congestion_level', 'congestion_score'],
        invalidate_hard_deletes=False
    )
}}

SELECT
    port_code,
    score_hour,
    congestion_score,
    congestion_level,
    berth_utilisation_pct,
    active_vessels,
    computed_at
FROM {{ ref('congestion_scores') }}
WHERE score_hour = date_trunc('hour', NOW())

{% endsnapshot %}
