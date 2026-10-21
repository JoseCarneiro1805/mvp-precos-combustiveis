-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 04 – Análise de qualidade dos dados
-- MAGIC
-- MAGIC **O que este notebook faz:** verifica se os dados são confiáveis antes de usá-los para responder às perguntas de negócio.
-- MAGIC
-- MAGIC A análise segue as dimensões de qualidade pedidas no trabalho:
-- MAGIC
-- MAGIC | Dimensão | Pergunta que respondemos | Passo |
-- MAGIC |---|---|---|
-- MAGIC | **Completude** | Existem valores faltando? | 1 |
-- MAGIC | **Unicidade** | Existem registros duplicados? | 2 |
-- MAGIC | **Consistência** | As tabelas e os atributos concordam entre si? | 3 e 4 |
-- MAGIC | **Conformidade** | Os valores respeitam o domínio declarado no Catálogo? | 5 |
-- MAGIC | **Acurácia** | Existem valores implausíveis (fora do normal)? | 6 |
-- MAGIC | **Atualidade e cobertura** | Os dados cobrem o ano todo de forma equilibrada? | 7 e 8 |
-- MAGIC
-- MAGIC **Observação:** problemas já tratados no notebook 02 (9.114 linhas em branco, coluna `valor_de_compra` vazia, unidade do GNV escrita de dois jeitos) não aparecem aqui, porque já foram corrigidos. Este notebook confere o resultado **depois** da limpeza.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Passo 1 – Completude: existem valores faltando?
-- MAGIC
-- MAGIC Contamos os nulos de **cada atributo** da Silver, a tabela que contém todos os atributos usados no modelo.
-- MAGIC
-- MAGIC Truque usado: `COUNT(*)` conta todas as linhas e `COUNT(coluna)` conta só as preenchidas. A diferença entre os dois é o número de nulos.
-- MAGIC No final, `UNPIVOT` transforma as colunas em linhas, para o resultado ficar fácil de ler.

-- COMMAND ----------

WITH contagem AS (
  SELECT
    COUNT(*)                          AS total,           -- total de linhas
    COUNT(*) - COUNT(regiao)          AS regiao,          -- nulos em cada coluna
    COUNT(*) - COUNT(uf)              AS uf,
    COUNT(*) - COUNT(municipio)       AS municipio,
    COUNT(*) - COUNT(revenda)         AS revenda,
    COUNT(*) - COUNT(cnpj)            AS cnpj,
    COUNT(*) - COUNT(bandeira)        AS bandeira,
    COUNT(*) - COUNT(produto)         AS produto,
    COUNT(*) - COUNT(unidade)         AS unidade,
    COUNT(*) - COUNT(data_coleta)     AS data_coleta,
    COUNT(*) - COUNT(valor_venda)     AS valor_venda,
    COUNT(*) - COUNT(arquivo_origem)  AS arquivo_origem
  FROM workspace.combustiveis.silver_precos
)
SELECT
  atributo,                                         -- nome da coluna
  nulos,                                            -- quantidade de nulos
  ROUND(100.0 * nulos / total, 2) AS perc_nulos     -- percentual de nulos
FROM contagem
-- UNPIVOT: transforma cada coluna de contagem em uma linha (atributo, nulos)
UNPIVOT (nulos FOR atributo IN (
  regiao, uf, municipio, revenda, cnpj, bandeira, produto,
  unidade, data_coleta, valor_venda, arquivo_origem
))

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Passo 2 – Unicidade: existem registros duplicados?
-- MAGIC
-- MAGIC Para cada tabela, comparamos o **total de linhas** com o **número de chaves diferentes**. Se os dois números forem iguais, não há duplicidade.
-- MAGIC - Nas dimensões, a chave é o código (`id_...` ou `data`) e também o atributo natural (CNPJ, município etc.).
-- MAGIC - Na fato, a chave é o **grão**: posto + produto + dia.

-- COMMAND ----------

