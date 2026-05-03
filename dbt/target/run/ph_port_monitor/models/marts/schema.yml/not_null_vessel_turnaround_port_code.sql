
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select port_code
from "ph_port_monitor"."public_marts"."vessel_turnaround"
where port_code is null



  
  
      
    ) dbt_internal_test