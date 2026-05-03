
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    

select
    score_id as unique_field,
    count(*) as n_records

from "ph_port_monitor"."public_marts"."congestion_scores"
where score_id is not null
group by score_id
having count(*) > 1



  
  
      
    ) dbt_internal_test