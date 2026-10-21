-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 02 – Transformação e camada Silver
-- MAGIC
-- MAGIC **O que este notebook faz:** pega a tabela Bronze (dado bruto, tudo em texto) e cria a tabela **Silver**: dados **limpos, tipados e sem duplicidade**, prontos para a modelagem.
-- MAGIC
-- MAGIC **Por que SQL?** As regras de limpeza ficam mais fáceis de ler em SQL, e cada regra vira uma linha comentada.
-- MAGIC
-- MAGIC ### Regras de negócio aplicadas
-- MAGIC
-- MAGIC | # | Regra | Motivo |
-- MAGIC |---|---|---|
-- MAGIC | R1 | Tirar espaços sobrando dos textos e transformar texto vazio em nulo | O CNPJ e outros campos vêm com espaço na frente |
-- MAGIC | R2 | Deixar o CNPJ só com números | Padronizar a chave que identifica o posto |
-- MAGIC | R3 | Converter o preço de texto (`"5,59"`) para número (`5.59`) | Sem isso não dá para calcular média |
-- MAGIC | R4 | Converter a data de texto (`19/06/2025`) para data | Permite agrupar por mês |
-- MAGIC | R5 | Descartar a coluna `valor_de_compra` | Coluna sem informação (ver diagnóstico) |
-- MAGIC | R6 | Descartar as colunas de endereço | Não são usadas em nenhuma pergunta (minimização de dados) |
-- MAGIC | R7 | Remover linhas vazias, sem preço, com preço zero ou sem data | Os arquivos da ANP têm 9.114 linhas em branco |
-- MAGIC | R8 | Manter um único preço por posto, produto e dia | Proteção contra preço contado duas vezes (o diagnóstico mostra que hoje não há duplicatas) |
-- MAGIC | R9 | Corrigir o nome do arquivo de origem (`%20` → espaço) | Deixar a linhagem legível |
-- MAGIC | R10 | Padronizar a unidade do GNV (`R$ / m3` → `R$ / m³`) | A mesma unidade aparece escrita de dois jeitos |

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Passo 1 – Diagnóstico da camada Bronze
-- MAGIC
-- MAGIC Antes de limpar, medimos o tamanho de cada problema. Assim, toda regra da tabela acima tem um número que a justifica.

-- COMMAND ----------

SELECT
  -- Total de linhas da tabela Bronze
  COUNT(*) AS total_linhas,

  -- COUNT(coluna) conta só as linhas preenchidas; se der 0, a coluna está vazia (regra R5)
  COUNT(valor_de_compra) AS valor_compra_preenchido,

  -- Linhas em que o preço NÃO consegue virar número (regra R3)
  -- TRY_CAST tenta converter; se não conseguir, devolve nulo em vez de dar erro
  SUM(CASE WHEN TRY_CAST(REPLACE(TRIM(valor_de_venda), ',', '.') AS DECIMAL(6,3)) IS NULL
      THEN 1 ELSE 0 END) AS preco_invalido,

  -- Linhas em que a data NÃO consegue virar data (regra R4)
  SUM(CASE WHEN TRY_TO_TIMESTAMP(TRIM(data_da_coleta), 'dd/MM/yyyy') IS NULL
      THEN 1 ELSE 0 END) AS data_invalida,

  -- Quantidade de produtos e de bandeiras diferentes
  COUNT(DISTINCT produto) AS qtd_produtos,
  COUNT(DISTINCT bandeira) AS qtd_bandeiras

FROM workspace.combustiveis.bronze_precos

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Quais produtos existem na base?
-- MAGIC Mostra cada produto, a unidade de medida e quantos preços foram coletados.

-- COMMAND ----------

SELECT
  produto,                 -- nome do combustível
  unidade_de_medida,       -- R$ / litro ou R$ / m³
  COUNT(*) AS linhas       -- quantidade de preços coletados
FROM workspace.combustiveis.bronze_precos
GROUP BY ALL               -- agrupa por todas as colunas que não são cálculo
ORDER BY linhas DESC       -- do mais coletado para o menos coletado

-- COMMAND ----------

-- MAGIC %md
-- MAGIC **Observação:** o GNV aparece com a unidade escrita de dois jeitos (`R$ / m³` e `R$ / m3`). É a mesma unidade, padronizada pela regra R10.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### O que são as 9.114 linhas inválidas? (regra R7)
-- MAGIC O diagnóstico mostrou 9.114 linhas com preço, data e produto inválidos, sempre o mesmo número.
-- MAGIC A consulta abaixo confirma que são **linhas totalmente em branco** nos arquivos da ANP.

-- COMMAND ----------

SELECT
  arquivo_origem,                    -- em qual arquivo estão as linhas
  COUNT(*) AS linhas_em_branco       -- quantas linhas
FROM workspace.combustiveis.bronze_precos
-- Linha em branco = todos os campos principais vazios ao mesmo tempo
WHERE produto IS NULL
  AND valor_de_venda IS NULL
  AND data_da_coleta IS NULL
  AND cnpj_da_revenda IS NULL
  AND estado_sigla IS NULL
GROUP BY arquivo_origem

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Existem preços repetidos? (regra R8)
-- MAGIC Contamos quantas combinações de **posto + produto + dia** aparecem mais de uma vez, **ignorando as linhas em branco** (que seriam contadas como uma "combinação" repetida milhares de vezes).

-- COMMAND ----------

