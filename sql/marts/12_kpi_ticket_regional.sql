-- 12_kpi_ticket_regional.sql
-- KPI: Ticket promedio de tarjetas de crédito por producto y país
-- Incluye la región para filtrar Sudamérica en el dashboard.
CREATE OR REPLACE TABLE mart_kpi_ticket_regional AS
SELECT
    t.product_name,
    t.ctry_mrch               AS pais,
    dp.region,
    ROUND(AVG(t.amt), 2)      AS ticket_promedio_usd,
    COUNT(*)                  AS n_transacciones
FROM stg_transac t
INNER JOIN dim_pais dp ON t.ctry_mrch = dp.pais
WHERE t.product_type = 'credito'
  AND t.amt > 0
GROUP BY t.product_name, t.ctry_mrch, dp.region
ORDER BY dp.region, t.product_name, t.ctry_mrch;

SELECT * FROM mart_kpi_ticket_regional;