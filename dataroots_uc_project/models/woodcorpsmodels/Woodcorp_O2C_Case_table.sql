{{ config(
        materialized='external_table',
        location="/Users/mustafakurtoglu/unitycatalog/etc/data/external/data_storage/Woodcorp_O2C_Case_table",
        plugin = 'unity')
    }}

with cases as (

    select * from {{ref('stg_Woodcorp_O2C_Case_table')}}

),

activities as (

    select * from {{ref('stg_Woodcorp_O2C_Activity_table')}}

),

Activity_counts as  (

    select Case_key, count(distinct activity_name) as activity_count
    from activities
    group by 1
),

final as (
select c.*,a.activity_count as activity_count  from cases c
left join Activity_counts a on a.case_key=c.CASE_KEY)

select * from final