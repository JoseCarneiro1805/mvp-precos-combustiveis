-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 03 – Modelagem e camada Gold (Esquema Estrela)
-- MAGIC
-- MAGIC **O que este notebook faz:** organiza os dados limpos da Silver em um **esquema estrela**, o modelo clássico de Data Warehouse.
-- MAGIC
-- MAGIC **Como funciona o esquema estrela:**
-- MAGIC - No centro fica a **tabela fato**, com o que foi **medido** (o preço) e os códigos que apontam para as dimensões.
-- MAGIC - Em volta ficam as **dimensões**, que descrevem o contexto da medição: **quando**, **onde**, **o quê**, **quem** e **qual bandeira**.
-- MAGIC
-- MAGIC ```
-- MAGIC                 gold_dim_tempo
-- MAGIC                       |
-- MAGIC  gold_dim_local --- gold_fato_preco --- gold_dim_produto
-- MAGIC                    /            \
-- MAGIC        gold_dim_posto          gold_dim_bandeira
-- MAGIC ```
-- MAGIC
-- MAGIC | Tabela | Pergunta que responde | Chave |
-- MAGIC |---|---|---|
-- MAGIC | `gold_fato_preco` | Quanto custou? (um preço por posto, produto e dia) | — |
-- MAGIC | `gold_dim_tempo` | Quando? (dia, mês, semestre, semana) | `data` |
-- MAGIC | `gold_dim_local` | Onde? (região, estado, município) | `id_local` |
-- MAGIC | `gold_dim_produto` | O quê? (combustível e unidade) | `id_produto` |
-- MAGIC | `gold_dim_posto` | Quem vendeu? (CNPJ e nome do posto) | `id_posto` |
-- MAGIC | `gold_dim_bandeira` | De qual distribuidora? | `id_bandeira` |
-- MAGIC
-- MAGIC **Por que separar em tabelas?** Cada informação descritiva fica guardada uma vez só na sua dimensão, e a fato guarda apenas números e códigos. Isso deixa o modelo organizado e as consultas de análise mais simples.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Passo 0 – Apagar a tabela fato antiga
-- MAGIC
-- MAGIC A tabela fato aponta para as dimensões (chaves estrangeiras). Para recriar as dimensões sem conflito, apagamos a fato primeiro. Ela é criada de novo no Passo 6.

-- COMMAND ----------

-- Apaga a tabela fato, se ela existir (permite rodar o notebook várias vezes)
DROP TABLE IF EXISTS workspace.combustiveis.gold_fato_preco

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Passo 1 – Dimensão Tempo (quando?)
-- MAGIC
-- MAGIC Uma linha para cada dia em que houve coleta. A partir da data, criamos colunas prontas para agrupar: ano, mês, semestre e semana.

-- COMMAND ----------

CREATE OR REPLACE TABLE workspace.combustiveis.gold_dim_tempo
COMMENT 'Dimensao tempo: um registro por dia de coleta'
AS
SELECT DISTINCT                                              -- DISTINCT: cada data aparece uma vez só
  data_coleta                              AS data,          -- chave da dimensão
  YEAR(data_coleta)                        AS ano,           -- ex.: 2025
  MONTH(data_coleta)                       AS mes,           -- 1 a 12
  DATE_FORMAT(data_coleta, 'yyyy-MM')      AS ano_mes,       -- ex.: 2025-06 (bom para gráficos)
  CASE WHEN MONTH(data_coleta) <= 6
       THEN 1 ELSE 2 END                   AS semestre,      -- 1º ou 2º semestre
  WEEKOFYEAR(data_coleta)                  AS semana_ano,    -- semana do ano (1 a 53)
  DAYOFWEEK(data_coleta)                   AS dia_semana     -- 1 = domingo ... 7 = sábado
FROM workspace.combustiveis.silver_precos

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Passo 2 – Dimensão Local (onde?)
-- MAGIC
-- MAGIC Uma linha para cada município. O `id_local` é um código numérico criado por nós (**chave substituta**), que a tabela fato usa no lugar do nome do município.

-- COMMAND ----------

CREATE OR REPLACE TABLE workspace.combustiveis.gold_dim_local
COMMENT 'Dimensao local: um registro por municipio'
AS
SELECT
  -- ROW_NUMBER numera as linhas 1, 2, 3...; vira o código do local
  ROW_NUMBER() OVER (ORDER BY uf, municipio) AS id_local,
  regiao,                                    -- N, NE, CO, SE, S
  uf,                                        -- sigla do estado
  municipio                                  -- nome do município
