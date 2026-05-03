
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    

with all_values as (

    select
        cargo_type as value_field,
        count(*) as n_records

    from "ph_port_monitor"."raw"."vessel_events"
    group by cargo_type

)

select *
from all_values
where value_field not in (
    'CONTAINER','RORO','BULK','TANKER','PASSENGER','GENERAL'
)



  
  
      
    ) dbt_internal_test