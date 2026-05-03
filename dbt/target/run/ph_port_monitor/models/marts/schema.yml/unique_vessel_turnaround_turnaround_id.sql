
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    

select
    turnaround_id as unique_field,
    count(*) as n_records

from "ph_port_monitor"."public_marts"."vessel_turnaround"
where turnaround_id is not null
group by turnaround_id
having count(*) > 1



  
  
      
    ) dbt_internal_test