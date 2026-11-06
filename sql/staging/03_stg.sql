-- 03_stg.sql
-- Limpieza y tipado del dato crudo → stg_transac


-- Macros de normalización
CREATE OR REPLACE MACRO norm_txt(s) AS
    regexp_replace(
        lower(strip_accents(trim(
            replace(replace(replace(replace(replace(replace(
                s,
                'Ã©','é'),'Ã¡','á'),'Ãº','ú'),'Ã³','ó'),'Ã­','í'),'Ã±','ñ')
        ))),
        '\s+', ' ', 'g'
    );

CREATE OR REPLACE MACRO norm_pais(s) AS
    CASE norm_txt(s)
        WHEN 'brazil' THEN 'brasil'
        ELSE norm_txt(s)
    END;

CREATE OR REPLACE MACRO norm_fecha(s) AS
    regexp_replace(trim(s), '[/.]', '-', 'g');

-- Tabla staging limpia y tipada
CREATE OR REPLACE TABLE stg_transac AS
SELECT
    trim(card_id)                                               AS card_id,
    norm_txt(product_name)                                      AS product_name,
    CASE lower(trim(product_type))
        WHEN 'credit'   THEN 'credito'
        WHEN 'credito'  THEN 'credito'
        WHEN 'debit'    THEN 'debito'
        WHEN 'debito'   THEN 'debito'
        WHEN 'prepaid'  THEN 'prepago'
        ELSE NULL
    END                                                         AS product_type,
    TRY_CAST(amt AS DECIMAL(18,2))                             AS amt,
    TRY_CAST(trim(is_contactless) AS INT)                      AS is_contactless,
    try_strptime(norm_fecha(prch_date), '%d-%m-%Y')::DATE      AS prch_date,
    regexp_replace(trim(prch_date), '[/.]', '-', 'g')          AS prch_date_fmt_origen,
    TRY_CAST(lpad(replace(trim(prch_time), '.', ':'), 8, '0') AS TIME) AS prch_time,
    norm_pais(ctry_card)                                        AS ctry_card,
    norm_pais(ctry_mrch)                                        AS ctry_mrch,
    norm_txt(mrch)                                              AS mrch,
    TRY_CAST(trim(mcg_id) AS INT)                              AS mcg_id,
    TRY_CAST(trim(is_xb) AS INT)                               AS is_xb_original,
    norm_pais(ctry_card) <> norm_pais(ctry_mrch)               AS is_xb_calc
FROM raw_transac;

-- Verificación
SELECT 'filas_raw' AS check, COUNT(*)::VARCHAR AS valor FROM raw_transac
UNION ALL
SELECT 'filas_stg',          COUNT(*)::VARCHAR FROM stg_transac
UNION ALL
SELECT 'fechas_invalidas',   COUNT(*)::VARCHAR FROM stg_transac WHERE prch_date IS NULL;