{% snapshot orders_snapshot %}

select * from {{ ref('orders') }}

{% endsnapshot %}