FROM (
  -- Subconsulta: lista cada combinação região + estado + município uma única vez
  SELECT DISTINCT regiao, uf, municipio
  FROM workspace.combustiveis.silver_precos
)

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Passo 3 – Dimensão Produto (o quê?)
-- MAGIC
-- MAGIC Uma linha para cada combustível. Criamos também a coluna `grupo`, que junta variações do mesmo combustível
-- MAGIC (gasolina comum e aditivada → GASOLINA; diesel e diesel S10 → DIESEL).

-- COMMAND ----------

CREATE OR REPLACE TABLE workspace.combustiveis.gold_dim_produto
COMMENT 'Dimensao produto: um registro por combustivel'
AS
SELECT
  ROW_NUMBER() OVER (ORDER BY produto) AS id_produto,   -- código do produto
  produto,                                             -- nome do combustível
  unidade,                                             -- R$ / litro ou R$ / m³
  CASE
    WHEN produto LIKE 'GASOLINA%' THEN 'GASOLINA'      -- LIKE 'GASOLINA%' = começa com GASOLINA
    WHEN produto LIKE 'DIESEL%'   THEN 'DIESEL'
    ELSE produto                                       -- ETANOL e GNV ficam como estão
  END AS grupo
FROM (
  SELECT DISTINCT produto, unidade
  FROM workspace.combustiveis.silver_precos
)

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Passo 4 – Dimensão Posto (quem vendeu?)
-- MAGIC
-- MAGIC Uma linha para cada posto, identificado pelo CNPJ. Se o mesmo CNPJ aparecer com mais de um nome ao longo do ano,
-- MAGIC fica um nome só (`MAX` escolhe o último em ordem alfabética), para que cada posto tenha um único registro.

-- COMMAND ----------

CREATE OR REPLACE TABLE workspace.combustiveis.gold_dim_posto
COMMENT 'Dimensao posto: um registro por CNPJ'
AS
SELECT
  ROW_NUMBER() OVER (ORDER BY cnpj) AS id_posto,   -- código do posto
  cnpj,                                           -- CNPJ só com números
  MAX(revenda) AS revenda                         -- nome do posto (um por CNPJ)
FROM workspace.combustiveis.silver_precos
GROUP BY cnpj                                     -- uma linha por CNPJ

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Passo 5 – Dimensão Bandeira (de qual distribuidora?)
-- MAGIC
-- MAGIC A bandeira fica em uma dimensão separada do posto porque um posto pode **trocar de bandeira** durante o ano.
-- MAGIC
-- MAGIC **Regra de negócio (pergunta 2):** a coluna `tipo_bandeira` classifica as 49 bandeiras em três grupos:
-- MAGIC - **BANDEIRA BRANCA**: posto sem contrato de exclusividade com distribuidora;
-- MAGIC - **GRANDE DISTRIBUIDORA**: as três maiores do país (Vibra, Raízen e Ipiranga);
-- MAGIC - **OUTRAS DISTRIBUIDORAS**: as demais bandeiras.

-- COMMAND ----------

CREATE OR REPLACE TABLE workspace.combustiveis.gold_dim_bandeira
COMMENT 'Dimensao bandeira: um registro por bandeira, com classificacao'
AS
SELECT
  ROW_NUMBER() OVER (ORDER BY bandeira) AS id_bandeira,   -- código da bandeira
  bandeira,                                              -- nome da bandeira
  CASE
    WHEN bandeira = 'BRANCA'                         THEN 'BANDEIRA BRANCA'
    WHEN bandeira IN ('VIBRA', 'RAIZEN', 'IPIRANGA') THEN 'GRANDE DISTRIBUIDORA'
    ELSE 'OUTRAS DISTRIBUIDORAS'
  END AS tipo_bandeira                                   -- classificação usada na pergunta 2
FROM (
  SELECT DISTINCT bandeira
  FROM workspace.combustiveis.silver_precos
)

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Passo 6 – Tabela Fato (quanto custou?)
-- MAGIC
-- MAGIC Cada linha da Silver vira uma linha da fato. Os textos (município, produto, CNPJ, bandeira) são trocados pelos **códigos** das dimensões.
-- MAGIC
-- MAGIC O operador `<=>` funciona como o `=`, mas também considera iguais dois valores nulos. Assim, nenhuma linha se perde no JOIN.

-- COMMAND ----------

