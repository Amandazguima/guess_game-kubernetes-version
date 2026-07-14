# Guess Game — Jogo de Adivinhação

Este projeto implementa o **Guess Game** (estilo Mastermind) com duas formas de deploy:

| Unidade | Tecnologia | Pasta |
|---------|-----------|-------|
| **I — Docker Compose** | Docker Compose, NGINX, Gunicorn | Raiz do repositório |
| **II — Kubernetes** | k3d, Helm Charts, HPA | `/k8s` |

> **Regra**: Nenhuma alteração foi feita no código-fonte da aplicação (`.py`, `.tsx`, `.js`, `.css`). Todas as mudanças estão em arquivos de infraestrutura.

---


---

## Unidade II — Kubernetes (k3d + Helm)

### Arquitetura

```
                    ┌─────────────────────────────────────────┐
  kubectl           │  k3d Cluster (1 server + 2 agents)     │
  port-forward      │                                         │
       │            │  Namespace: guess-game                  │
       ▼            │                                         │
  localhost:8080    │  ┌──────────┐                           │
       │            │  │ frontend │ Deployment x1             │
       └────────────┤  │ (nginx)  │──── proxy ────┐           │
                    │  └──────────┘               │           │
                    │         Service: frontend    │           │
                    │                             ▼           │
                    │              Service: backend :5000      │
                    │                    │                     │
                    │              ┌─────┴──────┐              │
                    │              │  Deployment │ HPA 2-6    │
                    │              │  (backend)  │ (auto-cpu)  │
                    │              └─────┬──────┘              │
                    │                    │                     │
                    │              Service: postgres :5432     │
                    │                    │                     │
                    │              ┌─────┴──────┐              │
                    │              │ StatefulSet│ PVC 1Gi       │
                    │              │ (postgres) │ (local-path)  │
                    │              └────────────┘              │
                    └─────────────────────────────────────────┘
```

### Pré-requisitos

| Ferramenta | Instalação (macOS) |
|-----------|-------------------|
| **k3d** | `brew install k3d` |
| **kubectl** | `brew install kubectl` |
| **helm** | `brew install helm` |
| **Docker** | Docker Desktop (necessário para o k3d rodar) |

### Imagens no Docker Hub

| Imagem | Docker Hub | Descrição |
|--------|-----------|-----------|
| Backend | `amandazguima/guess-game-backend:v1` | Flask + Gunicorn (Python 3.12) |
| Frontend | `amandazguima/guess-game-frontend:v1` | React + NGINX |

> Não é necessário reconstruir as imagens — basta `docker pull` das imagens disponíveis em https://hub.docker.com/repositories/amandazguima.

### Instalação e Execução (Kubernetes)

```bash
git clone https://github.com/fams/guess_game.git
cd guess_game

# 1. Criar cluster k3d
k3d cluster create guess-game --agents 2

# 2. Instalar o Helm chart
helm install guess-game ./k8s -n guess-game --create-namespace

# 3. Aguardar pods
kubectl -n guess-game get pods -w

# 4. Expor o frontend
kubectl -n guess-game port-forward svc/frontend 8080:80
```

Acesse: **http://localhost:8080**

### Componentes Kubernetes (Helm Chart)

| Recurso | Nome | Função |
|---------|------|--------|
| **Namespace** | `guess-game` | Isola todos os recursos do jogo |
| **Secret** | `postgres-secret` | Senha do banco (stringData, texto puro) |
| **ConfigMap** | `frontend-nginx-config` | Sobrescreve o `nginx.conf` do frontend para apontar ao Service K8s `backend:5000` |
| **StatefulSet** | `postgres` | Postgres com identidade estável + PVC persistente |
| **PVC** | `postgres-data` | Volume 1Gi via StorageClass `local-path` |
| **Deployment** | `backend` | Réplicas do Flask + Gunicorn (balanço via kube-proxy) |
| **Deployment** | `frontend` | NGINX + React com ConfigMap montado |
| **Service** | `backend` / `frontend` / `postgres` | DNS interno (ClusterIP) |
| **HPA** | `backend` | Autoescala 2→6 réplicas por CPU (≥70%) |

### Decisões de Design (Kubernetes)

