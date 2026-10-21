-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 05 – Análise: respostas às perguntas de negócio
-- MAGIC
-- MAGIC **Problema:** para quem abastece, a pergunta prática é **onde, quando e com qual combustível se gasta menos?**
-- MAGIC
-- MAGIC **Hipótese:** as diferenças de preço entre regiões, bandeiras e combustíveis são grandes o suficiente para justificar uma decisão de abastecimento orientada por dados.
-- MAGIC
-- MAGIC | # | Pergunta | Decisão que apoia |
-- MAGIC |---|---|---|
-- MAGIC | 1 | Quais estados têm o maior e o menor preço médio de gasolina e etanol, e qual a diferença? | **Onde** abastecer |
-- MAGIC | 2 | Postos de bandeira branca são mais baratos que os das grandes distribuidoras? | **Em qual posto** abastecer |
-- MAGIC | 3 | Como o preço evoluiu mês a mês e quando houve as maiores variações? | **Quando** abastecer |
-- MAGIC | 4 | Em quais estados o etanol compensou (≤ 70% do preço da gasolina), e em quantos meses? | **Com qual combustível** abastecer |
-- MAGIC | 5 | Os postos repassam reduções com a mesma velocidade que repassam aumentos? | Quanto **esperar** por uma redução |
-- MAGIC
-- MAGIC Todas as consultas usam o **esquema estrela** da camada Gold: a fato (`gold_fato_preco`) ligada às dimensões por JOIN.
-- MAGIC
-- MAGIC **Gráficos:** depois de rodar cada consulta, clique no **+** ao lado de "Table" → **Visualization**, e configure como indicado em cada passo (📊).

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC # Pergunta 1 – Onde abastecer?
-- MAGIC **Quais estados tiveram o maior e o menor preço médio de gasolina comum e de etanol em 2025, e qual a diferença percentual entre esses extremos?**
-- MAGIC
-- MAGIC **Como calculamos:** média de todos os preços coletados em cada estado, separada por produto.

-- COMMAND ----------

-- 1a) Preço médio de gasolina e etanol em cada estado
SELECT
  l.uf,                                                                          -- estado
  l.regiao,                                                                      -- região
  -- AVG(CASE ...) calcula a média só das linhas do produto indicado; as outras viram nulo e são ignoradas
  ROUND(AVG(CASE WHEN p.produto = 'GASOLINA' THEN f.valor_venda END), 2) AS gasolina,
  ROUND(AVG(CASE WHEN p.produto = 'ETANOL'   THEN f.valor_venda END), 2) AS etanol
FROM workspace.combustiveis.gold_fato_preco  AS f
JOIN workspace.combustiveis.gold_dim_local   AS l ON f.id_local   = l.id_local
JOIN workspace.combustiveis.gold_dim_produto AS p ON f.id_produto = p.id_produto
WHERE p.produto IN ('GASOLINA', 'ETANOL')        -- só os dois produtos da pergunta
GROUP BY l.uf, l.regiao                          -- uma linha por estado
ORDER BY gasolina DESC                           -- do estado mais caro para o mais barato

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 📊 **Gráfico:** tipo **Bar** · eixo X: `uf` · eixo Y: `gasolina` e `etanol` (média) · ordenar pelo eixo Y.

-- COMMAND ----------

-- 1b) Estado mais caro, mais barato e a diferença entre eles
WITH media_uf AS (
  -- Parte 1: preço médio de cada produto em cada estado
  SELECT
    p.produto,
    l.uf,
    AVG(f.valor_venda) AS preco_medio
  FROM workspace.combustiveis.gold_fato_preco  AS f
  JOIN workspace.combustiveis.gold_dim_local   AS l ON f.id_local   = l.id_local
  JOIN workspace.combustiveis.gold_dim_produto AS p ON f.id_produto = p.id_produto
  WHERE p.produto IN ('GASOLINA', 'ETANOL')
  GROUP BY p.produto, l.uf
),
extremos AS (
  -- Parte 2: para cada produto, acha o estado de maior e de menor preço
  SELECT
    produto,
    MAX_BY(uf, preco_medio) AS uf_mais_cara,     -- MAX_BY: devolve a UF onde o preço é máximo
    MAX(preco_medio)        AS preco_mais_caro,
    MIN_BY(uf, preco_medio) AS uf_mais_barata,   -- MIN_BY: devolve a UF onde o preço é mínimo
    MIN(preco_medio)        AS preco_mais_barato
  FROM media_uf
  GROUP BY produto
)
-- Parte 3: calcula as diferenças
SELECT
  produto,
  uf_mais_cara,
  ROUND(preco_mais_caro, 2)                                            AS preco_mais_caro,
  uf_mais_barata,
  ROUND(preco_mais_barato, 2)                                          AS preco_mais_barato,
  ROUND(preco_mais_caro - preco_mais_barato, 2)                        AS diferenca_reais_litro,
  ROUND(100 * (preco_mais_caro - preco_mais_barato) / preco_mais_barato, 1) AS diferenca_percentual,
  -- Impacto para o consumidor: diferença em um tanque de 50 litros
  ROUND((preco_mais_caro - preco_mais_barato) * 50, 2)                 AS diferenca_tanque_50_litros
