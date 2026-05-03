
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select congestion_score
from "ph_port_monitor"."public_marts"."congestion_scores"
where congestion_score is null



  
  
      
    ) dbt_internal_test