SELECT 'gold_dim_tempo'    AS tabela, 'data'              AS chave, COUNT(*) AS linhas, COUNT(DISTINCT data)                AS chaves_distintas FROM workspace.combustiveis.gold_dim_tempo
UNION ALL
SELECT 'gold_dim_local',    'id_local',             COUNT(*), COUNT(DISTINCT id_local)                FROM workspace.combustiveis.gold_dim_local
UNION ALL
SELECT 'gold_dim_local',    'uf + municipio',       COUNT(*), COUNT(DISTINCT uf, municipio)           FROM workspace.combustiveis.gold_dim_local
UNION ALL
SELECT 'gold_dim_produto',  'id_produto',           COUNT(*), COUNT(DISTINCT id_produto)              FROM workspace.combustiveis.gold_dim_produto
UNION ALL
SELECT 'gold_dim_posto',    'id_posto',             COUNT(*), COUNT(DISTINCT id_posto)                FROM workspace.combustiveis.gold_dim_posto
UNION ALL
SELECT 'gold_dim_posto',    'cnpj',                 COUNT(*), COUNT(DISTINCT cnpj)                    FROM workspace.combustiveis.gold_dim_posto
UNION ALL
SELECT 'gold_dim_bandeira', 'id_bandeira',          COUNT(*), COUNT(DISTINCT id_bandeira)             FROM workspace.combustiveis.gold_dim_bandeira
UNION ALL
SELECT 'gold_fato_preco',   'posto + produto + dia', COUNT(*), COUNT(DISTINCT id_posto, id_produto, data) FROM workspace.combustiveis.gold_fato_preco

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Passo 3 – Consistência entre tabelas (integridade referencial)
-- MAGIC
-- MAGIC Todo código da fato precisa existir na dimensão correspondente. Um código sem par é chamado de **órfão**.
-- MAGIC Usamos `LEFT JOIN`: ele mantém todas as linhas da fato, e quando não acha o par na dimensão, o lado da dimensão fica nulo. Contamos esses nulos.

-- COMMAND ----------

SELECT
  COUNT(*) AS linhas_fato,                                                    -- total da fato
  SUM(CASE WHEN t.data        IS NULL THEN 1 ELSE 0 END) AS orfaos_tempo,     -- data sem par
  SUM(CASE WHEN l.id_local    IS NULL THEN 1 ELSE 0 END) AS orfaos_local,     -- local sem par
  SUM(CASE WHEN p.id_produto  IS NULL THEN 1 ELSE 0 END) AS orfaos_produto,   -- produto sem par
  SUM(CASE WHEN po.id_posto   IS NULL THEN 1 ELSE 0 END) AS orfaos_posto,     -- posto sem par
  SUM(CASE WHEN b.id_bandeira IS NULL THEN 1 ELSE 0 END) AS orfaos_bandeira   -- bandeira sem par
FROM workspace.combustiveis.gold_fato_preco AS f
LEFT JOIN workspace.combustiveis.gold_dim_tempo    AS t  ON f.data        = t.data
LEFT JOIN workspace.combustiveis.gold_dim_local    AS l  ON f.id_local    = l.id_local
LEFT JOIN workspace.combustiveis.gold_dim_produto  AS p  ON f.id_produto  = p.id_produto
LEFT JOIN workspace.combustiveis.gold_dim_posto    AS po ON f.id_posto    = po.id_posto
LEFT JOIN workspace.combustiveis.gold_dim_bandeira AS b  ON f.id_bandeira = b.id_bandeira

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Passo 4 – Consistência entre atributos
-- MAGIC
-- MAGIC Alguns atributos precisam "concordar" entre si:
-- MAGIC - cada **estado** pertence a uma única **região**;
-- MAGIC - cada **posto** (CNPJ) fica em um único **município**.
-- MAGIC
-- MAGIC Verificamos também quantos postos **mudaram de nome** ou **trocaram de bandeira** durante o ano. Isso não é erro, mas confirma a decisão de modelar a bandeira em uma dimensão separada do posto.

