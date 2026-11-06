# Masterplop — Desafío Analytics Engineer

**Autor:** Sebastian Diaz  
**Período analizado:** Enero–Junio 2024 (2.400.000 transacciones)  
**Motor:** DuckDB + DBeaver  
**Dashboard Looker Studio (entregable principal):** [Ver en Looker Studio](https://lookerstudio.google.com/reporting/ede77b41-9776-4ed7-9045-4097d306a36a/page/tT0CG)  
**Dashboard HTML (versión alternativa):** [Ver dashboard HTML](https://claude.ai/artifact/X7ZFH3VUKD1zJMJh6XyvaZ)

> El dashboard permite bajar de **trimestre a mes** en los gráficos de volumen y ticket, e incluye filtros por **región** (Sudamérica / Centroamérica / México / Caribe) y **producto** (P1–P5) en el gráfico de ticket regional.

> Todo el SQL está escrito en dialecto DuckDB (usa funciones como `strftime`, `FILTER`, `read_csv` y `GROUP BY` por alias). Para otro motor habría que adaptar estas funciones.

---

## Estructura del repositorio

```
masterplop/
├── sql/
│   ├── raw/
│   │   └── 01_raw.sql          # Carga cruda desde CSV y Excel (todo varchar)
│   ├── dims/
│   │   └── 02_dims.sql         # Dimensiones: 17 países por región, MCG
│   ├── staging/
│   │   └── 03_stg.sql          # Limpieza y tipado → stg_transac
│   ├── marts/
│   │   ├── 09_mart_tarjeta_mes.sql     # Grano tarjeta × mes (base de 10, 11 y del dashboard)
│   │   ├── 10_kpi_volumen.sql
│   │   ├── 11_kpi_ticket_trimestral.sql
│   │   ├── 12_kpi_ticket_regional.sql  # 17 países · 4 regiones · 5 productos
│   │   ├── 13_kpi_top_mcg.sql          # Ranking completo (26 categorías)
│   │   ├── 14_kpi_contactless.sql
│   │   └── 20_cashback_mayo2024.sql
│   └── analysis/
│       ├── 90_validaciones.sql
│       └── 91_exploratorio.sql
├── data/raw/                    # Archivos fuente (excluidos del repo — ver .gitignore)
├── assets/                      # Logo Masterplop
└── README.md
```

Orden de ejecución: `01` → `02` → `03` → `09` → `10`–`14` → `20`. Los archivos `90` y `91` son diagnósticos opcionales.

Para el dashboard, los marts se exportaron a CSV desde DBeaver y se importaron a Google Sheets, que es la fuente de datos de Looker Studio.

---

## Decisiones de limpieza y preprocesamiento

### Arquitectura de capas
Se adoptó una arquitectura en tres capas inspirada en dbt:
- **raw**: carga directa desde los archivos fuente, todo en `VARCHAR` para no perder datos con casteos prematuros.
- **dims**: tablas de dimensión estables (`dim_pais` con clasificación regional, `dim_mcg` desde el maestro Excel).
- **stg**: dato limpio y tipado (`stg_transac`), único punto de verdad para todos los KPIs.

### Normalización de texto
Se creó la macro `norm_txt` que aplica en cadena: corrección de mojibake UTF-8 (`Ã©`→`é`, etc.), `strip_accents`, `lower` y colapso de espacios múltiples. Se añadió `norm_pais` para resolver el alias geográfico `brazil`→`brasil`.

### Fechas: dos formatos en el crudo
El campo `prch_date` llegó en dos formatos mezclados: `dd/mm/yyyy` (1.919.104 filas) y `dd-mm-yyyy` (480.896 filas). La macro `norm_fecha` unifica el separador a `-` antes del parseo con `try_strptime('%d-%m-%Y')`. Resultado: **0 fechas inválidas**.

### Zona horaria
El archivo no incluye zona horaria. Para el cashback de mayo, las tarjetas son exclusivamente chilenas (UTC-3 en invierno 2024), por lo que la fecha local coincide con la fecha del dato. Los trimestres se calculan exclusivamente sobre `prch_date` (campo DATE), eliminando cualquier ambigüedad horaria. Se midió el impacto máximo de borde de mes en la query K: **480 tarjetas** (1,2% de la base elegible), un margen acotado y documentado.

### Montos negativos
Existen 2.400 registros con `amt < 0` (0,1% del total). Los montos negativos pueden representar reversas o devoluciones en cualquier tipo de producto — en crédito son notas de crédito que reducen la deuda, en débito y prepago son abonos por devolución de compra. La decisión fue **conservarlos en `stg_transac`** para no perder trazabilidad. Se excluyen con `amt > 0` en los KPIs de gasto y en el cashback, ya que el enunciado define la campaña sobre "compras realizadas en comercios", no sobre movimientos netos. El servicio es de tarjetas (no wallet), por lo que no existe lógica de saldo acumulado que justifique incluirlos.

### `is_xb`: original vs. calculado
Se cuestionó si sobreescribir el campo `is_xb` original o agregar uno nuevo. La decisión fue **no sobreescribir**: se conservó `is_xb_original` intacto y se agregó `is_xb_calc = (ctry_card <> ctry_mrch)` como columna adicional. Esto permite auditar la discrepancia (1.440.451 filas inconsistentes, 60%) sin destruir el dato original. El cashback usa `ctry_mrch <> 'chile'` según el enunciado; la query de sensibilidad confirma que `ctry_mrch` e `is_xb_calc` producen el mismo resultado.

### MCG 35
El maestro `mcg_list.xlsx` contiene MCG del 1 al 25. Se encontró un MCG con id `35`. Se planteó la pregunta de qué hacer: ¿eliminarlo, reasignarlo, o investigarlo? La decisión fue **investigarlo primero**:
- 12.000 transacciones (0,5%), distribuidas uniformemente por mes, país y tipo de producto → no es error de carga puntual.
- Gasto positivo de USD 2.174.917 (0,51% del total), que lo ubica en el **puesto 17 de 26**, por encima de 9 categorías catalogadas. (Incluyendo montos negativos, el neto es USD 2.172.188.)
- Sus 4.176 comercios también aparecen con MCG válidos → no se puede reasignar con certeza (el nombre de comercio no es clave única de negocio).
- **Decisión final:** se etiqueta como `'mcg no catalogado (35)'` en el KPI de top MCG y se documenta. No se elimina ni reasigna.

### Grano tarjeta × mes para el dashboard
Los gráficos de volumen y ticket permiten bajar de trimestre a mes en Looker Studio. Para eso se creó `mart_tarjeta_mes` (una fila por tarjeta, mes y tipo de producto) en vez de guardar conteos ya calculados: el número de tarjetas distintas **no es aditivo**, porque una tarjeta activa en abril, mayo y junio se contaría 3 veces si se suman los meses.
- Looker calcula `COUNT_DISTINCT(card_id)` y `SUM(gasto_positivo) / COUNT_DISTINCT(card_id)` al nivel que el usuario elija.
- Los KPIs 10 y 11 también leen de este mart, para que SQL y dashboard tengan una **fuente única**.
- Se validó que a nivel trimestral el resultado es idéntico al cálculo original sobre `stg_transac` (46.747 / 51.037 tarjetas crédito; USD 3.232,46 / 5.024,57).
- Como el mart incluye crédito y débito, el gráfico de ticket aplica el filtro `product_type = 'credito'` en el dashboard.

### Top MCG: ranking completo
`mart_kpi_top_mcg` guarda las 26 categorías (25 del maestro + MCG 35). El top 10 se filtra al consultar y en el dashboard, para no perder el detalle del resto y poder ampliar el ranking sin modificar el SQL.

### Adopción contactless: limitación del dato
El KPI de adopción contactless muestra el **porcentaje de gasto** donde `is_contactless = 1`. Es importante señalar que este campo viene del dato fuente y no es posible validar su veracidad desde el dataset — no existe una fuente secundaria que permita cruzarlo. El KPI refleja fielmente el dato disponible, pero en producción se recomendaría validar con el sistema de procesamiento de pagos.

---

## Resultados KPIs

### Volumen de tarjetas por trimestre
| Trimestre | Tipo | Tarjetas |
|---|---|---|
| 2024-Q1 | crédito | 46.747 |
| 2024-Q1 | débito | 8.224 |
| 2024-Q2 | crédito | 51.037 |
| 2024-Q2 | débito | 8.960 |

Crecimiento uniforme de ~9% en ambos tipos de Q1 a Q2. Sin tarjetas prepago en el período.

### Ticket trimestral (crédito)
| Trimestre | Ticket promedio USD |
|---|---|
| 2024-Q1 | 3.232,46 |
| 2024-Q2 | 5.024,57 |

El aumento del 55% en Q2 es consistente con la campaña de cashback de mayo 2024, que incentivó compras internacionales de mayor monto en tarjetas chilenas.

### Ticket regional (crédito) — 17 países · 4 regiones
Escala consistente P1→P5 en todos los países y regiones. El mart incluye todas las regiones presentes en `dim_pais`:

| Región | Países | Ticket mediana P1 | Ticket mediana P5 |
|---|---|---|---|
| Sudamérica | 9 | ~$65 | ~$970 |
| Centroamérica | 6 | ~$65 | ~$972 |
| Norteamérica (México) | 1 | $65.47 | $954.29 |
| Caribe (Rep. Dom.) | 1 | $65.14 | $977.75 |

> **Nota:** la versión original del KPI 12 filtraba solo Sudamérica (`dp.region = 'sudamerica'`). Se corrigió para incluir todas las regiones, exponiendo `region` como columna en el mart. Resultado: 85 filas (17 países × 5 productos). En el dashboard, el filtro de región parte en Sudamérica, que es lo que pide el KPI.

### Top 10 MCG por gasto
| # | MCG | % gasto |
|---|---|---|
| 1 | groceries and supermarkets | 22,16% |
| 2 | restaurants and dining | 17,12% |
| 3 | entertainment | 13,40% |
| 4 | travel and transportation | 10,33% |
| 5 | clothing and accessories | 8,11% |
| 6 | electronics and appliances | 6,33% |
| 7 | health and wellness | 4,93% |
| 8 | home improvement | 3,82% |
| 9 | automotive | 2,97% |
| 10 | education and books | 2,31% |

Los top 10 concentran el **91,50%** del gasto total. La tabla `mart_kpi_top_mcg` guarda el ranking completo (26 categorías); el top 10 se filtra al consultar y en el dashboard. MCG 35 (no catalogado) ocupa el puesto 17 con 0,51%.

### Adopción contactless
Rango estrecho: **63–65%** en todos los países. El Salvador lidera (65,09%) y Guatemala cierra (63,25%). La adopción es homogénea entre mercados. Limitación: el campo `is_contactless` no puede validarse contra una fuente secundaria desde este dataset.

---

## Campaña Cashback Mayo 2024

### Criterio de elegibilidad
Tarjetas de **crédito** con `ctry_card = 'chile'` que realizaron compras con `ctry_mrch <> 'chile'` entre el 1 y el 31 de mayo de 2024, con `amt > 0`. Se excluyen montos negativos por representar reversas o devoluciones, no compras.

### Lógica del cálculo
El 7% se calcula sobre el **gasto acumulado por tarjeta durante mayo** (no por transacción individual). El tope de USD 50 se aplica sobre ese total mensual:

```sql
cashback_final = LEAST(SUM(amt) * 0.07, 50)
```

### Resultados
| Métrica | Valor |
|---|---|
| Tarjetas impactadas | 4.029 |
| Tarjetas que llegaron al tope | 2.681 (66%) |
| **Costo total para Masterplop** | **USD 178.608,88** |
| Costo sin tope (hipotético) | USD 512.908,27 |
| Ahorro gracias al tope | USD 334.299,39 (65%) |
| Cashback promedio por tarjeta | USD 44,33 |

El tope de USD 50 fue determinante: sin él el costo hubiera sido **2,87x mayor**.

### Validación de criterio
La sensibilidad entre usar `ctry_mrch <> 'chile'` (criterio del enunciado) vs. `is_xb_calc = TRUE` produce el **mismo resultado**: 4.029 tarjetas en ambos casos, confirmando la robustez del criterio. El costo en esa query es USD 178.608,19; la diferencia de USD 0,69 con el resultado oficial se debe solo a que la query de sensibilidad no redondea el cashback de cada tarjeta antes de sumar.

---

## Hallazgos adicionales

### Dos segmentos de mercado
Se detectaron dos grupos de países con niveles de gasto sistemáticamente distintos:
- **Grupo A** (Brasil, Argentina, Chile, México, Colombia): mediana ~USD 100.
- **Grupo B** (resto): mediana ~USD 39.

La brecha es de ~2,6x y es consistente dentro de cada producto (P1 a P5) y en el mix de productos (~15% premium en ambos grupos), lo que descarta diferencias de moneda y sugiere segmentos de mercado distintos.

### Moneda: USD
Los montos se tratan como USD. Las medianas por país y producto son coherentes con valores en dólares y no con monedas locales de alta denominación.

---

## Cómo reproducir

```bash
# 1. Abrir DBeaver y conectar a masterplop.duckdb
# 2. Ejecutar en orden:
sql/raw/01_raw.sql        # ajustar ruta del archivo fuente si es necesario
sql/dims/02_dims.sql
sql/staging/03_stg.sql
sql/marts/09_mart_tarjeta_mes.sql
sql/marts/10_kpi_volumen.sql
sql/marts/11_kpi_ticket_trimestral.sql
sql/marts/12_kpi_ticket_regional.sql
sql/marts/13_kpi_top_mcg.sql
sql/marts/14_kpi_contactless.sql
sql/marts/20_cashback_mayo2024.sql
# 3. Exportar los marts a CSV desde DBeaver e importarlos a Google Sheets (fuente de Looker Studio)
```

---

## AI Log

Usé Claude como asistente durante el desarrollo. Documento aquí los momentos donde la IA fue útil y, más importante, donde tomé decisiones distintas a lo que sugirió o detecté problemas en lo propuesto.

### Decisiones propias que difirieron de la IA

**MCG 35: investigar antes de descartar**
Decisión Propia: ¿qué hago con un MCG que no está en el maestro? La IA presentó opciones. Decidí investigarlo antes de cualquier acción: 12.000 transacciones distribuidas uniformemente por mes, país y producto, con 4.176 comercios que también aparecen con MCG válidos. La conclusión de no reasignar se basa en que el nombre de comercio no es clave única de negocio — adoptar una reasignación automática habría sido un error.

**Montos negativos: conservar con criterio**
Decisión Propia: conservarlos en staging para trazabilidad, excluirlos solo donde el enunciado habla de "compras". No eliminarlos del dato base.

**`is_xb`: no sobreescribir**
Decisión Propia. Decidí agregar `is_xb_calc` en paralelo para poder auditar la discrepancia del 60% sin destruir el dato original.

**Zona horaria: medir el impacto en vez de asumir**
La IA sugirió no convertir a UTC. Cuestioné esa decisión y pedí cuantificar el riesgo. Diseñamos la query K juntos: 480 tarjetas en el borde de mayo. Con esa evidencia tomé la decisión informada de no convertir, documentando el margen de error.

**KPI 12: cobertura regional completa**
La versión inicial del mart filtraba solo Sudamérica. Noté que la `dim_pais` incluía 17 países en 4 regiones y que el filtro dejaba fuera Centroamérica, México y Caribe. Corregí el query para exponer `region` como columna y cubrir los 17 países, sin duplicar marts por región.

**Top MCG: no perder el ranking completo**
El mart guardaba solo el top 10 (`WHERE ranking <= 10` dentro del `CREATE TABLE`). Cuestioné que así nadie podría ver la categoría 11 en adelante. Moví el filtro fuera de la tabla: el mart guarda las 26 categorías y el top 10 se filtra al consultar y en el dashboard. Esto dejó visible que el MCG 35 ocupa el puesto 17, por encima de 9 categorías catalogadas.

**Corrección del % del top 10**
Después de guardar el ranking completo, revisé los resultados contra el README para confirmar que el MCG 35 estuviera bien documentado. En esa revisión apareció que la suma de los 10 primeros no cuadraba con el 92,28% del README. Lo verifiqué con una query en DuckDB: el valor correcto es **91,50%**. Corregí el README y el dashboard.

**Drill-down mes/trimestre en el dashboard**
Decisión Propia: poder subir y bajar entre trimestre y mes, como en QuickSight. Propuse pasar los marts a nivel mensual para que Looker los agregue a trimestre. La IA advirtió que el conteo de tarjetas distintas no es aditivo (una tarjeta activa en 3 meses se contaría 3 veces). Se creó `mart_tarjeta_mes` a grano tarjeta × mes, guardando `card_id`, y los KPIs 10 y 11 pasaron a leer de ese mart como fuente única.

**Ticket que no cuadraba en Looker**
Al migrar el gráfico, el ticket dio 2.903 / 4.515 en vez de 3.232 / 5.025. Las primeras hipótesis de la IA (formato de números en Sheets) no eran: yo ya había corregido la configuración regional antes de importar. Pedí una query que calculara el ticket con 4 combinaciones de filtros. El resultado mostró que faltaba el filtro de crédito: el mart nuevo incluye débito, a diferencia del original que ya venía filtrado en SQL. También mostró que el filtro `gasto_positivo > 0` no cambia el resultado.

**Consistencia y legibilidad del SQL**
Pedí reemplazar `GROUP BY 1, 2` por nombres de columna en todos los marts. Cuando la IA agregó un CTE extra en el 09 para hacerlo "portable", cuestioné el aumento de código. Se concluyó que el repo ya es dialecto DuckDB (`strftime`, `FILTER`, `read_csv`), así que se volvió a la versión corta con `GROUP BY` por alias. Única excepción: en el 12 se agrupa por `t.ctry_mrch`, porque el alias `pais` sería ambiguo con la columna `pais` de `dim_pais`.

**Colores de marca estrictos**
La primera paleta propuesta para el dashboard incluía colores fuera de la marca (verde, azul marino). Exigí usar solo los 3 colores del desafío (#1A56DB, #FBBF24, #7C3AED) más neutros. Los 5 productos del ticket regional se diferencian con tintes de esos mismos colores.

**Adopción contactless: honestidad sobre limitaciones**
Noté que el KPI de contactless no se puede validar desde el dataset. Decidí documentar esa limitación en el README en vez de presentar el número como verdad absoluta.

### Prompts que desbloquearon problemas técnicos

- **Error de parser en DBeaver con UNION ALL:** DBeaver divide statements en UNION ALL dentro de paréntesis. Solución: reescribir con CTE + FULL OUTER JOIN.
- **Dos formatos de fecha mezclados:** macro `norm_fecha` para unificar separadores antes del parseo. Resultado: 0 fechas inválidas sobre 2,4M filas.
- **Cashback con tope por tarjeta:** `LEAST(SUM(amt) * 0.07, 50)` con GROUP BY card_id — el tope aplica sobre el acumulado mensual, no por transacción.
- **Mojibake en nombres de países:** cadena de `replace()` para corregir encoding UTF-8 mal interpretado antes de normalizar.
- **Conteo de tarjetas en Looker daba billones:** Looker leyó `card_id` como número y lo sumaba. Solución: tipo Texto y agregación "Recuento distintivo".
- **Drill-down mostraba meses apilados:** `mes` estaba en "Dimensión de desglose" en vez de en "Dimensión: eje X" bajo `trimestre`. Al moverlo, funcionaron las flechas para subir y bajar de nivel.
- **Looker Studio no se conecta a DuckDB:** los marts se exportan a CSV desde DBeaver y se importan a Google Sheets como fuente del dashboard.