FROM extremos

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Discussão – Pergunta 1
-- MAGIC
-- MAGIC | Produto | Estado mais caro | Estado mais barato | Diferença por litro | Diferença % | Diferença em um tanque de 50 L |
-- MAGIC |---|---|---|---|---|---|
-- MAGIC | Gasolina comum | AC – R$ 7,67 | PI – R$ 5,93 | R$ 1,75 | **29,5%** | **R$ 87,28** |
-- MAGIC | Etanol | AC – R$ 5,45 | MS – R$ 4,08 | R$ 1,37 | **33,6%** | **R$ 68,60** |
-- MAGIC
-- MAGIC **Resposta:** o **Acre** é o estado mais caro nos dois combustíveis. A gasolina mais barata está no **Piauí** e o etanol mais barato no **Mato Grosso do Sul**. A diferença entre os extremos passa de **29%**, o equivalente a quase **R$ 90 em um único tanque** de gasolina.
-- MAGIC
-- MAGIC **Interpretação:**
-- MAGIC - A **região Norte** concentra os preços mais altos de gasolina: os quatro estados mais caros são AC, AM, RR e RO. O padrão é compatível com o custo logístico de levar combustível a locais mais distantes dos centros de refino e distribuição.
-- MAGIC - O **etanol** é mais barato justamente nos estados produtores do Centro-Sul (**MS, SP, MT e MG**, os quatro mais baratos), o que indica o peso da proximidade das usinas no preço final.
-- MAGIC - O **Amapá** é um caso curioso: tem a 3ª gasolina mais barata do país (R$ 6,04), mas um dos etanóis mais caros (R$ 5,43). Isso volta a aparecer na pergunta 4.
-- MAGIC
-- MAGIC **Cuidado na leitura:** as médias são simples (cada preço coletado tem o mesmo peso) e vêm de uma **amostra** de 419 municípios pesquisados pela ANP. Elas representam bem os municípios da pesquisa, mas não necessariamente todo o território de cada estado.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC # Pergunta 2 – Em qual posto abastecer?
-- MAGIC **Postos de bandeira branca praticam preços menores que os postos de grandes distribuidoras? Qual é a diferença média?**
-- MAGIC
-- MAGIC **Como calculamos:** comparamos o preço médio dos três tipos de bandeira (regra de negócio G2: branca, grande distribuidora e outras).
-- MAGIC
-- MAGIC **Cuidado:** uma média nacional pode enganar. Se os postos de bandeira branca estiverem concentrados em estados mais baratos, eles pareceriam mais baratos só por causa da **localização** (efeito composição).
-- MAGIC Por isso fazemos também a comparação **dentro de cada estado** (consulta 2b).

-- COMMAND ----------

-- 2a) Preço médio por tipo de bandeira, para cada produto (comparação nacional)
WITH medias AS (
  SELECT
    p.produto,
    AVG(CASE WHEN b.tipo_bandeira = 'BANDEIRA BRANCA'       THEN f.valor_venda END) AS branca,
    AVG(CASE WHEN b.tipo_bandeira = 'GRANDE DISTRIBUIDORA'  THEN f.valor_venda END) AS grande_distribuidora,
    AVG(CASE WHEN b.tipo_bandeira = 'OUTRAS DISTRIBUIDORAS' THEN f.valor_venda END) AS outras
  FROM workspace.combustiveis.gold_fato_preco   AS f
  JOIN workspace.combustiveis.gold_dim_bandeira AS b ON f.id_bandeira = b.id_bandeira
  JOIN workspace.combustiveis.gold_dim_produto  AS p ON f.id_produto  = p.id_produto
  GROUP BY p.produto
)
SELECT
  produto,
  ROUND(branca, 3)                                              AS branca,
  ROUND(grande_distribuidora, 3)                                AS grande_distribuidora,
  ROUND(outras, 3)                                              AS outras,
  -- Diferença positiva = a bandeira branca é mais barata
  ROUND(grande_distribuidora - branca, 3)                       AS diferenca_reais,
  ROUND(100 * (grande_distribuidora - branca) / branca, 2)      AS diferenca_percentual
