-- macros/ph_now.sql
-- Returns current timestamp in Philippine Time (UTC+8)
-- Usage: {{ ph_now() }}

{% macro ph_now() %}
    (NOW() AT TIME ZONE 'Asia/Manila')
{% endmacro %}


-- macros/score_to_level.sql
-- Mirrors the marts.score_to_level() SQL function for use in dbt models
-- Usage: {{ score_to_level('congestion_score') }}

{% macro score_to_level(score_col) %}
    CASE
        WHEN {{ score_col }} >= 80 THEN 'CRITICAL'
        WHEN {{ score_col }} >= 60 THEN 'HIGH'
        WHEN {{ score_col }} >= 40 THEN 'MODERATE'
        ELSE 'LOW'
    END
{% endmacro %}
