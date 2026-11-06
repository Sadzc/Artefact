-- 14_kpi_contactless.sql
-- KPI: Porcentaje de gasto contactless por país de comercio
-- Ordenado de mayor a menor adopción

CREATE OR REPLACE TABLE mart_kpi_contactless AS
SELECT
    ctry_mrch                                                   AS pais,
    ROUND(100.0 * SUM(amt) FILTER (WHERE is_contactless = 1)
                / NULLIF(SUM(amt), 0), 2)                      AS pct_gasto_contactless,
    SUM(amt) FILTER (WHERE is_contactless = 1)                 AS gasto_contactless,
    SUM(amt)                                                    AS gasto_total
FROM stg_transac
WHERE amt > 0
GROUP BY ctry_mrch
ORDER BY pct_gasto_contactless DESC;

SELECT * FROM mart_kpi_contactless;