FROM medias
ORDER BY produto

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 📊 **Gráfico:** tipo **Bar** · eixo X: `produto` · eixo Y: `branca`, `grande_distribuidora` e `outras` · agrupamento lado a lado.

-- COMMAND ----------

-- 2b) Comparação dentro de cada estado (gasolina comum)
-- TEMP VIEW: uma "tabela temporária" que só existe enquanto o notebook está aberto.
-- Usamos para reaproveitar o mesmo cálculo em duas consultas.
CREATE OR REPLACE TEMP VIEW bandeira_por_uf AS
SELECT
  l.uf,
  AVG(CASE WHEN b.tipo_bandeira = 'BANDEIRA BRANCA'      THEN f.valor_venda END) AS branca,
  AVG(CASE WHEN b.tipo_bandeira = 'GRANDE DISTRIBUIDORA' THEN f.valor_venda END) AS grande_distribuidora
FROM workspace.combustiveis.gold_fato_preco   AS f
JOIN workspace.combustiveis.gold_dim_local    AS l ON f.id_local    = l.id_local
JOIN workspace.combustiveis.gold_dim_bandeira AS b ON f.id_bandeira = b.id_bandeira
JOIN workspace.combustiveis.gold_dim_produto  AS p ON f.id_produto  = p.id_produto
WHERE p.produto = 'GASOLINA'
GROUP BY l.uf

-- COMMAND ----------

-- Diferença entre grande distribuidora e bandeira branca em cada estado
SELECT
  uf,
  ROUND(branca, 2)                        AS branca,
  ROUND(grande_distribuidora, 2)          AS grande_distribuidora,
  ROUND(grande_distribuidora - branca, 2) AS diferenca_reais,   -- positivo = branca mais barata
  CASE WHEN branca < grande_distribuidora
       THEN 'BRANCA MAIS BARATA'
       ELSE 'BRANCA MAIS CARA OU IGUAL' END AS resultado
FROM bandeira_por_uf
ORDER BY diferenca_reais DESC

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 📊 **Gráfico:** tipo **Bar** · eixo X: `uf` · eixo Y: `diferenca_reais`. Barras positivas = estados onde a bandeira branca é mais barata.

-- COMMAND ----------

-- Resumo: em quantos estados a bandeira branca é mais barata?
SELECT
  COUNT(*)                                       AS estados_comparados,
  COUNT_IF(branca < grande_distribuidora)        AS estados_branca_mais_barata,  -- COUNT_IF conta onde a condição é verdadeira
  ROUND(AVG(grande_distribuidora - branca), 3)   AS diferenca_media_entre_estados