CREATE OR REPLACE TABLE workspace.combustiveis.gold_fato_preco
COMMENT 'Fato preco: um preco de venda por posto, produto e dia'
AS
SELECT
  s.data_coleta  AS data,          -- liga com gold_dim_tempo
  l.id_local,                      -- liga com gold_dim_local
  p.id_produto,                    -- liga com gold_dim_produto
  po.id_posto,                     -- liga com gold_dim_posto
  b.id_bandeira,                   -- liga com gold_dim_bandeira
  s.valor_venda                    -- a medida: preço de venda em R$
FROM workspace.combustiveis.silver_precos AS s
-- Busca o código do local comparando região, estado e município
JOIN workspace.combustiveis.gold_dim_local AS l
  ON  s.regiao    <=> l.regiao
  AND s.uf        <=> l.uf
  AND s.municipio <=> l.municipio
-- Busca o código do produto
JOIN workspace.combustiveis.gold_dim_produto AS p
  ON  s.produto <=> p.produto
  AND s.unidade <=> p.unidade
-- Busca o código do posto pelo CNPJ
JOIN workspace.combustiveis.gold_dim_posto AS po
  ON  s.cnpj <=> po.cnpj
-- Busca o código da bandeira
JOIN workspace.combustiveis.gold_dim_bandeira AS b
  ON  s.bandeira <=> b.bandeira

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Passo 7 – Declarar as chaves (primárias e estrangeiras)
-- MAGIC
-- MAGIC - **Chave primária (PK):** a coluna que identifica cada linha de uma dimensão.
-- MAGIC - **Chave estrangeira (FK):** a coluna da fato que aponta para a PK de uma dimensão.
-- MAGIC
-- MAGIC No Databricks essas chaves são **informativas**: documentam o modelo no catálogo e mostram os relacionamentos entre as tabelas.
-- MAGIC Antes de criar a PK, a coluna precisa ser marcada como **não nula** (`SET NOT NULL`).

-- COMMAND ----------

-- Chaves primárias das dimensões
ALTER TABLE workspace.combustiveis.gold_dim_tempo    ALTER COLUMN data        SET NOT NULL;
ALTER TABLE workspace.combustiveis.gold_dim_tempo    ADD CONSTRAINT pk_dim_tempo    PRIMARY KEY (data);

ALTER TABLE workspace.combustiveis.gold_dim_local    ALTER COLUMN id_local    SET NOT NULL;
ALTER TABLE workspace.combustiveis.gold_dim_local    ADD CONSTRAINT pk_dim_local    PRIMARY KEY (id_local);

ALTER TABLE workspace.combustiveis.gold_dim_produto  ALTER COLUMN id_produto  SET NOT NULL;
ALTER TABLE workspace.combustiveis.gold_dim_produto  ADD CONSTRAINT pk_dim_produto  PRIMARY KEY (id_produto);

ALTER TABLE workspace.combustiveis.gold_dim_posto    ALTER COLUMN id_posto    SET NOT NULL;
ALTER TABLE workspace.combustiveis.gold_dim_posto    ADD CONSTRAINT pk_dim_posto    PRIMARY KEY (id_posto);

ALTER TABLE workspace.combustiveis.gold_dim_bandeira ALTER COLUMN id_bandeira SET NOT NULL;
ALTER TABLE workspace.combustiveis.gold_dim_bandeira ADD CONSTRAINT pk_dim_bandeira PRIMARY KEY (id_bandeira);

-- COMMAND ----------

-- Chaves estrangeiras da tabela fato (cada uma aponta para a PK de uma dimensão)
ALTER TABLE workspace.combustiveis.gold_fato_preco ADD CONSTRAINT fk_fato_tempo
  FOREIGN KEY (data)        REFERENCES workspace.combustiveis.gold_dim_tempo (data);

ALTER TABLE workspace.combustiveis.gold_fato_preco ADD CONSTRAINT fk_fato_local
  FOREIGN KEY (id_local)    REFERENCES workspace.combustiveis.gold_dim_local (id_local);

ALTER TABLE workspace.combustiveis.gold_fato_preco ADD CONSTRAINT fk_fato_produto
  FOREIGN KEY (id_produto)  REFERENCES workspace.combustiveis.gold_dim_produto (id_produto);

ALTER TABLE workspace.combustiveis.gold_fato_preco ADD CONSTRAINT fk_fato_posto
  FOREIGN KEY (id_posto)    REFERENCES workspace.combustiveis.gold_dim_posto (id_posto);

