
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select imo_number
from "ph_port_monitor"."public_marts"."vessel_turnaround"
where imo_number is null



  
  
      
    ) dbt_internal_test