FROM bandeira_por_uf
WHERE branca IS NOT NULL
  AND grande_distribuidora IS NOT NULL           -- só estados que têm os dois tipos de posto

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Discussão – Pergunta 2
-- MAGIC
-- MAGIC **Comparação nacional (consulta 2a):** a bandeira branca é mais barata em **5 dos 6 produtos**:
-- MAGIC
-- MAGIC | Produto | Branca | Grande distribuidora | Diferença | % |
-- MAGIC |---|---|---|---|---|
-- MAGIC | Gasolina comum | R$ 6,119 | R$ 6,303 | R$ 0,184 | 3,0% |
-- MAGIC | Gasolina aditivada | R$ 6,238 | R$ 6,527 | R$ 0,289 | 4,6% |
-- MAGIC | Etanol | R$ 4,341 | R$ 4,497 | R$ 0,156 | 3,6% |
-- MAGIC | Diesel S10 | R$ 6,090 | R$ 6,282 | R$ 0,193 | 3,2% |
-- MAGIC | Diesel | R$ 6,047 | R$ 6,214 | R$ 0,168 | 2,8% |
-- MAGIC | GNV | R$ 4,783 | R$ 4,716 | −R$ 0,067 | −1,4% (branca mais cara) |
-- MAGIC
-- MAGIC **Comparação dentro de cada estado (consulta 2b, gasolina comum):** a bandeira branca é mais barata em **20 dos 27 estados**, mas a diferença média entre estados é de apenas **R$ 0,061 por litro**, três vezes menor que a diferença nacional (R$ 0,184).
-- MAGIC
-- MAGIC **Por que os dois números são diferentes?** A média nacional dá mais peso aos estados com mais preços coletados. São Paulo, por exemplo, tem muitos postos na amostra e uma das maiores vantagens da bandeira branca (R$ 0,35). Isso "puxa" a média nacional para cima. Quando cada estado conta igualmente, a vantagem típica é bem menor. Esse é o **efeito composição** que motivou a consulta 2b.
-- MAGIC
-- MAGIC **Resposta:** **sim, na maioria dos casos** a bandeira branca é mais barata, cerca de **3% no país** (R$ 9,20 por tanque de 50 L de gasolina). Mas **não é uma regra**: em 7 estados ela é igual ou mais cara, com destaque para o **Amazonas**, onde é R$ 0,57 mais cara. Fora SP, MS, PA, PR e MT, a vantagem fica abaixo de R$ 0,15 por litro.
-- MAGIC
-- MAGIC **Limitação:** a comparação mostra **associação**, não causa. Outros fatores que a base não registra, como a localização do posto dentro da cidade ou os serviços oferecidos, também podem influenciar o preço.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC # Pergunta 3 – Quando abastecer?
-- MAGIC **Como o preço médio evoluiu mês a mês em 2025 e em quais meses ocorreram as maiores variações?**
-- MAGIC
-- MAGIC **Como calculamos:** preço médio nacional de cada mês para gasolina comum, etanol e diesel S10. Depois comparamos cada mês com o anterior usando `LAG`.

-- COMMAND ----------

-- Preço médio mensal de cada produto (guardado em uma TEMP VIEW para reaproveitar)
CREATE OR REPLACE TEMP VIEW preco_mensal AS
SELECT
  t.ano_mes,                          -- mês (ex.: 2025-06)
  p.produto,                          -- combustível
  AVG(f.valor_venda) AS preco_medio   -- preço médio do mês
FROM workspace.combustiveis.gold_fato_preco  AS f
JOIN workspace.combustiveis.gold_dim_tempo   AS t ON f.data       = t.data
JOIN workspace.combustiveis.gold_dim_produto AS p ON f.id_produto = p.id_produto
WHERE p.produto IN ('GASOLINA', 'ETANOL', 'DIESEL S10')
GROUP BY t.ano_mes, p.produto

-- COMMAND ----------

-- 3a) Evolução mês a mês
SELECT
  ano_mes,
  produto,
  ROUND(preco_medio, 3) AS preco_medio
FROM preco_mensal
ORDER BY produto, ano_mes

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 📊 **Gráfico:** tipo **Line** · eixo X: `ano_mes` · eixo Y: `preco_medio` · agrupar por (Group by): `produto`.

-- COMMAND ----------

-- Variação de cada mês em relação ao mês anterior
CREATE OR REPLACE TEMP VIEW variacao_mensal AS
SELECT
  ano_mes,
  produto,
  preco_medio,
  -- LAG busca o valor da linha anterior (o mês anterior do mesmo produto)
  preco_medio - LAG(preco_medio) OVER (PARTITION BY produto ORDER BY ano_mes)             AS variacao_reais,
  100 * (preco_medio / LAG(preco_medio) OVER (PARTITION BY produto ORDER BY ano_mes) - 1) AS variacao_percentual
FROM preco_mensal

-- COMMAND ----------

-- 3b) As 5 maiores variações mensais (altas ou baixas)
SELECT
  ano_mes,
  produto,
  ROUND(variacao_reais, 3)      AS variacao_reais,
  ROUND(variacao_percentual, 2) AS variacao_percentual
FROM variacao_mensal
WHERE variacao_percentual IS NOT NULL      -- janeiro não tem mês anterior
ORDER BY ABS(variacao_percentual) DESC     -- ABS: tamanho da variação, sem olhar o sinal
LIMIT 5

-- COMMAND ----------

-- 3c) Variação acumulada no ano: dezembro em relação a janeiro
SELECT
  produto,
  ROUND(MAX(CASE WHEN ano_mes = '2025-01' THEN preco_medio END), 3) AS janeiro,
  ROUND(MAX(CASE WHEN ano_mes = '2025-12' THEN preco_medio END), 3) AS dezembro,
  ROUND(100 * (MAX(CASE WHEN ano_mes = '2025-12' THEN preco_medio END)
             / MAX(CASE WHEN ano_mes = '2025-01' THEN preco_medio END) - 1), 2) AS variacao_no_ano_percentual
