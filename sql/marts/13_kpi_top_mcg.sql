-- 13_kpi_top_mcg.sql
-- KPI: Top 10 MCG por porcentaje de gasto
-- La tabla guarda el ranking completo (todas las categorías)
-- MCG 35 (fuera del maestro) se etiqueta como "mcg no catalogado (35)"

CREATE OR REPLACE TABLE mart_kpi_top_mcg AS
WITH base AS (
    SELECT
        t.mcg_id,
        COALESCE(d.mcg_name, 'mcg no catalogado (35)') AS mcg_nombre,
        SUM(t.amt)                                     AS gasto
    FROM stg_transac t
    LEFT JOIN dim_mcg d ON t.mcg_id = d.mcg
    WHERE t.amt > 0
    GROUP BY t.mcg_id, d.mcg_name
),
total AS (
    SELECT SUM(gasto) AS gasto_total FROM base
),
ranked AS (
    SELECT
        b.mcg_id,
        b.mcg_nombre,
        b.gasto,
        ROUND(100.0 * b.gasto / t.gasto_total, 2) AS pct_gasto,
        RANK() OVER (ORDER BY b.gasto DESC)        AS ranking
    FROM base b
    CROSS JOIN total t
)
SELECT ranking, mcg_id, mcg_nombre, gasto, pct_gasto
FROM ranked
ORDER BY ranking;

SELECT *
FROM mart_kpi_top_mcg
WHERE ranking <= 10
ORDER BY ranking;