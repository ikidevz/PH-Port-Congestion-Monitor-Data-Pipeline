
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select gross_tonnage
from "ph_port_monitor"."public_staging"."stg_vessel_events"
where gross_tonnage is null



  
  
      
    ) dbt_internal_test