FROM preco_mensal
GROUP BY produto
ORDER BY produto

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Discussão – Pergunta 3
-- MAGIC
-- MAGIC **Resposta:** o ano teve **um único movimento forte, em fevereiro**, seguido de uma queda lenta até o meio do ano e estabilidade no segundo semestre.
-- MAGIC
-- MAGIC | Período | O que aconteceu |
-- MAGIC |---|---|
-- MAGIC | **Fevereiro** | Os três produtos tiveram a maior alta do ano: diesel S10 **+4,74%**, etanol **+4,05%** e gasolina **+2,96%**. São as três maiores variações mensais de 2025 |
-- MAGIC | **Março a agosto** | Queda gradual. A gasolina voltou de R$ 6,367 (fevereiro) para R$ 6,182 (agosto), praticamente o nível de janeiro. O diesel S10 caiu até junho (R$ 6,094), com a maior queda do ano em maio (**−2,40%**) |
-- MAGIC | **Setembro a dezembro** | Gasolina e diesel estáveis (variações abaixo de 0,5% ao mês). O etanol voltou a subir, com alta de **+1,94%** em dezembro |
-- MAGIC
-- MAGIC **Variação acumulada no ano (dezembro × janeiro):** gasolina **+0,31%**, etanol **+3,70%** e diesel S10 **−1,17%**. Ou seja, apesar das oscilações, o ano terminou praticamente onde começou.
-- MAGIC
-- MAGIC **Interpretação:**
-- MAGIC - A alta de fevereiro coincide com o aumento do ICMS fixo sobre combustíveis em 1º de fevereiro de 2025 (+R$ 0,10/L na gasolina e +R$ 0,06/L no diesel). Mas a alta observada foi **maior** que o imposto (gasolina +R$ 0,18 e diesel S10 +R$ 0,29), e o etanol também subiu. Outros fatores contribuíram, e a base da ANP não permite identificá-los.
-- MAGIC - O movimento do etanol (queda até agosto e alta no fim do ano) é compatível com o calendário da safra de cana, que aumenta a oferta no meio do ano.
-- MAGIC
-- MAGIC **Implicação prática:** fora de fevereiro, as variações mensais ficaram quase sempre abaixo de 1%. Escolher **quando** abastecer teve pouco efeito em 2025, bem menos que escolher **onde** (pergunta 1).
-- MAGIC
-- MAGIC **Limitação:** a análise cobre **um único ano**. Não dá para afirmar que o padrão (alta no início do ano, queda depois) se repete todo ano. Isso exigiria comparar vários anos.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC # Pergunta 4 – Com qual combustível abastecer?
-- MAGIC **Em quais estados o etanol foi economicamente vantajoso em relação à gasolina (relação de preços ≤ 70%) e em quantos meses do ano?**
-- MAGIC
-- MAGIC **Regra dos 70%:** o etanol rende cerca de 70% da gasolina por litro. Por isso, ele só compensa quando custa **até 70% do preço da gasolina**.
-- MAGIC
-- MAGIC **Como calculamos:** para cada estado e cada mês, dividimos o preço médio do etanol pelo da gasolina comum.

-- COMMAND ----------

-- Relação etanol / gasolina por estado e mês
CREATE OR REPLACE TEMP VIEW relacao_etanol_gasolina AS
SELECT
  l.uf,
  t.ano_mes,
  AVG(CASE WHEN p.produto = 'ETANOL'   THEN f.valor_venda END) AS etanol,
  AVG(CASE WHEN p.produto = 'GASOLINA' THEN f.valor_venda END) AS gasolina,
  -- Relação: quanto o etanol custa em proporção à gasolina (0,70 = 70%)
  AVG(CASE WHEN p.produto = 'ETANOL'   THEN f.valor_venda END)
  / AVG(CASE WHEN p.produto = 'GASOLINA' THEN f.valor_venda END) AS relacao
FROM workspace.combustiveis.gold_fato_preco  AS f
JOIN workspace.combustiveis.gold_dim_local   AS l ON f.id_local   = l.id_local
JOIN workspace.combustiveis.gold_dim_tempo   AS t ON f.data       = t.data
JOIN workspace.combustiveis.gold_dim_produto AS p ON f.id_produto = p.id_produto
WHERE p.produto IN ('ETANOL', 'GASOLINA')
GROUP BY l.uf, t.ano_mes

