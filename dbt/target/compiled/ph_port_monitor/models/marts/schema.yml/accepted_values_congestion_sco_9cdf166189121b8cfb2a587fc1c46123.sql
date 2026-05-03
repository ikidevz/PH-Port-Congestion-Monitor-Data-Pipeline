
    
    

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


