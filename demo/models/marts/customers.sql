select
    c.customer_id,
    c.customer_name,
    p.page_view_id
from {{ ref('stg_customers') }} as c
left join {{ ref('snowplow_utils', 'page_views') }} as p
    on p.customer_id = c.customer_id
