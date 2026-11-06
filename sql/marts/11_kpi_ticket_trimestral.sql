-- 11_kpi_ticket_trimestral.sql
-- KPI: Gasto promedio por tarjeta de crédito por trimestre

CREATE OR REPLACE TABLE mart_kpi_ticket_trimestral AS
SELECT
    trimestre,
    ROUND(SUM(gasto_positivo) / COUNT(DISTINCT card_id), 2) AS ticket_promedio_usd
FROM mart_tarjeta_mes
WHERE product_type   = 'credito'
  AND gasto_positivo > 0
GROUP BY trimestre
ORDER BY trimestre;

SELECT * FROM mart_kpi_ticket_trimestral;