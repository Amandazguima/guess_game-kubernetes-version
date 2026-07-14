# Helm Chart — guess-game

Este Helm Chart implanta o jogo de adivinhação (Flask + React + PostgreSQL) em um cluster **k3d / Kubernetes**.

Ele substitui, para a Unidade II (Kubernetes), o `docker-compose.yml` da Unidade I, reaproveitando as **mesmas imagens Docker** publicadas no Docker Hub — não é necessário reconstruí-las.

## Pré-requisitos

- [k3d](https://k3d.io/) (empacota o k3s + containerd num container Docker)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [helm](https://helm.sh/) v3+
- Docker (necessário apenas porque o k3d roda dentro dele)

## Instalação

```bash
# 1. Criar o cluster k3d (na raiz do repositório)
k3d cluster create guess-game --agents 2

# 2. Instalar o chart
helm install guess-game ./k8s -n guess-game --create-namespace

# 3. Acompanhar a subida dos pods
kubectl -n guess-game get pods -w
```

Quando todos os pods estiverem `Running` (postgres, backend, frontend):

```bash
# 4. Expor o frontend no host
kubectl -n guess-game port-forward svc/frontend 8080:80
```

Acesse: **http://localhost:8080**

## Componentes instalados

| Recurso | Tipo | Função |
|---------|------|--------|
| `Namespace/guess-game` | Namespace | Isola todos os recursos do jogo |
| `postgres-secret` | Secret | Senha do Postgres (`stringData`, texto puro) |
| `frontend-nginx-config` | ConfigMap | `nginx.conf` do frontend apontando o upstream para o Service `backend` |
| `postgres` | StatefulSet | Postgres com identidade estável (`postgres-0`) |
| `postgres` | Service (headless) | DNS `postgres` para o backend conectar |
| PVC `postgres-data` | PersistentVolumeClaim | 1Gi persistente (StorageClass `local-path`) |
| `backend` | Deployment | N réplicas do Flask + Gunicorn |
| `backend` | Service (ClusterIP) | DNS `backend:5000` — kube-proxy faz o LB |
| `backend` | HorizontalPodAutoscaler | Escala 2–6 pods por CPU (≥70%) |
| `frontend` | Deployment | NGINX servindo o React + proxy reverso |
| `frontend` | Service (ClusterIP) | Alvo do `kubectl port-forward` |

## Decisões de design (K8s)

- **Service único `backend` em vez de múltiplos upstreams**: o balanceamento de carga no K8s é responsabilidade do kube-proxy (via `Endpoints`), não do NGINX. O `nginx.conf` do frontend foi simplificado para apontar para `backend:5000`.
- **ConfigMap para o nginx.conf**: a imagem do frontend já vinha com um `nginx.conf` que apontava para `backend1`/`backend2` (nomes do Compose). Em vez de reconstruir a imagem, montamos um ConfigMap com `subPath` sobre `/etc/nginx/nginx.conf` — a mesma imagem funciona em ambos os ambientes.
- **StatefulSet para o Postgres**: garante DNS estável (`postgres-0`) e rebinding do PVC após restarts.
- **HPA com metrics-server**: o k3s já inclui o metrics-server por padrão, então o HPA funciona sem instalação adicional. O limite de CPU (`limits.cpu`) é intencionalmente omitido para que o pod possa usar CPU extra sob carga e disparar o autoscale.

## Acessar

```bash
kubectl -n guess-game port-forward svc/frontend 8080:80
```
→ **http://localhost:8080**

## Atualizar / Rollback

```bash
# Trocar a versão da imagem do backend, por exemplo
helm upgrade guess-game ./k8s --set images.backend=amandazguima/guess-game-backend:v2

# Ver histórico
helm history guess-game -n guess-game

# Voltar para a release anterior
helm rollback guess-game 1 -n guess-game
```

## Desinstalar

```bash
helm uninstall guess-game -n guess-game
k3d cluster delete guess-game
```

## Valores customizáveis (`values.yaml`)

| Chave | Default | Descrição |
|-------|---------|-----------|
| `images.backend` | `amandazguima/guess-game-backend:v1` | Imagem do backend |
| `images.frontend` | `amandazguima/guess-game-frontend:v1` | Imagem do frontend |
| `backend.replicas` | `2` | Réplicas iniciais (o HPA pode alterar) |
| `hpa.minReplicas` | `2` | Mínimo do autoscale |
| `hpa.maxReplicas` | `6` | Máximo do autoscale |
| `hpa.cpuAverageUtilization` | `70` | % de CPU que dispara o autoscale |
| `postgres.password` | `secretpass` | Senha do banco |
| `postgres.storage` | `1Gi` | Tamanho do PVC |
