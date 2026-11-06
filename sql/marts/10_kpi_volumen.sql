-- 10_kpi_volumen.sql
-- KPI: Cantidad de tarjetas por tipo que transaccionaron en cada trimestre
CREATE OR REPLACE TABLE mart_kpi_volumen AS
SELECT
    trimestre,
    product_type,
    COUNT(DISTINCT card_id) AS n_tarjetas
FROM mart_tarjeta_mes
GROUP BY trimestre, product_type
ORDER BY trimestre, product_type;

SELECT * FROM mart_kpi_volumen;