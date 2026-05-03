
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select expected_duration_hrs
from "ph_port_monitor"."public_staging"."stg_vessel_events"
where expected_duration_hrs is null



  
  
      
    ) dbt_internal_test