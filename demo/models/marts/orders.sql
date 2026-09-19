select
    o.order_id,
    o.amount,
    c.customer_name
from {{ ref('stg_orders') }} as o
join {{ ref('stg_customers') }} as c
    on o.customer_id = c.customer_id
