# ControlFinan (Elixir)

![Elixir](https://img.shields.io/badge/Elixir-1.18-4B275F?logo=elixir&logoColor=white)
![Phoenix](https://img.shields.io/badge/Phoenix-1.8-FD4F00?logo=phoenixframework&logoColor=white)
![Tailwind](https://img.shields.io/badge/Tailwind-4-06B6D4?logo=tailwindcss&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)

Aplicação web de controle financeiro pessoal, pensada para quem trabalha como motorista de aplicativo. Cada usuário registra entradas (créditos) e saídas (débitos) em contas como dinheiro, bancos e carteiras de aplicativos, e acompanha o saldo por dia e por mês.

Esta é a versão em **Elixir + Phoenix** do [ControlFinan em Rails 8 + Hotwire](https://github.com/igorcb/controlfinan-rails8-hotwire). Ela tem **paridade de funcionalidades e de visual** com o original, assim como as outras versões (Django, Laravel, Go, Java, Rust e C#): mesmas telas, mesmas regras, mesmas mensagens e **mesmo esquema de banco**. As versões podem usar os mesmos dados, inclusive as senhas.

Usa Phoenix com controllers simples e templates EEx (sem LiveView), Ecto SQL com Postgrex, `bcrypt_elixir` e `tz` para o fuso horário.

## Funcionalidades

| Tela | Rota | O que faz |
|---|---|---|
| Conta Corrente | `/` | Lista os lançamentos, do mais recente para o mais antigo, 30 por página, com o saldo total |
| Saldo do dia | `/current_accounts?date=AAAA-MM-DD` | Filtra a listagem por um dia e mostra o saldo daquele dia |
| Novo lançamento | `/current_accounts/new` | Cadastra um crédito ou um débito |
| Detalhe, edição e exclusão | `/current_accounts/:id` | Mostra, altera ou remove um lançamento |
| Dashboard | `/dashboard` | Abas **Saldo Diário** e **Saldo Mensal** (corridas menos combustível, lavagem e telefone). As setas navegam entre os meses |
| JSON | `/current_accounts.json` e `/current_accounts/:id.json` | Os mesmos dados, para integrações |
| Cadastro, login e senha | `/registration/new`, `/session/new`, `/passwords/new` | Conta de usuário, com senha de no mínimo 6 caracteres |

Cada usuário só enxerga os próprios lançamentos.

## Como a paridade foi feita

| Rails 8 + Hotwire | Elixir |
|---|---|
| Autenticação nativa do Rails 8 (`has_secure_password`, tabela `sessions`, cookie `session_id`) | Mesmo modelo: tabela `sessions` e cookie assinado `session_id`. O `bcrypt_elixir` grava no formato do Rails (`$2a$`, com o sal "legacy") |
| Proteção CSRF (`authenticity_token`) | Token em cookie repetido em cada formulário, com o mesmo nome de campo, checado num plug antes do router |
| `rate_limit to: 10, within: 3.minutes` | Limite de 10 tentativas a cada 3 minutos por IP, em memória (GenServer) |
| Token de redefinição de senha (15 minutos) | Token assinado com validade de 15 minutos, invalidado quando a senha muda |
| `_method` para PATCH, PUT e DELETE | O mesmo campo `_method` nos formulários |
| Turbo (`data-turbo-confirm`) e Stimulus (abas) | JavaScript simples para a confirmação e as abas |
| jbuilder | JSON compacto com os mesmos campos, na mesma ordem e no mesmo formato (por exemplo, `"price":"150.0"`) |
| Tailwind CSS 4 | Tailwind CSS 4 (CLI standalone), com as mesmas classes |

Não usa a sessão, o flash nem o CSRF do Phoenix, porque eles mudam nomes de cookies e de campos. Os templates são EEx puro (não HEEx), para o HTML sair igual ao do Rails. O preço vem do Postgres como `Decimal` e é tratado em centavos (inteiros), sem ponto flutuante.

**Verificação**, com o mesmo usuário e os mesmos dados (7.292 lançamentos) nos dois apps:

- Texto idêntico em todas as telas comparadas, incluindo paginação, filtro por dia, datas e meses inválidos, dashboard, formulários, mensagens de validação, erros de cadastro e login inválido.
- JSON idêntico byte a byte (lista, terceira página e detalhe).
- HTML com a mesma estrutura dos templates das outras versões.

## Benchmark

O benchmark que compara as versões do ControlFinan, com os mesmos dados e os mesmos limites de CPU e memória, fica no repositório do app de referência: [controlfinan-rails8-hotwire/benchmark](https://github.com/igorcb/controlfinan-rails8-hotwire/tree/main/benchmark).

A BEAM usa todos os núcleos que o container recebe (no benchmark, 2 CPUs).

## Como rodar com Docker

```bash
docker compose up               # app em http://localhost:8009
```

O container de desenvolvimento baixa as dependências, compila o Tailwind e roda `mix phx.server`. As tabelas são criadas na subida (mesmo esquema do app Rails). Depois de mudar código, reinicie com `docker compose restart web`.

Imagem de produção: `Dockerfile.prod`, um `mix release` (com o ERTS) sobre `debian:bookworm-slim`, com cerca de 150 MB e log só de avisos.

```bash
docker build -f Dockerfile.prod -t bench-elixir .
```

Configure `DATABASE_URL` (por exemplo `ecto://app:app@db:5432/controlfinan_elixir`), `SECRET_KEY_BASE` e, se quiser, `BCRYPT_COST` (padrão 12), `DB_POOL` (padrão 10) e `PORT` (padrão 8000).

## Testes

37 testes com ExUnit, usando Postgres de verdade. As requisições passam pelo endpoint inteiro, com cookies, CSRF e `_method`, como num navegador. Cobrem:

- Formatação de moeda e decimais.
- Senha no formato do Rails, incluindo um hash gravado pelo próprio Rails.
- Validações em pt-BR, saldo e resumo do mês.
- Login, limite de tentativas (com relógio controlado), logout, CSRF, cadastro e redefinição de senha.
- Lançamentos: filtro, paginação, JSON, criar, editar, excluir e isolamento entre usuários.
- Dashboard.

```bash
docker compose run --rm web mix test
```

Os testes usam o banco `controlfinan_elixir_test`, criado automaticamente.

## Estrutura

```
config/                          configuração (variáveis de ambiente em runtime.exs)
lib/controlfinan/accounts.ex     usuários, sessões, senha e validações
lib/controlfinan/entries.ex      lançamentos, validações, consultas e resumo do mês
lib/controlfinan/format.ex       moeda e decimais como no Rails
lib/controlfinan/rate_limiter.ex limite de tentativas
lib/controlfinan_web/web.ex      cookies assinados, sessão, CSRF, flash e respostas
lib/controlfinan_web/pipeline.ex _method, CSRF e sessão antes do router
lib/controlfinan_web/router.ex   rotas
lib/controlfinan_web/controllers.ex  controllers
lib/controlfinan_web/templates/  HTML com o mesmo resultado do app Rails
priv/schema.sql                  esquema do banco (igual ao do Rails)
priv/static/                     JavaScript e ícones (o CSS é gerado pelo Tailwind)
assets/                          fonte do Tailwind
```

## Licença

[MIT](LICENSE)
