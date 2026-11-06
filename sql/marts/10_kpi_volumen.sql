-- 10_kpi_volumen.sql
-- KPI: Cantidad de tarjetas por tipo que transaccionaron en cada trimestre

CREATE OR REPLACE TABLE mart_kpi_volumen AS
SELECT
    strftime(prch_date, '%Y') || '-Q' || CAST(quarter(prch_date) AS VARCHAR) AS trimestre,
    product_type,
    COUNT(DISTINCT card_id) AS n_tarjetas
FROM stg_transac
GROUP BY 1, 2
ORDER BY 1, 2;

SELECT * FROM mart_kpi_volumen;