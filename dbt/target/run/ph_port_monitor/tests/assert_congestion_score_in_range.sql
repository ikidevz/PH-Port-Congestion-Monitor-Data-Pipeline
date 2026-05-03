
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  -- tests/assert_congestion_score_in_range.sql
-- Fails if any congestion_score falls outside [0, 100]

SELECT *
FROM "ph_port_monitor"."public_marts"."congestion_scores"
WHERE congestion_score < 0
   OR congestion_score > 100
  
  
      
    ) dbt_internal_test