
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select is_peak_hour
from "ph_port_monitor"."public_staging"."stg_vessel_events"
where is_peak_hour is null



  
  
      
    ) dbt_internal_test