| Decisão | Justificativa |
|---------|--------------|
| **ConfigMap para nginx.conf** | A imagem publicada tem upstream `backend1`/`backend2` (nomes do Compose). Sem reconstruir a imagem, montamos o ConfigMap via `subPath` sobre `/etc/nginx/nginx.conf` — a mesma imagem funciona em ambos os ambientes. |
| **Service único `backend`** | No K8s o balanceamento de carga é responsabilidade do kube-proxy (via Endpoints), não do nginx. O `nginx.conf` aponta para um único `server backend:5000;`. |
| **StatefulSet para Postgres** | Garante DNS estável (`postgres-0`) e rebinding do PVC após restarts. |
| **HPA com metrics-server** | O k3s/k3d já inclui o metrics-server por padrão. O `limits.cpu` é omitido intencionalmente para que o pod use CPU extra sob carga e dispare o autoscale. |
| **Helm Chart parametrizado** | Permite alterar versões de imagem com `--set` (ex: `--set images.backend=...:v2`) sem editar YAML. |

### Atualizar Componentes (Kubernetes)

```bash
# Trocar versão da imagem
helm upgrade guess-game ./k8s --set images.backend=amandazguima/guess-game-backend:v2

# Histórico de releases
helm history guess-game -n guess-game

# Rollback
helm rollback guess-game 1 -n guess-game
```

### Desinstalar (Kubernetes)

```bash
helm uninstall guess-game -n guess-game
k3d cluster delete guess-game
```

---

## Como Jogar

### 1. Criar um novo jogo (Maker)

1. Acesse `http://localhost:8080`
2. Clique em **Maker** na barra de navegação
3. Digite uma palavra ou frase secreta
4. Clique em **Create Game**
5. Anote o `Game ID` gerado (ex.: `r9fquQp4`)

### 2. Adivinhar a senha (Breaker)

1. Acesse `http://localhost:8080`
2. Clique em **Breaker** na barra de navegação
3. Digite o `Game ID` recebido
4. Digite seu palpite
5. Clique em **Submit Guess**
6. O sistema retorna:
   - **"Correct"** — Você adivinhou a senha!
   - **"Incorrect"** — Dica com quantas letras estão corretas e em quais posições

---

## URLs dos Serviços

| Serviço | URL | Descrição |
|---------|-----|-----------|
| **Aplicação** | `http://localhost:8080` | Ponto de entrada (Docker Compose ou port-forward K8s) |
| **Criar jogo** | `POST http://localhost:8080/create` | `{"password": "..."}` → `{"game_id": "..."}` |
| **Fazer palpite** | `POST http://localhost:8080/guess/<id>` | `{"guess": "..."}` → `{"result": "..."}` |
| **Health check** | `GET http://localhost:8080/health` | `{"status": "ok"}` |

---

## Estrutura do Repositório

```
guess_game/
├── docker-compose.yml          # Unidade I: Orquestração Docker Compose
├── Dockerfile.backend          # Imagem do backend (Gunicorn)
├── Dockerfile.frontend         # Imagem do frontend (multi-stage: Node → NGINX)
├── nginx.conf                  # NGINX config (proxy reverso + load balancer)
├── requirements.txt             # Dependências Python
├── .dockerignore
├── k8s/                        # Unidade II: Helm Chart Kubernetes
│   ├── Chart.yaml              # Metadados do chart
│   ├── values.yaml             # Parâmetros (imagens, réplicas, HPA, senha)
│   ├── README.md               # Documentação do chart
│   └── templates/
│       ├── _helpers.tpl        # Labels e seletores reutilizáveis
│       ├── namespace.yaml
│       ├── secret-postgres.yaml
│       ├── configmap-nginx.yaml
│       ├── postgres-statefulset.yaml
│       ├── postgres-service.yaml
│       ├── backend-deployment.yaml
│       ├── backend-service.yaml
│       ├── backend-hpa.yaml
│       ├── frontend-deployment.yaml
│       └── frontend-service.yaml
├── guess/                      # Código-fonte Flask (intocado)
│   ├── __init__.py
│   ├── discover.py
│   └── game_routes.py
├── repository/                 # Camada de persistência (intocada)
│   ├── entities.py
│   ├── postgres.py
│   ├── sqlite.py
│   ├── dynamodb.py
│   └── hash.py
├── frontend/                   # Código-fonte React (intocado)
│   ├── package.json
│   ├── public/
│   └── src/
│       ├── App.tsx
│       └── components/
│           ├── Home.tsx
│           ├── Maker.tsx
│           └── Breaker.tsx
├── run.py
└── tests/
```

---

## Licença

Este projeto está licenciado sob a [MIT License](LICENSE).
