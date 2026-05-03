
    
    

select
    turnaround_id as unique_field,
    count(*) as n_records

from "ph_port_monitor"."public_marts"."vessel_turnaround"
where turnaround_id is not null
group by turnaround_id
having count(*) > 1