-- COMMAND ----------

-- Estados que aparecem em mais de uma região (o esperado é nenhum)
SELECT
  uf,
  COUNT(DISTINCT regiao) AS qtd_regioes     -- em quantas regiões o estado aparece
FROM workspace.combustiveis.silver_precos
GROUP BY uf
HAVING COUNT(DISTINCT regiao) > 1           -- mostra só os inconsistentes

-- COMMAND ----------

SELECT
  COUNT(*) AS total_postos,                                                             -- postos (CNPJs) na base
  SUM(CASE WHEN qtd_municipios > 1 THEN 1 ELSE 0 END) AS postos_em_mais_de_1_municipio,  -- inconsistência
  SUM(CASE WHEN qtd_nomes      > 1 THEN 1 ELSE 0 END) AS postos_que_mudaram_de_nome,     -- informativo
  SUM(CASE WHEN qtd_bandeiras  > 1 THEN 1 ELSE 0 END) AS postos_que_trocaram_bandeira    -- informativo
FROM (
  -- Subconsulta: para cada CNPJ, conta quantos municípios, nomes e bandeiras diferentes ele teve
  SELECT
    cnpj,
    COUNT(DISTINCT uf, municipio) AS qtd_municipios,
    COUNT(DISTINCT revenda)       AS qtd_nomes,
    COUNT(DISTINCT bandeira)      AS qtd_bandeiras
  FROM workspace.combustiveis.silver_precos
  GROUP BY cnpj
)

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Passo 5 – Conformidade: os valores respeitam o domínio?
-- MAGIC
-- MAGIC Conferimos cada regra de domínio declarada no **Catálogo de Dados**. Em todas as colunas `fora_...`, o resultado esperado é **zero**.

-- COMMAND ----------

SELECT
  -- Região deve ser uma das 5 siglas
  SUM(CASE WHEN regiao NOT IN ('N', 'NE', 'CO', 'SE', 'S') THEN 1 ELSE 0 END)  AS fora_regiao,

  -- Devem existir exatamente 27 UFs
  COUNT(DISTINCT uf)                                                           AS qtd_ufs,

  -- CNPJ deve ter exatamente 14 dígitos
  SUM(CASE WHEN LENGTH(cnpj) <> 14 THEN 1 ELSE 0 END)                          AS fora_cnpj_14_digitos,

  -- Data deve estar dentro de 2025
  SUM(CASE WHEN YEAR(data_coleta) <> 2025 THEN 1 ELSE 0 END)                   AS fora_ano_2025,

  -- Data deve combinar com o semestre do arquivo de origem
  SUM(CASE WHEN (arquivo_origem LIKE '%2025.01%' AND MONTH(data_coleta) > 6)
             OR (arquivo_origem LIKE '%2025.02%' AND MONTH(data_coleta) <= 6)
           THEN 1 ELSE 0 END)                                                  AS fora_semestre_do_arquivo,

  -- Unidade deve ser litro ou m³
  SUM(CASE WHEN unidade NOT IN ('R$ / litro', 'R$ / m³') THEN 1 ELSE 0 END)    AS fora_unidade,

  -- Só o GNV pode ser vendido em m³ (e o GNV só em m³)
  SUM(CASE WHEN (produto = 'GNV') <> (unidade = 'R$ / m³') THEN 1 ELSE 0 END)  AS fora_produto_x_unidade,

  -- Preço deve ser positivo
  SUM(CASE WHEN valor_venda <= 0 THEN 1 ELSE 0 END)                            AS fora_preco_positivo

FROM workspace.combustiveis.silver_precos

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Passo 6 – Acurácia: existem preços implausíveis?
-- MAGIC
-- MAGIC Usamos a **regra do boxplot (intervalo interquartil)**, um critério estatístico clássico:
-- MAGIC 1. **Q1** = preço abaixo do qual estão 25% dos valores; **Q3** = preço abaixo do qual estão 75%.
-- MAGIC 2. **IQR** = Q3 − Q1 (a "largura" da faixa central dos preços).
-- MAGIC 3. São considerados **atípicos** os preços abaixo de `Q1 − 1,5 × IQR` ou acima de `Q3 + 1,5 × IQR`.
-- MAGIC
-- MAGIC O cálculo é feito **por produto**, porque cada combustível tem uma faixa de preço diferente.