-- COMMAND ----------

-- 4a) Resumo por estado: relação média e meses em que o etanol compensou
SELECT
  uf,
  ROUND(100 * AVG(relacao), 1)       AS relacao_media_percentual,  -- média dos 12 meses, em %
  COUNT_IF(relacao <= 0.70)          AS meses_etanol_vantajoso,    -- meses com relação ≤ 70%
  COUNT(relacao)                     AS meses_com_dados,           -- meses com preço dos dois produtos
  CASE
    WHEN COUNT_IF(relacao <= 0.70) = COUNT(relacao) THEN 'ETANOL COMPENSOU O ANO TODO'
    WHEN COUNT_IF(relacao <= 0.70) > 0              THEN 'ETANOL COMPENSOU EM PARTE DO ANO'
    ELSE 'GASOLINA COMPENSOU O ANO TODO'
  END AS conclusao
FROM relacao_etanol_gasolina
GROUP BY uf
ORDER BY relacao_media_percentual          -- do estado onde o etanol é mais vantajoso para o menos

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 📊 **Gráfico:** tipo **Bar** · eixo X: `uf` · eixo Y: `relacao_media_percentual`. Estados abaixo de 70 = etanol compensa.

-- COMMAND ----------

-- 4b) Quantos estados em cada situação
SELECT
  conclusao,
  COUNT(*) AS qtd_estados,
  CONCAT_WS(', ', SORT_ARRAY(COLLECT_LIST(uf))) AS estados    -- lista dos estados, em ordem
FROM (
  SELECT
    uf,
    CASE
      WHEN COUNT_IF(relacao <= 0.70) = COUNT(relacao) THEN 'ETANOL COMPENSOU O ANO TODO'
      WHEN COUNT_IF(relacao <= 0.70) > 0              THEN 'ETANOL COMPENSOU EM PARTE DO ANO'
      ELSE 'GASOLINA COMPENSOU O ANO TODO'
    END AS conclusao
  FROM relacao_etanol_gasolina
  GROUP BY uf
)
GROUP BY conclusao
ORDER BY qtd_estados DESC

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Discussão – Pergunta 4
-- MAGIC
-- MAGIC | Situação em 2025 | Estados | Qtd. |
-- MAGIC |---|---|---|
-- MAGIC | Etanol compensou **o ano todo** (12 de 12 meses) | MS (65,6%), MT (66,4%), SP (67,4%) | 3 |
-- MAGIC | Etanol compensou **em parte do ano** | PR (10 meses), GO (4), MG (3), DF (1) | 4 |
-- MAGIC | Gasolina compensou **o ano todo** | AC, AL, AM, AP, BA, CE, ES, MA, PA, PB, PE, PI, RJ, RN, RO, RR, RS, SC, SE, TO | 20 |
-- MAGIC
-- MAGIC *(entre parênteses: relação média etanol/gasolina no ano)*
-- MAGIC
-- MAGIC **Resposta:** o etanol foi vantajoso **o ano inteiro em apenas 3 estados** (MS, MT e SP) e **em parte do ano em outros 4** (PR, GO, MG e DF). Em **20 dos 27 estados**, a gasolina foi a melhor escolha em **todos os meses**.
-- MAGIC
-- MAGIC **Interpretação:**
-- MAGIC - Os 7 estados onde o etanol compensou em algum momento ficam todos no **Centro-Sul**, a principal região produtora. É o mesmo padrão da pergunta 1: o etanol é competitivo perto de onde é produzido.
-- MAGIC - O caso extremo é o **Amapá** (90,2%): lá o etanol custa quase o mesmo que a gasolina, o que explica a combinação estranha vista na pergunta 1 (gasolina barata e etanol caro).
-- MAGIC - Em **MG, GO e DF**, a relação média ficou muito perto do limite (70,6% a 71,9%). Nesses estados, a decisão muda de um mês para outro e vale acompanhar os preços.
-- MAGIC
-- MAGIC **Limitação:** os 70% são uma **regra prática**. O rendimento real do etanol varia conforme o modelo do carro e o modo de dirigir. Além disso, usamos médias estaduais mensais: em um posto específico a relação pode ser diferente.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC # Pergunta 5 – Os aumentos chegam mais rápido que as reduções?
-- MAGIC **Os postos repassam as reduções de preço com a mesma velocidade com que repassam os aumentos?**
-- MAGIC
-- MAGIC Esse fenômeno é conhecido como **"foguetes e penas"**: o preço sobe como foguete e desce como pena.
-- MAGIC
-- MAGIC **Como calculamos:** para cada posto, comparamos cada preço de gasolina comum com o preço da **coleta anterior do mesmo posto**.
-- MAGIC Assim medimos quantas vezes o preço subiu, desceu ou ficou igual, e o tamanho médio de cada mudança.
-- MAGIC
-- MAGIC **Limitação (já esperada):** "repasse" é a reação do posto a uma mudança no **custo** dele. A base da ANP tem só o preço de **venda**, sem o preço de compra (a coluna `valor_de_compra` veio vazia) e sem as datas de reajuste das refinarias.
-- MAGIC Por isso, esta análise mostra **como os preços variaram**, mas não consegue provar a **causa** da variação.

