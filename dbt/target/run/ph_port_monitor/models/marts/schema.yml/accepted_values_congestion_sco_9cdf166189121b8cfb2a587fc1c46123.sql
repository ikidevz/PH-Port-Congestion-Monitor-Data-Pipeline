
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    

with all_values as (

    select
        congestion_level as value_field,
        count(*) as n_records

    from "ph_port_monitor"."public_marts"."congestion_scores"
    group by congestion_level

)

select *
from all_values
where value_field not in (
    'LOW','MODERATE','HIGH','CRITICAL'
)



  
  
      
    ) dbt_internal_test