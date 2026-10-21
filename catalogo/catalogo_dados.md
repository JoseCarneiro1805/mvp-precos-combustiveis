# Catálogo de Dados

Descrição de todas as tabelas da camada **Gold** (esquema estrela), usadas na análise.
Todas ficam no Databricks, no schema `workspace.combustiveis`.

**Fonte de todos os dados:** ANP – Série Histórica de Preços de Combustíveis, Combustíveis Automotivos, 1º e 2º semestres de 2025 (arquivos `ca-2025-01.zip` e `ca-2025-02.zip`), coletados em 21/10/2026. Licença CC-BY.

**Caminho dos dados (linhagem geral):**
`arquivos .zip da ANP` → `volume raw` → `bronze_precos` (notebook 01) → `silver_precos` (notebook 02) → tabelas `gold_` (notebook 03)

**Como ler a coluna "Linhagem":** indica a coluna de origem no arquivo da ANP e as regras aplicadas. As regras R1 a R10 estão descritas na seção 4 do README e no notebook 02.

---

## gold_fato_preco

Tabela fato. **Grão:** um preço de venda por posto, produto e dia de coleta. **Linhas:** 804.617.

| Atributo | Tipo | Descrição | Domínio | Obrigatoriedade | Linhagem |
|---|---|---|---|---|---|
| `data` | data | Dia em que o preço foi coletado | 01/01/2025 a 31/12/2025 | Obrigatório | `Data da Coleta` (texto dd/mm/aaaa) → convertido para data (R4). Chave estrangeira para `gold_dim_tempo` |
| `id_local` | inteiro | Código do município onde fica o posto | 1 a 419 | Obrigatório | Gerado no notebook 03 a partir de região + UF + município. Chave estrangeira para `gold_dim_local` |
| `id_produto` | inteiro | Código do combustível | 1 a 6 | Obrigatório | Gerado no notebook 03 a partir de produto + unidade. Chave estrangeira para `gold_dim_produto` |
| `id_posto` | inteiro | Código do posto | 1 a 8.706 | Obrigatório | Gerado no notebook 03 a partir do CNPJ. Chave estrangeira para `gold_dim_posto` |
| `id_bandeira` | inteiro | Código da bandeira do posto no dia da coleta | 1 a 49 | Obrigatório | Gerado no notebook 03 a partir da bandeira. Chave estrangeira para `gold_dim_bandeira` |
| `valor_venda` | numérico (decimal 6,3) | Preço de venda ao consumidor, em reais por litro (ou por m³ no GNV) | Mínimo R$ 3,090 e máximo R$ 9,590. Faixa por produto na tabela abaixo | Obrigatório. Linhas sem preço foram removidas (R7) | `Valor de Venda` (texto com vírgula) → vírgula trocada por ponto e convertido para número (R3) |

**Faixa de `valor_venda` por produto:**

| Produto | Unidade | Mínimo | Máximo | Média | Qtd. de preços |
|---|---|---|---|---|---|
| DIESEL | R$ / litro | 5,24 | 8,39 | 6,15 | 85.969 |
| DIESEL S10 | R$ / litro | 4,73 | 9,29 | 6,21 | 144.541 |
| ETANOL | R$ / litro | 3,09 | 7,44 | 4,46 | 177.753 |
| GASOLINA | R$ / litro | 4,99 | 9,29 | 6,25 | 212.423 |
| GASOLINA ADITIVADA | R$ / litro | 5,19 | 9,59 | 6,45 | 165.691 |
| GNV | R$ / m³ | 3,39 | 6,49 | 4,74 | 18.240 |

---

## gold_dim_tempo

Dimensão de tempo. **Grão:** um registro por dia em que houve coleta. **Linhas:** 274 (a pesquisa da ANP não coleta todos os dias do ano).

| Atributo | Tipo | Descrição | Domínio | Obrigatoriedade | Linhagem |
|---|---|---|---|---|---|
| `data` | data | Dia de coleta (chave primária) | 01/01/2025 a 31/12/2025 | Obrigatório, único | `Data da Coleta` → convertido para data (R4) |
| `ano` | inteiro | Ano da coleta | 2025 | Obrigatório | Calculado: `YEAR(data)` |
| `mes` | inteiro | Mês da coleta | 1 a 12 | Obrigatório | Calculado: `MONTH(data)` |
| `ano_mes` | texto | Ano e mês no formato aaaa-mm | 2025-01 a 2025-12 | Obrigatório | Calculado: `DATE_FORMAT(data, 'yyyy-MM')` |
| `semestre` | inteiro | Semestre da coleta | 1 ou 2 | Obrigatório | Calculado: 1 se mês ≤ 6, senão 2 |
| `semana_ano` | inteiro | Semana do ano | 1 a 53 | Obrigatório | Calculado: `WEEKOFYEAR(data)` |
| `dia_semana` | inteiro | Dia da semana | 1 (domingo) a 7 (sábado) | Obrigatório | Calculado: `DAYOFWEEK(data)` |

---

## gold_dim_local

Dimensão de localização. **Grão:** um registro por município. **Linhas:** 419.

