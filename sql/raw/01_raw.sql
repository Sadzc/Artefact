-- 01_raw.sql
-- Carga original desde archivos fuente. En VARCHAR

CREATE OR REPLACE TABLE raw_transac AS
SELECT *
FROM read_csv(
    'C:/Users/ldrub/Desktop/Artefacts/db_transac.csv',
    header = true,
    all_varchar = true
);

LOAD excel;

CREATE OR REPLACE TABLE dim_mcg AS
SELECT
    CAST(mcg AS INT)       AS mcg,
    lower(trim(mcg_name))  AS mcg_name
FROM read_xlsx('C:/Users/ldrub/Desktop/Artefacts/mcg_list.xlsx');