SELECT
  COUNT(*) AS combinacoes_repetidas,              -- quantas combinações se repetem
  COALESCE(SUM(vezes - 1), 0) AS linhas_excedentes -- quantas linhas sobram além da primeira (0 se não houver)
FROM (
  -- Subconsulta: conta quantas vezes cada combinação aparece
  SELECT
    TRIM(cnpj_da_revenda) AS cnpj,
    produto,
    data_da_coleta,
    COUNT(*) AS vezes
  FROM workspace.combustiveis.bronze_precos
  WHERE produto IS NOT NULL                    -- ignora as linhas em branco
  GROUP BY ALL
  HAVING COUNT(*) > 1                          -- fica só com as que se repetem
)

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Passo 2 – Criar a tabela Silver
-- MAGIC
-- MAGIC A consulta tem duas partes:
-- MAGIC 1. **`limpo`**: aplica as regras R1 a R6, R9 e R10, coluna por coluna;
-- MAGIC 2. **consulta final**: aplica R7 (filtro) e R8 (um preço por posto, produto e dia).
-- MAGIC
-- MAGIC `CREATE OR REPLACE` recria a tabela a cada execução, então o notebook pode rodar quantas vezes for preciso sem duplicar dados.

-- COMMAND ----------

CREATE OR REPLACE TABLE workspace.combustiveis.silver_precos
COMMENT 'Precos de combustiveis ANP 2025 - dados limpos, tipados e sem duplicidade'
AS

-- Parte 1: limpeza coluna por coluna
WITH limpo AS (
  SELECT
    -- R1: TRIM tira espaços das pontas; NULLIF troca texto vazio por nulo
    NULLIF(TRIM(regiao_sigla), '')      AS regiao,
    NULLIF(TRIM(estado_sigla), '')      AS uf,
    NULLIF(TRIM(municipio), '')         AS municipio,
    NULLIF(TRIM(revenda), '')           AS revenda,

    -- R2: remove tudo que não for número (pontos, barra, traço e espaços)
    REGEXP_REPLACE(cnpj_da_revenda, '[^0-9]', '') AS cnpj,

    NULLIF(TRIM(produto), '')           AS produto,

    -- R4: converte "19/06/2025" em data; se não conseguir, fica nulo
    CAST(TRY_TO_TIMESTAMP(TRIM(data_da_coleta), 'dd/MM/yyyy') AS DATE) AS data_coleta,

    -- R3: troca vírgula por ponto ("5,59" -> "5.59") e converte para número com 3 casas decimais
    TRY_CAST(REPLACE(TRIM(valor_de_venda), ',', '.') AS DECIMAL(6,3)) AS valor_venda,

    -- R10: padroniza a unidade do GNV ("m3" vira "m³")
    REPLACE(NULLIF(TRIM(unidade_de_medida), ''), 'm3', 'm³') AS unidade,
    NULLIF(TRIM(bandeira), '')          AS bandeira,

    -- R9: corrige o nome do arquivo de origem (linhagem)
    REPLACE(arquivo_origem, '%20', ' ') AS arquivo_origem

    -- R5 e R6: valor_de_compra e as colunas de endereço (rua, número,
    -- complemento, bairro, CEP) simplesmente não são selecionadas
  FROM workspace.combustiveis.bronze_precos
)

-- Parte 2: filtro e remoção de duplicidade
SELECT
  regiao,
  uf,
  municipio,
  revenda,
  cnpj,
  bandeira,
  produto,
  unidade,
  data_coleta,
  -- R8: se o mesmo posto tiver mais de um preço para o mesmo produto no mesmo dia,
  -- fica a média desses preços (na prática, uma única linha)
  CAST(ROUND(AVG(valor_venda), 3) AS DECIMAL(6,3)) AS valor_venda,
  arquivo_origem
FROM limpo
-- R7: só entram linhas com preço positivo, data válida e CNPJ preenchido
WHERE valor_venda > 0
  AND data_coleta IS NOT NULL
  AND cnpj <> ''
-- R8: agrupa por todas as colunas que não são cálculo (uma linha por posto + produto + dia)
GROUP BY ALL

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Passo 3 – Conferência
-- MAGIC
-- MAGIC Comparamos o tamanho das duas camadas. A diferença deve ser exatamente igual às **9.114 linhas em branco** encontradas no diagnóstico
-- MAGIC (813.731 − 804.617 = 9.114). Isso confirma que nenhuma linha com dado real foi perdida.

-- COMMAND ----------

SELECT 'bronze' AS camada, COUNT(*) AS linhas FROM workspace.combustiveis.bronze_precos
UNION ALL   -- junta o resultado das duas consultas em uma tabela só
SELECT 'silver' AS camada, COUNT(*) AS linhas FROM workspace.combustiveis.silver_precos

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Os tipos ficaram corretos?
-- MAGIC `data_coleta` deve aparecer como **date** e `valor_venda` como **decimal**.

-- COMMAND ----------

-- Mostra cada coluna da tabela Silver e o seu tipo
DESCRIBE TABLE workspace.combustiveis.silver_precos

-- COMMAND ----------

-- Confere a regra R10: o GNV deve aparecer com uma única unidade
SELECT
  produto,            -- nome do combustível
  unidade,            -- unidade já padronizada
  COUNT(*) AS linhas  -- quantidade de preços
FROM workspace.combustiveis.silver_precos
GROUP BY ALL
ORDER BY linhas DESC

-- COMMAND ----------

-- Amostra de 10 linhas para visualizar o dado limpo
SELECT *
FROM workspace.combustiveis.silver_precos
LIMIT 10