-- COMMAND ----------

-- Parte 1: calcula Q1 e Q3 de cada produto
WITH quartis AS (
  SELECT
    p.produto,
    PERCENTILE_APPROX(f.valor_venda, 0.25) AS q1,   -- 1º quartil
    PERCENTILE_APPROX(f.valor_venda, 0.75) AS q3    -- 3º quartil
  FROM workspace.combustiveis.gold_fato_preco  AS f
  JOIN workspace.combustiveis.gold_dim_produto AS p ON f.id_produto = p.id_produto
  GROUP BY p.produto
),

-- Parte 2: calcula os limites inferior e superior
limites AS (
  SELECT
    produto,
    q1,
    q3,
    q1 - 1.5 * (q3 - q1) AS limite_inferior,
    q3 + 1.5 * (q3 - q1) AS limite_superior
  FROM quartis
)

-- Parte 3: conta quantos preços ficam fora dos limites
SELECT
  li.produto,
  li.q1,
  li.q3,
  ROUND(li.limite_inferior, 2) AS limite_inferior,
  ROUND(li.limite_superior, 2) AS limite_superior,
  SUM(CASE WHEN f.valor_venda < li.limite_inferior THEN 1 ELSE 0 END) AS atipicos_abaixo,
  SUM(CASE WHEN f.valor_venda > li.limite_superior THEN 1 ELSE 0 END) AS atipicos_acima,
  ROUND(100.0 * SUM(CASE WHEN f.valor_venda < li.limite_inferior
                          OR f.valor_venda > li.limite_superior THEN 1 ELSE 0 END)
        / COUNT(*), 2) AS perc_atipicos
FROM workspace.combustiveis.gold_fato_preco  AS f
JOIN workspace.combustiveis.gold_dim_produto AS p  ON f.id_produto = p.id_produto
JOIN limites                                 AS li ON p.produto    = li.produto
GROUP BY li.produto, li.q1, li.q3, li.limite_inferior, li.limite_superior
ORDER BY li.produto

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Os preços atípicos são erros ou são reais?
-- MAGIC
-- MAGIC Um valor fora do normal **não é necessariamente um erro**. Olhamos os 10 maiores preços de gasolina comum para ver **onde** eles aconteceram.
-- MAGIC Se estiverem em locais de difícil acesso (onde o frete encarece o combustível), são preços reais e devem ser mantidos.

-- COMMAND ----------

SELECT
  l.regiao,
  l.uf,
  l.municipio,
  f.data,
  f.valor_venda
FROM workspace.combustiveis.gold_fato_preco  AS f
JOIN workspace.combustiveis.gold_dim_local   AS l ON f.id_local   = l.id_local
JOIN workspace.combustiveis.gold_dim_produto AS p ON f.id_produto = p.id_produto
WHERE p.produto = 'GASOLINA'          -- só gasolina comum
ORDER BY f.valor_venda DESC           -- do maior para o menor
LIMIT 10                              -- só os 10 maiores

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Passo 7 – Atualidade e cobertura no tempo
-- MAGIC
-- MAGIC As perguntas 3 e 4 comparam meses. Para isso funcionar, **todos os meses precisam ter volume de coleta parecido**.
-- MAGIC Um mês com poucos dados teria uma média menos confiável.

-- COMMAND ----------

SELECT
  t.ano_mes,                                     -- mês
  COUNT(DISTINCT t.data)      AS dias_com_coleta, -- em quantos dias houve coleta
  COUNT(*)                    AS qtd_precos,      -- quantos preços foram coletados
  COUNT(DISTINCT f.id_posto)  AS qtd_postos       -- quantos postos diferentes
