
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    

select
    port_code as unique_field,
    count(*) as n_records

from "ph_port_monitor"."raw"."ports"
where port_code is not null
group by port_code
having count(*) > 1



  
  
      
    ) dbt_internal_test