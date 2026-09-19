select
    order_id,
    amount
from {{ ref('stg_shop_orders') }}
