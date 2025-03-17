
{{ config(
        materialized='external_table',
        location="/Users/mustafakurtoglu/unitycatalog/etc/data/external/data_storage/Woodcorp_O2C_Activity_table",
        plugin = 'unity')
    }}


with final as (
    select * from {{ref('stg_Woodcorp_O2C_Activity_table')}}
)

select * from final