| Atributo | Tipo | Descrição | Domínio | Obrigatoriedade | Linhagem |
|---|---|---|---|---|---|
| `id_local` | inteiro | Código do município (chave primária) | 1 a 419 | Obrigatório, único | Gerado no notebook 03 com `ROW_NUMBER`, em ordem de UF e município |
| `regiao` | categórico | Sigla da região do país | N, NE, CO, SE, S | Obrigatório | `Regiao - Sigla` → espaços removidos (R1) |
| `uf` | categórico | Sigla do estado | 27 UFs: AC, AL, AM, AP, BA, CE, DF, ES, GO, MA, MG, MS, MT, PA, PB, PE, PI, PR, RJ, RN, RO, RR, RS, SC, SE, SP, TO | Obrigatório | `Estado - Sigla` → espaços removidos (R1) |
| `municipio` | texto | Nome do município, em maiúsculas e sem acento (como publicado pela ANP) | 419 municípios pesquisados | Obrigatório | `Municipio` → espaços removidos (R1) |

**Distribuição por região:**

| Região | Estados | Municípios |
|---|---|---|
| CO | DF, GO, MS, MT | 29 |
| N | AC, AM, AP, PA, RO, RR, TO | 31 |
| NE | AL, BA, CE, MA, PB, PE, PI, RN, SE | 91 |
| S | PR, RS, SC | 77 |
| SE | ES, MG, RJ, SP | 191 |

---

## gold_dim_produto

Dimensão de produto. **Grão:** um registro por combustível. **Linhas:** 6.

| Atributo | Tipo | Descrição | Domínio | Obrigatoriedade | Linhagem |
|---|---|---|---|---|---|
| `id_produto` | inteiro | Código do combustível (chave primária) | 1 a 6 | Obrigatório, único | Gerado no notebook 03 com `ROW_NUMBER`, em ordem de produto |
| `produto` | categórico | Nome do combustível | DIESEL, DIESEL S10, ETANOL, GASOLINA, GASOLINA ADITIVADA, GNV | Obrigatório | `Produto` → espaços removidos (R1) |
| `unidade` | categórico | Unidade de medida do preço | R$ / litro, R$ / m³ (só GNV) | Obrigatório | `Unidade de Medida` → espaços removidos (R1) e `m3` padronizado para `m³` (R10) |
| `grupo` | categórico | Agrupamento do combustível | GASOLINA (comum + aditivada), DIESEL (comum + S10), ETANOL, GNV | Obrigatório | Calculado no notebook 03 a partir de `produto` |

---

## gold_dim_posto

Dimensão de posto revendedor. **Grão:** um registro por CNPJ. **Linhas:** 8.706.

| Atributo | Tipo | Descrição | Domínio | Obrigatoriedade | Linhagem |
|---|---|---|---|---|---|
| `id_posto` | inteiro | Código do posto (chave primária) | 1 a 8.706 | Obrigatório, único | Gerado no notebook 03 com `ROW_NUMBER`, em ordem de CNPJ |
| `cnpj` | texto | CNPJ do posto, só com números | 14 dígitos | Obrigatório, único | `CNPJ da Revenda` → pontos, barra, traço e espaços removidos (R2) |
| `revenda` | texto | Razão social do posto | Texto livre | Obrigatório | `Revenda` → espaços removidos (R1). Se o CNPJ teve mais de um nome no ano, fica um só (`MAX`) |

---

## gold_dim_bandeira

Dimensão de bandeira (distribuidora à qual o posto é vinculado). **Grão:** um registro por bandeira. **Linhas:** 49.

| Atributo | Tipo | Descrição | Domínio | Obrigatoriedade | Linhagem |
|---|---|---|---|---|---|
| `id_bandeira` | inteiro | Código da bandeira (chave primária) | 1 a 49 | Obrigatório, único | Gerado no notebook 03 com `ROW_NUMBER`, em ordem de bandeira |
| `bandeira` | categórico | Nome da bandeira, como publicado pela ANP | 49 bandeiras; as principais são BRANCA, VIBRA, IPIRANGA, RAIZEN e ALE | Obrigatório | `Bandeira` → espaços removidos (R1) |
| `tipo_bandeira` | categórico | Classificação da bandeira (regra de negócio da pergunta 2) | BANDEIRA BRANCA; GRANDE DISTRIBUIDORA (VIBRA, RAIZEN, IPIRANGA); OUTRAS DISTRIBUIDORAS (as demais 45) | Obrigatório | Calculado no notebook 03 a partir de `bandeira` |

**Participação por tipo de bandeira na tabela fato:**

| Tipo | Bandeiras | Qtd. de preços | % |
|---|---|---|---|
| BANDEIRA BRANCA | BRANCA | 266.087 | 33,1% |
| GRANDE DISTRIBUIDORA | VIBRA, IPIRANGA, RAIZEN | 469.182 | 58,3% |
| OUTRAS DISTRIBUIDORAS | 45 bandeiras (ALE, SABBÁ, RODOIL...) | 69.348 | 8,6% |

**Decisão registrada:** a bandeira `RAIZEN MIME` (2.206 preços, 0,3% da base) foi classificada como "outras distribuidoras", porque a ANP a registra como uma bandeira distinta de `RAIZEN`. Pelo peso pequeno, essa escolha não altera o resultado da pergunta 2.
