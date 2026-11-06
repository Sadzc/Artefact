-- 91_exploratorio.sql
-- Validación de supuestos y hallazgos de negocio.
-- No produce tablas mart: es material de análisis para el README

-- J) Distribución de montos por país de tarjeta (quintiles)
--    Permite identificar segmentos de mercado y validar moneda (USD)
SELECT
    ctry_card,
    COUNT(*)                                        AS n_trx,
    ROUND(quantile_cont(amt, 0.10)::DECIMAL, 2)    AS p10,
    ROUND(quantile_cont(amt, 0.50)::DECIMAL, 2)    AS mediana,
    ROUND(quantile_cont(amt, 0.75)::DECIMAL, 2)    AS p75,
    ROUND(quantile_cont(amt, 0.90)::DECIMAL, 2)    AS p90,
    ROUND(MAX(amt)::DECIMAL, 2)                    AS maximo
FROM stg_transac WHERE amt > 0
GROUP BY 1 ORDER BY mediana DESC;

-- J2) Distribución de montos por producto
SELECT
    product_name,
    ROUND(quantile_cont(amt, 0.50)::DECIMAL, 2) AS mediana,
    ROUND(quantile_cont(amt, 0.90)::DECIMAL, 2) AS p90,
    ROUND(MAX(amt)::DECIMAL, 2)                 AS maximo
FROM stg_transac WHERE amt > 0
GROUP BY 1 ORDER BY mediana;

-- L) Mix de productos por país (% de transacciones premium P4+P5)
SELECT
    ctry_card,
    COUNT(*)                                                              AS n_total,
    ROUND(100.0 * COUNT(*) FILTER (WHERE product_name IN ('p4','p5'))
          / COUNT(*), 1)                                                  AS pct_premium,
    ROUND(quantile_cont(amt, 0.50)::DECIMAL, 2)                          AS mediana_global
FROM stg_transac WHERE amt > 0
GROUP BY 1 ORDER BY pct_premium DESC;

-- M) PIVOT: mediana de monto por país × producto
--    Confirma que la brecha entre grupos A y B es consistente en cada producto
PIVOT (
    SELECT ctry_card, product_name,
           ROUND(quantile_cont(amt, 0.50)::DECIMAL, 2) AS mediana
    FROM stg_transac WHERE amt > 0
    GROUP BY 1, 2
) ON product_name USING FIRST(mediana)
ORDER BY p1 DESC;

-- K) Sensibilidad de zona horaria
--    Cuenta transacciones en el borde de mayo (podría cambiar de mes con UTC)
--    Criterio: tarjetas chilenas de crédito, comercios fuera de Chile
--    Borde = 1-may antes de 06:00 o 31-may desde 18:00 (±3h margen UTC-3)
SELECT
    COUNT(*)           AS trx_en_borde,
    SUM(amt)           AS gasto_en_borde,
    COUNT(DISTINCT card_id) AS tarjetas_en_borde,
    ROUND(SUM(LEAST(SUM(amt) OVER (PARTITION BY card_id) * 0.07, 50)), 2) AS cashback_potencial_borde
FROM stg_transac
WHERE product_type = 'credito'
  AND ctry_card    = 'chile'
  AND ctry_mrch   <> 'chile'
  AND amt          > 0
  AND (
      (prch_date = '2024-05-01' AND prch_time < '06:00:00')
   OR (prch_date = '2024-05-31' AND prch_time >= '18:00:00')
  );