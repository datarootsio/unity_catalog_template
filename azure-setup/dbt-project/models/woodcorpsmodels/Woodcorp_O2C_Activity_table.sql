{{ config(
    materialized='external_table',
    location=var('storage_path'),
    plugin='unity'
) }}

with final as (
    select * from {{ref('stg_Woodcorp_O2C_Activity_table')}}
)

select * from final
