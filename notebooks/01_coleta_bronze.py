# Databricks notebook source
# MAGIC %md
# MAGIC # 01 – Coleta e camada Bronze
# MAGIC
# MAGIC **O que este notebook faz:** pega os arquivos brutos da ANP, coloca na nuvem e grava a primeira tabela do pipeline, a **camada Bronze**.
# MAGIC
# MAGIC **Regra da camada Bronze:** o dado fica **igual ao que veio da fonte**. Não corrigimos nada aqui.
# MAGIC A única mudança é técnica: os nomes das colunas perdem acentos e espaços, porque o formato de tabela usado (Delta) não aceita espaço em nome de coluna.
# MAGIC Todas as colunas são lidas como **texto**. Converter para número e data fica para a próxima camada (Silver).
# MAGIC
# MAGIC | Item | Valor |
# MAGIC |---|---|
# MAGIC | Fonte | ANP – Série Histórica de Preços de Combustíveis (Combustíveis Automotivos) |
# MAGIC | Período | 1º e 2º semestres de 2025 |
# MAGIC | Formato original | 2 arquivos .zip, cada um com um CSV |
# MAGIC | Licença | Creative Commons Attribution (CC-BY) |
# MAGIC | Link | https://www.gov.br/anp/pt-br/centrais-de-conteudo/dados-abertos/serie-historica-de-precos-de-combustiveis |

# COMMAND ----------

# MAGIC %md
# MAGIC ## Passo 1 – Criar o espaço de armazenamento na nuvem
# MAGIC
# MAGIC No Databricks, os dados ficam organizados em três níveis: **catálogo → schema → tabela** (como armário → gaveta → pasta).
# MAGIC - Catálogo: `workspace` (já vem pronto na versão gratuita)
# MAGIC - Schema: `combustiveis` (criamos agora; vai guardar todas as tabelas do projeto)
# MAGIC - Volume: `raw` (uma pasta na nuvem para guardar os arquivos brutos .zip e .csv)

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Cria o schema (a "gaveta") do projeto, se ele ainda não existir
# MAGIC CREATE SCHEMA IF NOT EXISTS workspace.combustiveis
# MAGIC -- Descrição que aparece no catálogo do Databricks
# MAGIC COMMENT 'MVP - Precos de combustiveis ANP 2025'

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Cria o volume (a "pasta de arquivos") onde vamos colocar os .zip baixados da ANP
# MAGIC CREATE VOLUME IF NOT EXISTS workspace.combustiveis.raw
# MAGIC -- Descrição que aparece no catálogo do Databricks
# MAGIC COMMENT 'Arquivos brutos baixados do portal de dados abertos da ANP'

# COMMAND ----------

# MAGIC %md
# MAGIC ## Passo 2 – Enviar os arquivos para a nuvem (manual)
# MAGIC
# MAGIC Os dois .zip foram baixados do site da ANP e enviados pela interface do Databricks:
# MAGIC **Catalog → workspace → combustiveis → Volumes → raw → Upload to this volume**.
# MAGIC
# MAGIC A célula abaixo só confere se os arquivos chegaram.

# COMMAND ----------

# Nome do catálogo (vem pronto no Databricks gratuito)
CATALOGO = "workspace"

# Nome do schema que criamos no passo 1
SCHEMA = "combustiveis"

# Endereço da pasta "raw" na nuvem, montado a partir dos nomes acima
VOLUME_PATH = f"/Volumes/{CATALOGO}/{SCHEMA}/raw"

# Lista com os nomes dos dois arquivos baixados da ANP (um por semestre)
ARQUIVOS_ZIP = ["ca-2025-01.zip", "ca-2025-02.zip"]

# Lista o conteúdo da pasta na nuvem, para confirmar que os .zip estão lá
display(dbutils.fs.ls(VOLUME_PATH))

# COMMAND ----------

