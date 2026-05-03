
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select event_hour
from "ph_port_monitor"."public_staging"."stg_vessel_events"
where event_hour is null



  
  
      
    ) dbt_internal_test