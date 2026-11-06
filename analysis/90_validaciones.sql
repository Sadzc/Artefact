-- 90_validaciones.sql
-- Chequeos de calidad sobre raw_transac y stg_transac
-- No modifican datos: solo miden problemas para documentarlos
-- Ejecutar cada query con el cursor dentro + Ctrl+Enter

-- A) Resumen general de calidad en 1 solo escaneo (Single-Pass)
WITH base_metrics AS (
    SELECT
        COUNT(*)                                              AS total_filas,
        MIN(prch_date)                                        AS fecha_min,
        MAX(prch_date)                                        AS fecha_max,
        COUNT(*) FILTER (WHERE prch_date IS NULL)             AS fechas_invalidas,
        COUNT(*) FILTER (WHERE prch_time IS NULL)             AS horas_invalidas,
        COUNT(*) FILTER (WHERE amt IS NULL)                   AS amt_nulo,
        COUNT(*) FILTER (WHERE amt < 0)                       AS amt_negativo,
        COUNT(*) FILTER (WHERE amt = 0)                       AS amt_cero,
        MAX(amt)                                              AS amt_max,
        COUNT(*) FILTER (WHERE product_type IS NULL)          AS product_type_sin_map,
        COUNT(*) FILTER (WHERE is_xb_original <> is_xb_calc) AS xb_inconsistente,
        COUNT(DISTINCT card_id)                               AS tarjetas_distintas
    FROM stg_transac
),
integridad_dim AS (
    SELECT
        COUNT(*) FILTER (WHERE dp_card.pais IS NULL) AS pais_card_fuera_dim,
        COUNT(*) FILTER (WHERE dp_mrch.pais IS NULL) AS pais_mrch_fuera_dim,
        COUNT(*) FILTER (WHERE dmcg.mcg IS NULL)     AS mcg_huerfano_filas
    FROM stg_transac t
    LEFT JOIN dim_pais dp_card ON t.ctry_card = dp_card.pais
    LEFT JOIN dim_pais dp_mrch ON t.ctry_mrch = dp_mrch.pais
    LEFT JOIN dim_mcg  dmcg    ON t.mcg_id    = dmcg.mcg
),
duplicados AS (
    SELECT (COUNT(*) - COUNT(*) OVER ())::BIGINT AS dup
    FROM (SELECT DISTINCT * FROM stg_transac)
),
card_anomalias AS (
    SELECT
        COUNT(*) FILTER (WHERE n_prod > 1) AS tarjetas_multi_tipo,
        COUNT(*) FILTER (WHERE n_pais > 1) AS tarjetas_multi_pais
    FROM (
        SELECT card_id,
               COUNT(DISTINCT product_type) AS n_prod,
               COUNT(DISTINCT ctry_card)    AS n_pais
        FROM stg_transac
        GROUP BY card_id
    )
)
SELECT 'filas_total'            AS chequeo, total_filas::VARCHAR            AS valor FROM base_metrics
UNION ALL SELECT 'fecha_min',            fecha_min::VARCHAR                 FROM base_metrics
UNION ALL SELECT 'fecha_max',            fecha_max::VARCHAR                 FROM base_metrics
UNION ALL SELECT 'fechas_invalidas',     fechas_invalidas::VARCHAR          FROM base_metrics
UNION ALL SELECT 'horas_invalidas',      horas_invalidas::VARCHAR           FROM base_metrics
UNION ALL SELECT 'amt_nulo',             amt_nulo::VARCHAR                  FROM base_metrics
UNION ALL SELECT 'amt_negativo',         amt_negativo::VARCHAR              FROM base_metrics
UNION ALL SELECT 'amt_cero',             amt_cero::VARCHAR                  FROM base_metrics
UNION ALL SELECT 'amt_max',              amt_max::VARCHAR                   FROM base_metrics
UNION ALL SELECT 'product_type_sin_map', product_type_sin_map::VARCHAR      FROM base_metrics
UNION ALL SELECT 'pais_card_fuera_dim',  pais_card_fuera_dim::VARCHAR       FROM integridad_dim
UNION ALL SELECT 'pais_mrch_fuera_dim',  pais_mrch_fuera_dim::VARCHAR       FROM integridad_dim
UNION ALL SELECT 'mcg_huerfano_filas',   mcg_huerfano_filas::VARCHAR        FROM integridad_dim
UNION ALL SELECT 'xb_inconsistente',     xb_inconsistente::VARCHAR          FROM base_metrics
UNION ALL SELECT 'duplicados_exactos',   (COUNT(*) - (SELECT COUNT(*) FROM (SELECT DISTINCT * FROM stg_transac)))::VARCHAR FROM stg_transac
UNION ALL SELECT 'tarjetas_distintas',   tarjetas_distintas::VARCHAR        FROM base_metrics
UNION ALL SELECT 'tarjetas_multi_tipo',  tarjetas_multi_tipo::VARCHAR       FROM card_anomalias
UNION ALL SELECT 'tarjetas_multi_pais',  tarjetas_multi_pais::VARCHAR       FROM card_anomalias;

-- B) Valores distintos ya limpios
SELECT 'product_type' AS campo, product_type AS valor, COUNT(*) AS n FROM stg_transac GROUP BY 1,2
UNION ALL
SELECT 'product_name', product_name, COUNT(*) FROM stg_transac GROUP BY 1,2
UNION ALL
SELECT 'is_contactless', is_contactless::VARCHAR, COUNT(*) FROM stg_transac GROUP BY 1,2
ORDER BY campo, n DESC;