# MAGIC %md
# MAGIC ## Passo 3 – Descompactar os arquivos
# MAGIC
# MAGIC A ANP publica os dados de 2025 compactados em .zip. Aqui extraímos o CSV de dentro de cada um.

# COMMAND ----------

# Biblioteca padrão do Python para trabalhar com arquivos .zip
import zipfile

# Repete o bloco abaixo para cada um dos dois arquivos
for nome in ARQUIVOS_ZIP:

    # Monta o endereço completo do .zip na nuvem
    caminho_zip = f"{VOLUME_PATH}/{nome}"

    # Abre o .zip
    with zipfile.ZipFile(caminho_zip) as arquivo_zip:

        # Mostra na tela quais arquivos existem dentro do .zip
        print(f"{nome} contém: {arquivo_zip.namelist()}")

        # Extrai tudo para a subpasta "extraidos", dentro do volume
        arquivo_zip.extractall(f"{VOLUME_PATH}/extraidos")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Passo 4 – Olhar o arquivo bruto antes de ler
# MAGIC
# MAGIC Antes de carregar, abrimos as primeiras linhas do CSV para responder três perguntas:
# MAGIC 1. Qual é o **separador** das colunas? (vírgula, ponto e vírgula...)
# MAGIC 2. Qual é a **codificação** do texto? Ela define se os acentos vão aparecer certo.
# MAGIC 3. Os números usam **vírgula ou ponto** como separador decimal?

# COMMAND ----------

# Biblioteca padrão do Python para procurar arquivos por padrão de nome
import glob

# Procura todos os arquivos .csv dentro da pasta "extraidos" e coloca em ordem
arquivos_csv = sorted(glob.glob(f"{VOLUME_PATH}/extraidos/**/*.csv", recursive=True))

# Mostra na tela os arquivos encontrados
print("Arquivos CSV encontrados:")
for arquivo in arquivos_csv:
    print(" -", arquivo)


# Função que descobre a codificação do arquivo
def detectar_encoding(caminho):
    # Abre o arquivo em modo binário (bytes puros, sem interpretar o texto)
    with open(caminho, "rb") as f:
        # Lê um pedaço do começo do arquivo
        amostra = f.read(200_000)
    # Tenta interpretar esse pedaço como UTF-8 (o padrão mais comum hoje)
    try:
        amostra.decode("utf-8")
        # Se funcionou, o arquivo é UTF-8
        return "UTF-8"
    # Se deu erro, o arquivo usa a codificação antiga (latin-1)
    except UnicodeDecodeError:
        return "ISO-8859-1"


# Aplica a função no primeiro CSV e guarda o resultado
ENCODING = detectar_encoding(arquivos_csv[0])

# Mostra a codificação encontrada
print(f"\nCodificação detectada: {ENCODING}\n")

# Abre o primeiro CSV já com a codificação correta
with open(arquivos_csv[0], encoding=ENCODING) as f:
    # Mostra as 4 primeiras linhas (cabeçalho + 3 registros)
    for _ in range(4):
        print(f.readline().rstrip())

# COMMAND ----------

# MAGIC %md
# MAGIC ## Passo 5 – Ler os CSVs com o Spark
# MAGIC
# MAGIC O **Spark** é o motor do Databricks que processa tabelas grandes.
# MAGIC Lemos os dois semestres de uma vez e guardamos, em cada linha, o **nome do arquivo de origem**.
# MAGIC Isso faz parte da **linhagem**: saber de onde veio cada dado.

# COMMAND ----------

# Funções prontas do Spark (usamos o "F" como apelido)
from pyspark.sql import functions as F

# Lê os CSVs e cria a tabela em memória "df_bruto"
df_bruto = (
    spark.read
    # A primeira linha do arquivo é o cabeçalho (nomes das colunas)
    .option("header", True)
    # As colunas são separadas por ponto e vírgula
    .option("sep", ";")
    # Usa a codificação descoberta no passo 4
    .option("encoding", ENCODING)
    # Lê tudo como texto, sem tentar adivinhar tipos (regra da camada Bronze)
    .option("inferSchema", False)
    # Lê todos os CSVs encontrados (os dois semestres)
    .csv(arquivos_csv)
    # Cria a coluna "arquivo_origem" com o nome do arquivo de cada linha
    .withColumn("arquivo_origem", F.col("_metadata.file_name"))
)

