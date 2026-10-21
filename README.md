# MVP – Preços de Combustíveis no Brasil (ANP, 2025)

Trabalho final de MVP – Departamento de Engenharia de Produção / UnB
Autor: José Marcos Pereira Carneiro
Plataforma: Databricks Free Edition

---

## 1. Objetivo

### Problema
O preço dos combustíveis varia bastante entre estados, entre postos e ao longo do ano. Para quem abastece, seja um motorista ou um gestor de frota, a pergunta prática é: **onde, quando e com qual combustível se gasta menos?** Este MVP usa os dados públicos da ANP de 2025 para responder a essa pergunta com evidência.

### Hipótese
As diferenças de preço entre regiões, bandeiras e combustíveis são grandes o suficiente para justificar uma decisão de abastecimento orientada por dados.

### Perguntas de negócio
1. Quais estados tiveram o maior e o menor preço médio de gasolina comum e de etanol em 2025, e qual a diferença percentual entre esses extremos?
2. Postos de bandeira branca praticam preços menores que os postos de grandes distribuidoras? Qual é a diferença média?
3. Como o preço médio evoluiu mês a mês em 2025 e em quais meses ocorreram as maiores variações?
4. Em quais estados o etanol foi economicamente vantajoso em relação à gasolina (relação de preços ≤ 70%) e em quantos meses do ano?
5. Os postos repassam as reduções de preço com a mesma velocidade com que repassam os aumentos?

> As perguntas permanecem íntegras até o final do trabalho, inclusive as que não puderem ser respondidas. O atingimento de cada uma é discutido na seção de Autoavaliação.

---

## 2. Coleta

### Origem dos dados
Os dados vêm do **Levantamento de Preços de Combustíveis (LPC)** da ANP, uma pesquisa semanal feita por empresa contratada pela agência, que registra o preço de venda praticado em uma amostra de postos de todo o país. A ANP publica os resultados no portal de dados abertos, agrupados por semestre.

| Item | Valor |
|---|---|
| Fonte | ANP – Série Histórica de Preços de Combustíveis (Combustíveis Automotivos) |
| Página | https://www.gov.br/anp/pt-br/centrais-de-conteudo/dados-abertos/serie-historica-de-precos-de-combustiveis |
| Arquivos | `ca-2025-01.zip` (1º semestre) e `ca-2025-02.zip` (2º semestre) |
| Data da coleta | 21/10/2026 |
| Formato original | Um CSV dentro de cada .zip; separador `;`; codificação UTF-8; decimal com vírgula; data no formato dd/mm/aaaa |
| Volume | **813.731 linhas** (429.523 no 1º semestre e 384.208 no 2º) e 16 colunas |
| Licença | Creative Commons Attribution (CC-BY) |

### Como a coleta foi feita
1. Os dois arquivos .zip foram baixados manualmente do portal da ANP. Não foi necessário robô de coleta (web scraping), porque os dados são publicados em arquivo para download.
2. Os arquivos foram enviados para um **volume** no Databricks (`workspace.combustiveis.raw`), uma pasta de armazenamento na nuvem.
3. O notebook [`01_coleta_bronze`](notebooks/01_coleta_bronze.py) descompacta os arquivos, lê os CSVs e grava a tabela **`workspace.combustiveis.bronze_precos`** no formato Delta, sem alterar o conteúdo.

### Persistência na nuvem
Ao final da coleta, os dados estão persistidos em dois lugares no Databricks:
- **Arquivos brutos:** volume `workspace.combustiveis.raw` (os .zip e os CSVs extraídos);
- **Tabela Bronze:** `workspace.combustiveis.bronze_precos`, com 813.731 linhas.

Evidências:
- Workspace do Databricks: [`evidencias/01_workspace.png`](evidencias/01_workspace.png)
- Arquivos no volume: [`evidencias/02_volume_raw_arquivos.png`](evidencias/02_volume_raw_arquivos.png)
- Contagem de linhas por arquivo: [`evidencias/03_contagem_bronze.png`](evidencias/03_contagem_bronze.png)
- Tabela Bronze no catálogo: [`evidencias/04_tabela_bronze_catalog.png`](evidencias/04_tabela_bronze_catalog.png)

### Dados pessoais (LGPD)
A base identifica os postos pelo CNPJ e pela razão social, ou seja, são dados de **pessoas jurídicas**, divulgados publicamente pela própria ANP. Não há dados de pessoas físicas. Mesmo assim, por cautela, os endereços são descartados na camada Silver (não são usados em nenhuma pergunta), e todas as análises são feitas de forma **agregada** (por estado, bandeira e mês), sem expor postos individualmente.

