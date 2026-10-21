# Modelo de dados – Esquema Estrela

Camada Gold do pipeline, no schema `workspace.combustiveis` do Databricks.

**Grão da tabela fato:** um preço de venda por **posto**, **produto** e **dia de coleta**.

```mermaid
erDiagram
    gold_dim_tempo    ||--o{ gold_fato_preco : "data"
    gold_dim_local    ||--o{ gold_fato_preco : "id_local"
    gold_dim_produto  ||--o{ gold_fato_preco : "id_produto"
    gold_dim_posto    ||--o{ gold_fato_preco : "id_posto"
    gold_dim_bandeira ||--o{ gold_fato_preco : "id_bandeira"

    gold_fato_preco {
        date data FK
        bigint id_local FK
        bigint id_produto FK
        bigint id_posto FK
        bigint id_bandeira FK
        decimal valor_venda
    }
    gold_dim_tempo {
        date data PK
        int ano
        int mes
        string ano_mes
        int semestre
        int semana_ano
        int dia_semana
    }
    gold_dim_local {
        bigint id_local PK
        string regiao
        string uf
        string municipio
    }
    gold_dim_produto {
        bigint id_produto PK
        string produto
        string unidade
        string grupo
    }
    gold_dim_posto {
        bigint id_posto PK
        string cnpj
        string revenda
    }
    gold_dim_bandeira {
        bigint id_bandeira PK
        string bandeira
        string tipo_bandeira
    }
```

## Por que esse modelo

| Escolha | Justificativa |
|---|---|
| Esquema estrela (e não snowflake) | As dimensões são pequenas e simples; separar em hierarquias não traria ganho e deixaria as consultas mais longas |
| Bandeira em dimensão própria, separada do posto | Um posto pode trocar de bandeira durante o ano; com a bandeira na fato, cada preço fica associado à bandeira daquele dia |
| Chave da dimensão tempo é a própria data | A data já é única e legível; não há necessidade de código artificial |
| Demais dimensões com chave substituta (`id_...`) | A fato guarda códigos numéricos curtos no lugar de textos repetidos |
| Coluna `grupo` em produto | Permite comparar gasolina com etanol sem misturar comum e aditivada (pergunta 4) |
| Coluna `tipo_bandeira` | Implementa a regra de negócio da pergunta 2 (branca × grandes distribuidoras) |

## Como cada pergunta usa o modelo

| Pergunta | Dimensões usadas |
|---|---|
| 1. Estados com maior e menor preço | local, produto |
| 2. Bandeira branca × grandes distribuidoras | bandeira, produto |
| 3. Evolução mês a mês | tempo, produto |
| 4. Etanol × gasolina (regra dos 70%) | local, tempo, produto |
| 5. Repasse de altas e baixas | tempo, posto, produto |