FROM workspace.combustiveis.gold_fato_preco AS f
JOIN workspace.combustiveis.gold_dim_tempo  AS t ON f.data = t.data
GROUP BY t.ano_mes
ORDER BY t.ano_mes

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Passo 8 – Frequência de observação do mesmo posto
-- MAGIC
-- MAGIC A pergunta 5 (velocidade de repasse de altas e baixas) exige acompanhar **o mesmo posto ao longo do tempo**.
-- MAGIC Aqui medimos quantas vezes cada combinação **posto + produto** foi coletada no ano.
-- MAGIC Se a maioria aparece poucas vezes, não dá para medir a "velocidade" de mudança de preço de cada posto.

-- COMMAND ----------

SELECT
  COUNT(*)                                          AS combinacoes_posto_produto,  -- pares posto + produto
  ROUND(AVG(vezes), 1)                              AS media_coletas_no_ano,       -- média de coletas por par
  PERCENTILE_APPROX(vezes, 0.5)                     AS mediana_coletas_no_ano,     -- metade dos pares tem até este número
  MIN(vezes)                                        AS minimo,
  MAX(vezes)                                        AS maximo,
  SUM(CASE WHEN vezes = 1 THEN 1 ELSE 0 END)        AS coletados_uma_unica_vez,   -- pares vistos só uma vez
  SUM(CASE WHEN vezes >= 12 THEN 1 ELSE 0 END)      AS coletados_12_vezes_ou_mais -- ao menos ~1 vez por mês
FROM (
  -- Subconsulta: quantas vezes cada posto + produto foi coletado no ano
  SELECT
    id_posto,
    id_produto,
    COUNT(*) AS vezes
  FROM workspace.combustiveis.gold_fato_preco
  GROUP BY id_posto, id_produto
)

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Conclusões da análise de qualidade
-- MAGIC
-- MAGIC | Dimensão | Resultado | Decisão |
-- MAGIC |---|---|---|
-- MAGIC | Completude | 0 nulos em todos os 11 atributos | Nenhuma ação necessária |
-- MAGIC | Unicidade | Todas as chaves são únicas; nenhum posto + produto + dia repetido na fato | Nenhuma ação necessária |
-- MAGIC | Consistência entre tabelas | 0 códigos órfãos na fato | Nenhuma ação necessária |
-- MAGIC | Consistência entre atributos | Nenhum estado em mais de uma região. 3 postos (0,03%) aparecem em mais de um município | Mantidos: impacto desprezível, e cada preço fica ligado ao município registrado naquele dia |
-- MAGIC | Consistência (informativo) | 109 postos mudaram de nome e 393 trocaram de bandeira no ano | Confirma a decisão de modelar a bandeira em dimensão separada do posto |
-- MAGIC | Conformidade | 0 valores fora do domínio declarado; 27 UFs | Nenhuma ação necessária |
-- MAGIC | Acurácia | De 0,6% (etanol) a 2,6% (GNV) de preços atípicos, quase todos acima do limite superior | **Mantidos**: os maiores preços de gasolina (R$ 9,29 em Barueri/SP) se repetem semana após semana no mesmo local, o que indica preço real, e não erro de digitação |
-- MAGIC | Atualidade e cobertura | Todos os 12 meses cobertos, de 20 a 26 dias de coleta por mês. Agosto tem cerca de 20% menos preços que a média | Agosto ainda tem quase 54 mil preços, volume suficiente para calcular médias confiáveis |
-- MAGIC | Frequência por posto | Cada posto + produto foi coletado em média 23 vezes no ano (mediana 22); 64% foram coletados 12 vezes ou mais | Permite acompanhar a variação de preço de cada posto (pergunta 5) |
-- MAGIC
-- MAGIC **Conclusão geral:** depois da limpeza do notebook 02, a base não apresenta problemas que comprometam as respostas às perguntas de negócio. Os preços atípicos foram mantidos por serem plausíveis e representarem menos de 3% dos registros de cada produto.