ALTER TABLE workspace.combustiveis.gold_fato_preco ADD CONSTRAINT fk_fato_bandeira
  FOREIGN KEY (id_bandeira) REFERENCES workspace.combustiveis.gold_dim_bandeira (id_bandeira);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Passo 8 – Conferência do modelo
-- MAGIC
-- MAGIC 1. A fato deve ter **exatamente** o mesmo número de linhas da Silver (804.617). Se tiver menos, alguma linha se perdeu nos JOINs.
-- MAGIC 2. Tamanho de cada dimensão.

-- COMMAND ----------

SELECT 'silver_precos'     AS tabela, COUNT(*) AS linhas FROM workspace.combustiveis.silver_precos
UNION ALL SELECT 'gold_fato_preco',   COUNT(*) FROM workspace.combustiveis.gold_fato_preco
UNION ALL SELECT 'gold_dim_tempo',    COUNT(*) FROM workspace.combustiveis.gold_dim_tempo
UNION ALL SELECT 'gold_dim_local',    COUNT(*) FROM workspace.combustiveis.gold_dim_local
UNION ALL SELECT 'gold_dim_produto',  COUNT(*) FROM workspace.combustiveis.gold_dim_produto
UNION ALL SELECT 'gold_dim_posto',    COUNT(*) FROM workspace.combustiveis.gold_dim_posto
UNION ALL SELECT 'gold_dim_bandeira', COUNT(*) FROM workspace.combustiveis.gold_dim_bandeira

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Teste do modelo: uma consulta "em estrela"
-- MAGIC A fato é ligada às dimensões para calcular o preço médio da gasolina comum por região. É assim que as consultas de análise vão funcionar.

-- COMMAND ----------

SELECT
  l.regiao,                                       -- região (vem da dimensão local)
  ROUND(AVG(f.valor_venda), 2) AS preco_medio,    -- preço médio (vem da fato)
  COUNT(*) AS qtd_precos                          -- quantos preços entraram na média
FROM workspace.combustiveis.gold_fato_preco AS f
JOIN workspace.combustiveis.gold_dim_local   AS l ON f.id_local   = l.id_local
JOIN workspace.combustiveis.gold_dim_produto AS p ON f.id_produto = p.id_produto
WHERE p.produto = 'GASOLINA'                      -- só gasolina comum
GROUP BY l.regiao
ORDER BY preco_medio DESC                         -- da mais cara para a mais barata

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Passo 9 – Domínios dos dados (para o Catálogo de Dados)
-- MAGIC
-- MAGIC O Catálogo de Dados precisa informar os valores **mínimo e máximo** de cada número e as **categorias possíveis** de cada texto.
-- MAGIC As consultas abaixo levantam essas informações.

-- COMMAND ----------

-- Faixa de preço por produto: mínimo, máximo e média
SELECT
  p.produto,
  p.unidade,
  MIN(f.valor_venda)           AS preco_minimo,
  MAX(f.valor_venda)           AS preco_maximo,
  ROUND(AVG(f.valor_venda), 2) AS preco_medio,
  COUNT(*)                     AS qtd_precos
FROM workspace.combustiveis.gold_fato_preco AS f
JOIN workspace.combustiveis.gold_dim_produto AS p ON f.id_produto = p.id_produto
GROUP BY p.produto, p.unidade
ORDER BY p.produto

-- COMMAND ----------

-- Período coberto pela dimensão tempo
SELECT
  MIN(data)            AS primeira_data,
  MAX(data)            AS ultima_data,
  COUNT(*)             AS dias_com_coleta,
  COUNT(DISTINCT mes)  AS meses
FROM workspace.combustiveis.gold_dim_tempo

-- COMMAND ----------

-- Regiões e quantidade de estados e municípios em cada uma
SELECT
  regiao,
  COUNT(DISTINCT uf)  AS qtd_estados,
  COUNT(*)            AS qtd_municipios,
  CONCAT_WS(', ', SORT_ARRAY(COLLECT_SET(uf))) AS estados   -- lista dos estados, em ordem
FROM workspace.combustiveis.gold_dim_local
GROUP BY regiao
ORDER BY regiao

-- COMMAND ----------

-- Bandeiras, classificação e quantidade de preços de cada uma
SELECT
  b.bandeira,
  b.tipo_bandeira,
  COUNT(*) AS qtd_precos
FROM workspace.combustiveis.gold_fato_preco AS f
JOIN workspace.combustiveis.gold_dim_bandeira AS b ON f.id_bandeira = b.id_bandeira
GROUP BY b.bandeira, b.tipo_bandeira
ORDER BY qtd_precos DESC