-- C) Países limpios (tarjeta y comercio)
WITH card AS (SELECT ctry_card AS pais, COUNT(*) AS n FROM stg_transac GROUP BY 1),
     mrch AS (SELECT ctry_mrch AS pais, COUNT(*) AS n FROM stg_transac GROUP BY 1)
SELECT COALESCE(card.pais, mrch.pais) AS pais,
       COALESCE(card.n, 0)            AS n_como_ctry_card,
       COALESCE(mrch.n, 0)            AS n_como_ctry_mrch
FROM card FULL OUTER JOIN mrch ON card.pais = mrch.pais
ORDER BY pais;

-- D) MCG fuera del maestro (no se borran, se investigan)
SELECT t.mcg_id,
       COUNT(*)                AS n_trx,
       SUM(t.amt)              AS gasto,
       COUNT(DISTINCT t.mrch)  AS n_comercios,
       COUNT(DISTINCT t.card_id) AS n_tarjetas
FROM stg_transac t
LEFT JOIN dim_mcg d ON t.mcg_id = d.mcg
WHERE d.mcg IS NULL
GROUP BY 1 ORDER BY gasto DESC;

-- E1) Peso del MCG 35 sobre el total
SELECT
    SUM(amt) FILTER (WHERE mcg_id = 35)  AS gasto_mcg35,
    SUM(amt)                              AS gasto_total,
    ROUND(100.0 * SUM(amt) FILTER (WHERE mcg_id = 35) / NULLIF(SUM(amt),0), 2) AS pct_gasto,
    ROUND(100.0 * COUNT(*) FILTER (WHERE mcg_id = 35) / NULLIF(COUNT(*),0), 2) AS pct_trx
FROM stg_transac;

-- E2) Distribución del MCG 35 por mes, producto y país
SELECT 'mes' AS dimension, strftime(prch_date,'%Y-%m') AS valor, COUNT(*) AS n FROM stg_transac WHERE mcg_id=35 GROUP BY 1,2
UNION ALL SELECT 'product_type', product_type, COUNT(*) FROM stg_transac WHERE mcg_id=35 GROUP BY 1,2
UNION ALL SELECT 'ctry_mrch', ctry_mrch, COUNT(*) FROM stg_transac WHERE mcg_id=35 GROUP BY 1,2
ORDER BY dimension, n DESC;

-- E3) Comercios del MCG 35 que también tienen MCG válido
--     Solo diagnóstico: NO se reasigna (nombre de comercio no es clave única)
SELECT COUNT(DISTINCT t35.mrch) AS comercios_mcg35_con_otro_mcg_valido
FROM (SELECT DISTINCT mrch FROM stg_transac WHERE mcg_id = 35) t35
JOIN (SELECT DISTINCT mrch FROM stg_transac WHERE mcg_id BETWEEN 1 AND 25) tv
  ON t35.mrch = tv.mrch;

-- F) Patrones de fecha en el dato crudo
SELECT regexp_replace(trim(prch_date), '[0-9]', '9', 'g') AS patron,
       COUNT(*) AS n, MIN(prch_date) AS ejemplo_min, MAX(prch_date) AS ejemplo_max
FROM raw_transac GROUP BY 1 ORDER BY n DESC;

-- G) Identificación de día y mes por formato
SELECT regexp_replace(trim(prch_date), '[0-9]', '9', 'g') AS patron,
       MAX(CAST(split_part(norm_fecha(prch_date),'-',1) AS INT)) AS max_parte1_dia,
       MAX(CAST(split_part(norm_fecha(prch_date),'-',2) AS INT)) AS max_parte2_mes
FROM raw_transac GROUP BY 1;

-- H) Resultado de normalización por formato de origen
SELECT prch_date_fmt_origen,
       COUNT(*) AS n,
       COUNT(*) FILTER (WHERE prch_date IS NULL) AS invalidas,
       MIN(prch_date) AS fecha_min, MAX(prch_date) AS fecha_max
FROM stg_transac GROUP BY 1;

-- I) Nulos o vacíos en todas las columnas del dato crudo
UNPIVOT (
  SELECT
    COUNT(*) FILTER (WHERE card_id        IS NULL OR trim(card_id)        = '') AS card_id,
    COUNT(*) FILTER (WHERE product_name   IS NULL OR trim(product_name)   = '') AS product_name,
    COUNT(*) FILTER (WHERE product_type   IS NULL OR trim(product_type)   = '') AS product_type,
    COUNT(*) FILTER (WHERE amt            IS NULL OR trim(amt)            = '') AS amt,
    COUNT(*) FILTER (WHERE is_xb          IS NULL OR trim(is_xb)          = '') AS is_xb,
    COUNT(*) FILTER (WHERE is_contactless IS NULL OR trim(is_contactless) = '') AS is_contactless,
    COUNT(*) FILTER (WHERE prch_date      IS NULL OR trim(prch_date)      = '') AS prch_date,
    COUNT(*) FILTER (WHERE prch_time      IS NULL OR trim(prch_time)      = '') AS prch_time,
    COUNT(*) FILTER (WHERE ctry_card      IS NULL OR trim(ctry_card)      = '') AS ctry_card,
    COUNT(*) FILTER (WHERE ctry_mrch      IS NULL OR trim(ctry_mrch)      = '') AS ctry_mrch,
    COUNT(*) FILTER (WHERE mrch           IS NULL OR trim(mrch)           = '') AS mrch,
    COUNT(*) FILTER (WHERE mcg_id         IS NULL OR trim(mcg_id)         = '') AS mcg_id
  FROM raw_transac
) ON COLUMNS(*) INTO NAME columna VALUE nulos_o_vacios;