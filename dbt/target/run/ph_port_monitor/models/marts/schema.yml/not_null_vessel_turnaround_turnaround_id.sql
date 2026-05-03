
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select turnaround_id
from "ph_port_monitor"."public_marts"."vessel_turnaround"
where turnaround_id is null



  
  
      
    ) dbt_internal_test