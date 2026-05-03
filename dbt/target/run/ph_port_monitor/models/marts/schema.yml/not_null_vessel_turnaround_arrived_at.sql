
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select arrived_at
from "ph_port_monitor"."public_marts"."vessel_turnaround"
where arrived_at is null



  
  
      
    ) dbt_internal_test