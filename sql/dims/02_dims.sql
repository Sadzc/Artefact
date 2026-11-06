-- 02_dims.sql
-- Dimensión de países con clasificación regional

CREATE OR REPLACE TABLE dim_pais AS
SELECT pais, region FROM (VALUES
    ('argentina',           'sudamerica'),
    ('bolivia',             'sudamerica'),
    ('brasil',              'sudamerica'),
    ('chile',               'sudamerica'),
    ('colombia',            'sudamerica'),
    ('ecuador',             'sudamerica'),
    ('paraguay',            'sudamerica'),
    ('peru',                'sudamerica'),
    ('uruguay',             'sudamerica'),
    ('mexico',              'norteamerica'),
    ('guatemala',           'centroamerica'),
    ('honduras',            'centroamerica'),
    ('el salvador',         'centroamerica'),
    ('nicaragua',           'centroamerica'),
    ('costa rica',          'centroamerica'),
    ('panama',              'centroamerica'),
    ('republica dominicana','caribe')
) AS t(pais, region);

SELECT * FROM dim_pais ORDER BY region, pais;