---

## 3. Modelagem e Catálogo de Dados
_Em construção._

## 4. Carga (pipeline ETL)

O pipeline segue a **arquitetura medalhão**, em que cada camada é uma tabela Delta no schema `workspace.combustiveis`:

| Camada | Tabela | Notebook | O que contém |
|---|---|---|---|
| Bronze | `bronze_precos` | [`01_coleta_bronze`](notebooks/01_coleta_bronze.py) | Dado bruto, igual à fonte, todas as colunas como texto |
| Silver | `silver_precos` | [`02_transformacao_silver`](notebooks/02_transformacao_silver.sql) | Dado limpo, tipado e sem duplicidade |
| Gold | _em construção_ | _em construção_ | Modelo estrela para a análise |

### 4.1 Bronze → Silver: regras de transformação

Antes de limpar, o notebook 02 faz um **diagnóstico** da camada Bronze, de modo que cada regra é justificada por um número:

| Diagnóstico | Resultado |
|---|---|
| Total de linhas na Bronze | 813.731 |
| Linhas totalmente em branco | 9.114 |
| `valor_de_compra` preenchido | 0 linhas (coluna vazia) |
| Produtos diferentes | 6 (gasolina, gasolina aditivada, etanol, diesel, diesel S10, GNV) |
| Bandeiras diferentes | 49 |
| Duplicatas reais (posto + produto + dia) | 0 |
| Unidade do GNV | escrita de dois jeitos: `R$ / m³` e `R$ / m3` |

Regras aplicadas:

| # | Regra | Motivo |
|---|---|---|
| R1 | Tirar espaços sobrando dos textos e transformar texto vazio em nulo | CNPJ e outros campos vêm com espaço na frente |
| R2 | Deixar o CNPJ só com números | Padronizar a chave que identifica o posto |
| R3 | Converter o preço de texto (`"5,59"`) para número (`5.59`) | Permitir cálculos |
| R4 | Converter a data de texto (`19/06/2025`) para data | Permitir agrupar por mês |
| R5 | Descartar `valor_de_compra` | Coluna 100% vazia |
| R6 | Descartar as colunas de endereço | Não são usadas em nenhuma pergunta (minimização de dados) |
| R7 | Remover linhas vazias, sem preço, com preço zero ou sem data | Os arquivos da ANP têm 9.114 linhas em branco |
| R8 | Manter um único preço por posto, produto e dia | Proteção contra dupla contagem (hoje não há duplicatas) |
| R9 | Corrigir o nome do arquivo de origem (`%20` → espaço) | Deixar a linhagem legível |
| R10 | Padronizar a unidade do GNV (`R$ / m3` → `R$ / m³`) | A mesma unidade aparece escrita de dois jeitos |

**Resultado:** a Silver tem **804.617 linhas**. A diferença para a Bronze (9.114) é exatamente o número de linhas em branco, ou seja, nenhum registro com dado real foi perdido.

Evidências:
- Diagnóstico da Bronze: [`evidencias/05_diagnostico_bronze.png`](evidencias/05_diagnostico_bronze.png)
- Contagem Bronze × Silver: [`evidencias/06_contagem_silver.png`](evidencias/06_contagem_silver.png)
- Tipos das colunas da Silver: [`evidencias/07_tipos_silver.png`](evidencias/07_tipos_silver.png)

## 5. Análise
### 5.1 Qualidade dos dados
_Em construção._

### 5.2 Respostas às perguntas
_Em construção._

### 5.3 Discussão geral
_Em construção._

## 6. Autoavaliação
_Em construção._

## 7. Licença
- **Código:** MIT (ver arquivo `LICENSE`).
- **Dados:** Série Histórica de Preços de Combustíveis – ANP, publicada como dado aberto sob licença Creative Commons Attribution (CC-BY), que permite redistribuição e uso derivado com atribuição da fonte.

## Estrutura do repositório
| Caminho | Conteúdo |
|---|---|
| `README.md` | Este documento |
| `/notebooks` | Notebooks de coleta, transformação, carga e análise |
| `/catalogo` | Catálogo de Dados e diagrama do modelo |
| `/evidencias` | Capturas de tela da execução na nuvem |
| `LICENSE` | Licença do código |
