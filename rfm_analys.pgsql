-- public.v_rfm_by_category source

CREATE OR REPLACE VIEW public.v_rfm_by_category
AS WITH raw_data AS (
         SELECT p.id AS partner_id,
            p.name AS partner_name,
            prod.category,
            COALESCE(EXTRACT(day FROM now() - max(o.order_date)::timestamp with time zone), 999::numeric) AS recency_days,
            count(DISTINCT o.id) AS frequency_count,
            sum(oi.total_price) AS monetary_value
           FROM partners p
             JOIN orders o ON p.id = o.customer_id AND (o.status::text <> ALL (ARRAY['DRAFT'::character varying, 'CANCELLED'::character varying]::text[]))
             JOIN order_items oi ON o.id = oi.order_id
             JOIN products prod ON oi.product_id = prod.id
          WHERE o.order_date > (CURRENT_DATE - '1 year'::interval)
          GROUP BY p.id, p.name, prod.category
        ), scored_data AS (
         SELECT raw_data.partner_id,
            raw_data.partner_name,
            raw_data.category,
            raw_data.recency_days,
            raw_data.frequency_count,
            raw_data.monetary_value,
            ntile(5) OVER (PARTITION BY raw_data.category ORDER BY raw_data.recency_days DESC) AS r_score,
            ntile(5) OVER (PARTITION BY raw_data.category ORDER BY raw_data.frequency_count) AS f_score,
            ntile(5) OVER (PARTITION BY raw_data.category ORDER BY raw_data.monetary_value) AS m_score
           FROM raw_data
        )
 SELECT partner_id,
    partner_name,
    category,
    recency_days,
    frequency_count,
    monetary_value,
    r_score,
    f_score,
    m_score,
    (r_score::text || f_score::text) || m_score::text AS rfm_code,
        CASE
            WHEN r_score >= 4 AND m_score >= 4 THEN 'CHAMPION 🏆'::text
            WHEN r_score >= 3 AND m_score >= 3 THEN 'LOYAL'::text
            WHEN r_score >= 4 AND m_score < 3 THEN 'NEW POTENTIAL 🌱'::text
            WHEN r_score <= 2 AND f_score >= 3 THEN 'AT RISK ⚠️'::text
            WHEN r_score <= 2 AND m_score >= 4 THEN 'LOST WHALE 🐋'::text
            ELSE 'LOW INTEREST'::text
        END AS segment_name
   FROM scored_data;
