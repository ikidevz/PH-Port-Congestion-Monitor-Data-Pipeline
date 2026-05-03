
    
    

with child as (
    select port_code as from_field
    from "ph_port_monitor"."public_staging"."stg_vessel_events"
    where port_code is not null
),

parent as (
    select port_code as to_field
    from "ph_port_monitor"."raw"."ports"
)

select
    from_field

from child
left join parent
    on child.from_field = parent.to_field

where parent.to_field is null