-- COMMAND ----------

-- Variação de preço de cada posto entre duas coletas seguidas (gasolina comum)
CREATE OR REPLACE TEMP VIEW variacao_posto AS
SELECT
  f.id_posto,
  f.data,
  f.valor_venda,
  -- Diferença para o preço da coleta anterior do MESMO posto
  f.valor_venda - LAG(f.valor_venda) OVER (PARTITION BY f.id_posto ORDER BY f.data) AS variacao,
  -- Quantos dias se passaram desde a coleta anterior
  DATEDIFF(f.data, LAG(f.data) OVER (PARTITION BY f.id_posto ORDER BY f.data))       AS dias_desde_anterior
FROM workspace.combustiveis.gold_fato_preco  AS f
JOIN workspace.combustiveis.gold_dim_produto AS p ON f.id_produto = p.id_produto
WHERE p.produto = 'GASOLINA'

-- COMMAND ----------

-- 5a) Aumentos × reduções: quantidade e tamanho médio
SELECT
  CASE
    WHEN variacao > 0 THEN 'AUMENTO'
    WHEN variacao < 0 THEN 'REDUCAO'
    ELSE 'SEM MUDANCA'
  END                                                      AS tipo_variacao,
  COUNT(*)                                                 AS qtd,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)         AS percentual,          -- % do total de comparações
  ROUND(AVG(ABS(variacao)), 3)                             AS variacao_media_reais, -- tamanho médio da mudança
  ROUND(AVG(dias_desde_anterior), 1)                       AS intervalo_medio_dias  -- dias entre as duas coletas
FROM variacao_posto
WHERE variacao IS NOT NULL                                 -- a primeira coleta de cada posto não tem anterior
GROUP BY ALL
ORDER BY qtd DESC

-- COMMAND ----------

-- 5b) Aumentos e reduções mês a mês
SELECT
  DATE_FORMAT(data, 'yyyy-MM')  AS ano_mes,
  COUNT_IF(variacao > 0)        AS aumentos,
  COUNT_IF(variacao < 0)        AS reducoes,
  ROUND(AVG(variacao), 3)       AS variacao_media_reais    -- positiva = mês de alta, negativa = mês de queda
