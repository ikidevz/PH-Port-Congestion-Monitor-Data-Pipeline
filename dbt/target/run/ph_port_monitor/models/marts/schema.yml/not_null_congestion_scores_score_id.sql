
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select score_id
from "ph_port_monitor"."public_marts"."congestion_scores"
where score_id is null



  
  
      
    ) dbt_internal_test