# Mostra na tela os nomes originais das colunas
print("Colunas originais:")
for coluna in df_bruto.columns:
    print(" -", coluna)

# COMMAND ----------

# MAGIC %md
# MAGIC ## Passo 6 – Padronizar os nomes das colunas
# MAGIC
# MAGIC Exemplos: `Estado - Sigla` → `estado_sigla` | `Valor de Venda` → `valor_de_venda`
# MAGIC Só o **nome** da coluna muda. O conteúdo continua intacto.

# COMMAND ----------

# Biblioteca para "expressões regulares" (busca e troca de padrões de texto)
import re

# Biblioteca para lidar com acentos
import unicodedata


# Função que transforma um nome de coluna em um nome padronizado
def padronizar_nome(coluna):
    # Remove os acentos (ex.: "Município" vira "Municipio")
    sem_acento = unicodedata.normalize("NFKD", coluna).encode("ascii", "ignore").decode()
    # Troca tudo que não for letra ou número por "_" (ex.: " - " vira "_")
    com_underline = re.sub(r"[^0-9a-zA-Z]+", "_", sem_acento)
    # Tira "_" das pontas e deixa tudo em minúsculas
    return com_underline.strip("_").lower()


# Cria a tabela Bronze em memória a partir da tabela bruta
df_bronze = (
    df_bruto
    # Renomeia todas as colunas usando a função acima
    .toDF(*[padronizar_nome(c) for c in df_bruto.columns])
    # Cria a coluna "data_carga" com a data e hora em que o pipeline rodou
    .withColumn("data_carga", F.current_timestamp())
)

# Mostra lado a lado: nome antigo -> nome novo
for antiga, nova in zip(df_bruto.columns, df_bronze.columns):
    print(f"{antiga:30} -> {nova}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Passo 7 – Gravar a tabela Bronze na nuvem
# MAGIC
# MAGIC A partir daqui os dados estão **persistidos na nuvem**, no formato Delta.
# MAGIC O modo `overwrite` (sobrescrever) permite rodar o notebook de novo sem duplicar linhas.

# COMMAND ----------

# Nome completo da tabela: catálogo.schema.tabela
TABELA_BRONZE = f"{CATALOGO}.{SCHEMA}.bronze_precos"

# Grava a tabela
(
    df_bronze.write
    # Se a tabela já existir, substitui pelo conteúdo novo
    .mode("overwrite")
    # Permite substituir também a estrutura das colunas, se ela mudar
    .option("overwriteSchema", "true")
    # Salva como tabela permanente no catálogo
    .saveAsTable(TABELA_BRONZE)
)

# Conta as linhas da tabela gravada e mostra na tela
total = spark.table(TABELA_BRONZE).count()
print(f"Tabela {TABELA_BRONZE} gravada com {total:,} linhas.")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Passo 8 – Conferir a carga
# MAGIC
# MAGIC Quantas linhas vieram de cada arquivo e uma amostra dos dados. Esses números entram na seção **Coleta** do README.

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Conta quantas linhas vieram de cada arquivo (um por semestre)
# MAGIC SELECT
# MAGIC   arquivo_origem,           -- nome do arquivo
# MAGIC   COUNT(*) AS linhas        -- quantidade de linhas
# MAGIC FROM workspace.combustiveis.bronze_precos
# MAGIC GROUP BY arquivo_origem     -- agrupa por arquivo
# MAGIC ORDER BY arquivo_origem     -- ordena pelo nome

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Mostra as 10 primeiras linhas da tabela, para visualizar o dado bruto
# MAGIC SELECT *
# MAGIC FROM workspace.combustiveis.bronze_precos
# MAGIC LIMIT 10