FROM variacao_posto
WHERE variacao IS NOT NULL
GROUP BY ALL
ORDER BY ano_mes

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 📊 **Gráfico:** tipo **Bar** · eixo X: `ano_mes` · eixo Y: `aumentos` e `reducoes` · lado a lado.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Discussão – Pergunta 5
-- MAGIC
-- MAGIC **O que os dados mostram (consulta 5a):** comparando cada preço de gasolina com a coleta anterior do mesmo posto (203.788 comparações):
-- MAGIC
-- MAGIC | Tipo | Quantidade | % | Tamanho médio da mudança |
-- MAGIC |---|---|---|---|
-- MAGIC | Sem mudança | 155.696 | 76,4% | — |
-- MAGIC | Redução | 27.037 | 13,3% | **R$ 0,146** |
-- MAGIC | Aumento | 21.055 | 10,3% | **R$ 0,197** |
-- MAGIC
-- MAGIC - Os **aumentos são menos frequentes, porém 35% maiores** que as reduções. As reduções acontecem mais vezes, em passos menores.
-- MAGIC - **Mês a mês (consulta 5b):** fevereiro concentrou **5.116 aumentos**, mais que o triplo das reduções (1.422). A volta do preço foi diluída ao longo de **seis meses** (março a agosto), sempre com mais reduções que aumentos.
-- MAGIC - Na média nacional (pergunta 3), a gasolina subiu R$ 0,18 **em um único mês** e levou **seis meses** para voltar ao nível de janeiro.
-- MAGIC
-- MAGIC **Resposta: inconclusiva.** O padrão observado é **compatível** com o fenômeno "foguetes e penas": o aumento veio de uma vez, em degraus grandes, e a redução veio aos poucos, em degraus pequenos. **Porém, não é possível afirmar que os postos repassam as reduções mais devagar**, porque:
-- MAGIC
-- MAGIC 1. **Falta o custo do posto.** "Repasse" é a reação a uma mudança de custo. A coluna `valor_de_compra` veio 100% vazia, e a base não tem os preços das distribuidoras nem as datas de reajuste das refinarias.
-- MAGIC 2. **Sem o custo, não dá para separar as explicações.** A queda lenta de março a agosto pode ser repasse lento ou simplesmente reflexo de um custo que também caiu devagar.
-- MAGIC 3. **A pesquisa não acompanha o posto todo dia.** Cada posto foi coletado, em média, 23 vezes no ano, ou seja, cerca de uma vez a cada duas semanas (análise de qualidade, passo 8), então não dá para medir em quantos **dias** cada mudança aconteceu.
-- MAGIC
-- MAGIC **O que resolveria:** cruzar esta base com uma série de **custo**, como os preços médios de distribuição (também publicados pela ANP) ou o histórico de reajustes da Petrobras. Isso permitiria medir o atraso entre a mudança no custo e a mudança na bomba. Fica como trabalho futuro.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ---
-- MAGIC # Discussão geral
-- MAGIC
-- MAGIC **Problema:** onde, quando e com qual combustível se gasta menos?
-- MAGIC
-- MAGIC **Hipótese:** as diferenças de preço são grandes o suficiente para justificar uma decisão de abastecimento orientada por dados. **A hipótese foi confirmada**, mas cada decisão pesa de um jeito muito diferente.
-- MAGIC
-- MAGIC Para comparar as decisões na mesma unidade, convertemos cada diferença em reais por **tanque de 50 litros de gasolina comum**:
-- MAGIC
-- MAGIC | Decisão | Diferença encontrada | Por tanque de 50 L | Peso |
-- MAGIC |---|---|---|---|
-- MAGIC | **Onde** abastecer (estado mais caro × mais barato) | 29,5% | **R$ 87,28** | Muito alto |
-- MAGIC | **Com qual combustível** | Depende do estado: o etanol compensa só no Centro-Sul | Varia | Alto, mas regional |
-- MAGIC | **Em qual posto** (branca × grande distribuidora) | 3,0% no país; R$ 0,06/L na média dos estados | R$ 3,05 a R$ 9,20 | Moderado |
-- MAGIC | **Quando** (pico de fevereiro × agosto) | 2,9% | R$ 9,25 | Baixo e concentrado em um mês |
-- MAGIC
-- MAGIC **Conclusões:**
-- MAGIC 1. **A localização é o fator dominante.** A diferença entre estados é cerca de dez vezes maior que a de bandeira ou de época do ano. Para quem tem flexibilidade de rota (frotas, transportadoras), planejar **onde** abastecer é a decisão que mais economiza.
-- MAGIC 2. **A escolha do combustível é regional.** No Centro-Sul (MS, MT, SP, PR) o etanol compensa na maior parte do ano; no Norte e no Nordeste, a gasolina compensa sempre. Não existe uma resposta nacional.
-- MAGIC 3. **A bandeira branca costuma ser mais barata, mas não sempre.** A vantagem é real em 20 estados, mas pequena na maioria deles. Vale como critério de desempate, não como regra.
-- MAGIC 4. **O momento importou pouco em 2025.** Houve um único choque (fevereiro), e o restante do ano foi estável.
-- MAGIC 5. **A dinâmica dos preços sugere assimetria** (altas rápidas, quedas lentas), mas a base não permite confirmar a causa. A pergunta 5 ficou sem resposta conclusiva por falta de dados de custo.
-- MAGIC
-- MAGIC **Limitações gerais:** a pesquisa da ANP é uma **amostra** (419 municípios, cerca de 8,7 mil postos), e não um censo. As médias são simples, sem ponderação pelo volume vendido em cada posto. E a análise cobre apenas **2025**.
