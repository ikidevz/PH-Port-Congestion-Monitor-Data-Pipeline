
    
    

with all_values as (

    select
        cargo_type as value_field,
        count(*) as n_records

    from "ph_port_monitor"."public_staging"."stg_vessel_events"
    group by cargo_type

)

select *
from all_values
where value_field not in (
    'CONTAINER','RORO','BULK','TANKER','PASSENGER','GENERAL'
)


