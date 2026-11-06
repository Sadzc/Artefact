-- 09_mart_tarjeta_mes.sql
-- Mart a grano tarjeta x mes
CREATE OR REPLACE TABLE mart_tarjeta_mes AS
SELECT
    strftime(prch_date, '%Y') || '-Q' || CAST(quarter(prch_date) AS VARCHAR) AS trimestre,
    strftime(prch_date, '%Y-%m')         AS mes,
    product_type,
    card_id,
    SUM(amt) FILTER (WHERE amt > 0)      AS gasto_positivo,
    COUNT(*)                             AS n_trx
FROM stg_transac
GROUP BY trimestre, mes, product_type, card_id;

-- Control: debe dar 46.747 / 8.224 (Q1) y 51.037 / 8.960 (Q2)
SELECT trimestre, product_type, COUNT(DISTINCT card_id) AS n_tarjetas
FROM mart_tarjeta_mes
GROUP BY trimestre, product_type
ORDER BY trimestre, product_type;