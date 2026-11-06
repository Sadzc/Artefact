-- 11_kpi_ticket_trimestral.sql
-- KPI: Gasto promedio por tarjeta de crédito por trimestre
-- Solo tarjetas de crédito, solo montos positivos


CREATE OR REPLACE TABLE mart_kpi_ticket_trimestral AS
SELECT
    strftime(prch_date, '%Y') || '-Q' || CAST(quarter(prch_date) AS VARCHAR) AS trimestre,
    ROUND(SUM(amt) / COUNT(DISTINCT card_id), 2) AS ticket_promedio_usd
FROM stg_transac
WHERE product_type = 'credito'
  AND amt > 0
GROUP BY 1
ORDER BY 1;

SELECT * FROM mart_kpi_ticket_trimestral;