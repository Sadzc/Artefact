-- 20_cashback_mayo2024.sql
-- Campaña cashback mayo 2024: tarjetas de crédito chilenas
-- en comercios fuera de Chile. 7% con tope 50 USD por tarjeta
-- Se excluyen montos negativos (reversas/devoluciones)

-- Paso 1: transacciones base de la campaña
CREATE OR REPLACE TABLE mart_cashback_base AS
SELECT
    card_id,
    amt,
    ctry_mrch,
    prch_date
FROM stg_transac
WHERE product_type  = 'credito'
  AND ctry_card     = 'chile'
  AND ctry_mrch    <> 'chile'
  AND amt           > 0
  AND prch_date    >= '2024-05-01'
  AND prch_date     < '2024-06-01';

-- Paso 2: cashback por tarjeta (con tope de 50 USD)
CREATE OR REPLACE TABLE mart_cashback_tarjeta AS
SELECT
    card_id,
    SUM(amt)                                             AS gasto_bruto,
    ROUND(SUM(amt) * 0.07, 2)                            AS cashback_sin_tope,
    ROUND(LEAST(SUM(amt) * 0.07, 50), 2)                 AS cashback_final,
    CASE WHEN SUM(amt) * 0.07 >= 50 THEN 1 ELSE 0 END   AS llego_al_tope
FROM mart_cashback_base
GROUP BY card_id;

-- Paso 3: resumen ejecutivo
SELECT
    COUNT(*)                                              AS tarjetas_impactadas,
    SUM(llego_al_tope)                                    AS tarjetas_en_tope,
    ROUND(SUM(cashback_final), 2)                         AS costo_total_usd,
    ROUND(SUM(cashback_sin_tope), 2)                      AS costo_sin_tope,
    ROUND(SUM(cashback_sin_tope) - SUM(cashback_final), 2) AS ahorro_por_tope,
    ROUND(AVG(cashback_final), 2)                         AS cashback_promedio_usd
FROM mart_cashback_tarjeta;

-- Paso 4: sensibilidad ctry_mrch vs is_xb_calc
-- Compara el costo según dos criterios de elegibilidad
WITH por_criterio AS (
    SELECT
        'criterio: ctry_mrch' AS metodo,
        card_id,
        SUM(amt) AS gasto
    FROM mart_cashback_base
    GROUP BY card_id

    UNION ALL

    SELECT
        'criterio: is_xb_calc' AS metodo,
        card_id,
        SUM(amt) AS gasto
    FROM stg_transac
    WHERE product_type = 'credito'
      AND ctry_card    = 'chile'
      AND is_xb_calc   = TRUE
      AND amt          > 0
      AND prch_date   >= '2024-05-01'
      AND prch_date    < '2024-06-01'
    GROUP BY card_id
)
SELECT
    metodo,
    COUNT(*)                                   AS tarjetas,
    ROUND(SUM(LEAST(gasto * 0.07, 50)), 2)    AS costo_total_usd
FROM por_criterio
GROUP BY metodo
ORDER BY metodo;