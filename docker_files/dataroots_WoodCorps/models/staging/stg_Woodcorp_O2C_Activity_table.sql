
with source as (

    select * from {{ref('raw_Woodcorp_O2C_Activity_table')}}

),


renamed as (

    select CASE_KEY as case_key,
            ACTIVITY_EN as activity_name,
            EVENTTIME as time_of_event,
            SORTING as sort_value
            from source

)

select * from renamed