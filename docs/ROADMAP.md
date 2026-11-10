# Roadmap: ver todo el Proyecto Integrador en acción

Recorrido de principio a fin, en orden, con los comandos para **levantar, demostrar y destruir** Mini-Netflix
en AWS. Cada etapa indica **quién** la ejecuta y qué requisito del PDF cubre.

- **P1** = Persona 1 (infraestructura, anfitrión, dueño de la cuenta AWS)
- **Equipo** = cualquier integrante con acceso configurado (etapa 1)
- **Todos** = no hace falta AWS

Detalle adicional: [infra/RUNBOOK.md](../infra/RUNBOOK.md) (infra y credenciales) · [docs/GUIA-DEMO.md](GUIA-DEMO.md) (demo).

---

## Mapa: qué se conecta con qué

> **"¿Los pods están vinculados al EKS?"** Casi: un pod no se vincula directamente a EKS.
> EKS es el **cerebro** (plano de control administrado por AWS: API server, scheduler, etcd).
> Los **nodos** son instancias **EC2** que se registran en ese cerebro. Los **pods** (contenedores)
> **corren dentro de los nodos**, y es el plano de control de EKS quien decide en qué nodo va cada uno.
> La imagen de cada pod la descarga el nodo desde **ECR** usando su rol IAM.

```
 GitHub (código) ──push/PR──► GitHub Actions (CI: tests, E2E, validación)
                                    │  OIDC: credenciales temporales, sin claves
                                    ▼
                               Amazon ECR  (imágenes mini-netflix/<servicio>:<sha>)
                                    │  pull (rol IAM de los nodos)
 ┌──────────────── VPC us-east-2 ───┼──────────────────────────────────────────┐
 │  EKS control plane (AWS) ◄── kubectl / CD ── decide dónde corre cada pod    │
 │        │ registra                                                           │
 │  ┌─────▼──────── subred privada ──────────────┐  NAT ─► Internet            │
 │  │ Nodo EC2 #1 (us-east-2a)  Nodo EC2 #2 (b)  │                             │
 │  │  pods: catalogo, rankings, frontend, DBs…  │◄── HPA (metrics-server)     │
 │  │  DaemonSets: cloudwatch-agent, fluent-bit ─┼──► CloudWatch (métricas/logs)│
 │  └────────────────────────────────────────────┘                             │
 │  Load Balancer (subred pública) ──► Service frontend ──► pods frontend      │
 └─────────────────────────────────────────────────────────────────────────────┘
                     ▲
                Usuario / k6
```

| Pieza | Qué es | Cómo comprobarlo |
|---|---|---|
| Terraform | Crea VPC, EKS, nodos, ECR, IAM, dashboard | `terraform -chdir=infra/terraform state list` |
| EKS | Plano de control | `aws eks describe-cluster --name mini-netflix-eks` |
| Nodo | EC2 registrada en EKS | `kubectl get nodes -o custom-columns=NODO:.metadata.name,EC2:.spec.providerID` |
| Pod | Contenedor corriendo **en** un nodo | `kubectl -n mini-netflix get pods -o wide` (columna `NODE`) |
| Imagen | Viene de ECR | `kubectl -n mini-netflix describe pod <pod> \| grep -E 'Image:\|Pulled'` |
| Service/ELB | Entrada pública a los pods | `kubectl -n mini-netflix get svc frontend` |
| HPA | Cambia el nº de pods según CPU | `kubectl -n mini-netflix get hpa` |
| CloudWatch | Métricas y logs enviados por agentes en cada nodo | `kubectl -n amazon-cloudwatch get pods -o wide` |

---

## Etapa 0 — Obtener el código (Todos)

```bash
# Primera vez
git clone https://github.com/PatrikRam/mini-netflix.git && cd mini-netflix

# Cada vez que empiezas a trabajar
git switch main && git pull
```

Mientras el PR de infraestructura no esté fusionado, usar su rama:

```bash
git fetch origin && git switch feature/infra-eks-oidc-us-east-2 && git pull
```

Herramientas: `git`, `docker`, `aws` (CLI v2), `kubectl`, `gh`, `k6`, `envsubst` (paquete `gettext-base`)
y, solo P1, `terraform` ≥ 1.6. Instalación: [RUNBOOK D.1](../infra/RUNBOOK.md#d1--instalar-herramientas-ubuntuwsl).

---

## Etapa 1 — Credenciales (nada se sube al repositorio)

| Quién | Credencial | Cómo se obtiene |
|---|---|---|
| P1 | Usuario IAM `admin-devops` (perfil `default`) | Ya configurado (`aws configure`). Rotar: `scripts/refresh-aws-secrets.sh rotate-keys` |
| Equipo | Usuario IAM propio + rol `mini-netflix-team` | P1 los crea (abajo); cada uno genera **su** access key |
| GitHub Actions | Rol `mini-netflix-github-actions` vía **OIDC** | Terraform. **No** usa claves: Variables `AWS_ROLE_ARN`, `AWS_REGION`, `EKS_CLUSTER_NAME`, `ECR_REGISTRY` |
| Bases de datos | Secrets de Kubernetes aleatorios | `scripts/deploy-inicial.sh` (solo existen en el clúster) |
| GitHub | Cuenta con acceso de escritura al repo | `gh auth login` (para lanzar el workflow) |

**P1 — dar acceso al equipo (una vez):**

```bash
for U in persona2 persona3 persona4; do       # usar los nombres reales
  aws iam create-user --user-name $U
  aws iam create-login-profile --user-name $U --password "$(openssl rand -base64 18)Aa1!" --password-reset-required
  aws iam attach-user-policy --user-name $U --policy-arn arn:aws:iam::aws:policy/IAMUserChangePassword
  aws iam put-user-policy --user-name $U --policy-name self-manage-keys --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["iam:CreateAccessKey","iam:DeleteAccessKey","iam:ListAccessKeys","iam:UpdateAccessKey","iam:GetUser"],"Resource":"arn:aws:iam::*:user/${aws:username}"}]}'
done
aws iam list-users --query 'Users[?starts_with(UserName,`persona`)].Arn'
# Pegar esos ARN en infra/terraform/terraform.tfvars -> team_member_arns = [...]
terraform -chdir=infra/terraform apply
terraform -chdir=infra/terraform output team_role_arn
```

Enviar a cada compañero **por privado** (nunca en Git ni en el grupo): ID de cuenta, usuario, contraseña temporal.
La contraseña se muestra con `aws iam create-login-profile ...` (o defínela tú y anótala).

**Equipo — configurar la máquina (una vez):**

```bash
# 1. Consola AWS con tu usuario -> cambiar contraseña -> IAM -> tu usuario -> Security credentials -> Create access key (CLI)
aws configure --profile mini-netflix-base          # tu key, region us-east-2, output json
cat >> ~/.aws/config <<'EOF'

[profile mini-netflix]
role_arn = arn:aws:iam::<ACCOUNT_ID>:role/mini-netflix-team
source_profile = mini-netflix-base
region = us-east-2
EOF
echo 'export AWS_PROFILE=mini-netflix AWS_REGION=us-east-2' >> ~/.bashrc && source ~/.bashrc

aws sts get-caller-identity                         # debe decir assumed-role/mini-netflix-team
scripts/refresh-aws-secrets.sh kubeconfig           # conecta kubectl al clúster de Ohio
kubectl get nodes                                   # 2 nodos Ready
gh auth login
```

---

## Etapa 2 — Levantar todo · PDF 4.4 (P1, ~25 min)

```bash
scripts/reconstruir.sh
```

Hace, en orden: `terraform plan` + `apply` (pide confirmación) → `bootstrap-k8s.sh` (kubeconfig, nodos Ready,
namespace, metrics-server) → Variables de GitHub → build y push de las 5 imágenes a ECR → `deploy-inicial.sh`.

Paso a paso equivalente (para mostrar cada pieza en el video):

```bash
cd infra/terraform
terraform init
terraform plan -out=tfplan          # qué se va a crear
terraform apply tfplan
terraform output                    # output documentado
cd ../..
scripts/bootstrap-k8s.sh
scripts/refresh-aws-secrets.sh github
export IMAGE_TAG=manual-$(git rev-parse --short HEAD)
REG=$(terraform -chdir=infra/terraform output -raw ecr_registry)
aws ecr get-login-password | docker login -u AWS --password-stdin $REG
for s in catalogo calificaciones rankings recomendaciones frontend; do
  docker build -t $REG/mini-netflix/$s:$IMAGE_TAG ./$s && docker push $REG/mini-netflix/$s:$IMAGE_TAG
done
scripts/deploy-inicial.sh
```

---

## Etapa 3 — Ver la infraestructura (Equipo)

```bash
export AWS_REGION=us-east-2 NS=mini-netflix C=mini-netflix-eks

aws eks describe-cluster --name $C --query 'cluster.{Estado:status,Version:version}' --output table
aws eks describe-nodegroup --cluster-name $C --nodegroup-name mini-netflix-ng \
  --query 'nodegroup.{Estado:status,Tipo:instanceTypes[0],Nodos:scalingConfig.desiredSize}' --output table
aws ec2 describe-instances --filters Name=tag:eks:cluster-name,Values=$C Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].[InstanceId,Placement.AvailabilityZone,PrivateIpAddress]' --output table

# Nodo de Kubernetes = instancia EC2
kubectl get nodes -o custom-columns=NODO:.metadata.name,EC2:.spec.providerID,ESTADO:.status.conditions[-1].type

# Pods = contenedores corriendo DENTRO de los nodos
kubectl -n $NS get pods -o wide
kubectl get pods -A -o custom-columns=NODO:.spec.nodeName --no-headers | sort | uniq -c   # pods por nodo

# La imagen del pod vino de ECR
kubectl -n $NS describe pod -l app=catalogo | grep -E 'Image:|Successfully pulled' | head -2
aws ecr describe-images --repository-name mini-netflix/catalogo --query 'imageDetails[].[imageTags[0],imagePushedAt]' --output table
```

Consola AWS: **EKS → mini-netflix-eks → Compute** (nodos) y **Resources** (pods), **EC2 → Instances**, **ECR → Repositories**.

---

## Etapa 4 — La aplicación funcionando · PDF 4.7 (Todos)

```bash
export FE=http://$(kubectl -n mini-netflix get svc frontend -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo $FE            # P1 comparte esta URL: quien no tenga AWS solo la abre en el navegador

FRONTEND_URL=$FE CATALOGO_URL=$FE/api/catalogo CALIFICACIONES_URL=$FE/api/calificaciones \
RANKINGS_URL=$FE/api/rankings RECOMENDACIONES_URL=$FE/api/recomendaciones bash scripts/smoke.sh

kubectl -n mini-netflix get deploy,svc,hpa
kubectl -n mini-netflix get secrets,configmaps                 # secretos gestionados (valores no visibles en Git)
kubectl -n mini-netflix describe deploy catalogo | grep -E 'Liveness|Readiness|Limits|Requests' -A1
```

**Recuperación ante fallos:**

```bash
kubectl -n mini-netflix get pods -l app=catalogo -w &
kubectl -n mini-netflix delete pod $(kubectl -n mini-netflix get pod -l app=catalogo -o jsonpath='{.items[0].metadata.name}')
for i in $(seq 1 15); do curl -s -o /dev/null -w "%{http_code} " $FE/api/catalogo/peliculas; sleep 1; done; echo   # todo 200
kill %1
kubectl -n mini-netflix exec deploy/rankings -- sh -c 'kill 1'   # el contenedor se reinicia (RESTARTS +1)
kubectl -n mini-netflix get pods -l app=rankings
```

---

## Etapa 5 — Autoscaling (HPA) y prueba de carga · PDF 4.8 (Equipo; la carga la puede lanzar Todos)

```bash
# Terminal 1
kubectl -n mini-netflix get hpa -w
# Terminal 2
kubectl -n mini-netflix get pods -l 'app in (catalogo,rankings)' -w
# Terminal 3 (k6 solo necesita la URL)
k6 run -e BASE_URL=$FE -e VUS=60 -e DURACION=4m pruebas/k6/carga-catalogo.js
# Al final
kubectl -n mini-netflix describe hpa catalogo | sed -n '/Events/,$p'
```

Qué esperar: catalogo pasa de **2 → 6** réplicas en ~40 s y rankings de **2 → 3**. Unos minutos después de
terminar, vuelven a 2. El resumen de k6 (peticiones, p95, % de errores) es el reporte de la prueba de carga.

---

## Etapa 6 — Monitorización con CloudWatch · PDF 4.9 (Equipo)

```bash
terraform -chdir=infra/terraform output -raw cloudwatch_dashboard_url    # P1; o en la consola: CloudWatch → Dashboards → mini-netflix-eks
```

En el dashboard (rango **1 h**, ideal durante/después de la etapa 5): réplicas por Deployment (subida del HPA),
CPU de pods vs. objetivo, CPU/memoria de nodos, reinicios y tabla de logs de error.

```bash
# Logs de los pods en vivo
aws logs tail /aws/containerinsights/mini-netflix-eks/application --follow --format short --filter-pattern '"mini-netflix"'

# Métrica del HPA desde la terminal
aws cloudwatch get-metric-statistics --namespace ContainerInsights --metric-name replicas_ready \
  --dimensions Name=PodName,Value=catalogo Name=ClusterName,Value=mini-netflix-eks Name=Namespace,Value=mini-netflix \
  --start-time $(date -u -d '-1 hour' +%FT%TZ) --end-time $(date -u +%FT%TZ) --period 60 --statistics Maximum \
  --query 'sort_by(Datapoints,&Timestamp)[].[Timestamp,Maximum]' --output text

# Eventos y errores de Kubernetes
kubectl -n mini-netflix get events --sort-by=.lastTimestamp | tail -20
kubectl -n mini-netflix top pods
```

Consola: **CloudWatch → Insights → Container Insights** (vista por clúster, namespace, servicio, pod).

---

## Etapa 7 — CI/CD en acción · PDF 4.2, 4.5, 4.6 y demo final 1-6 (Equipo con `gh`)

Cómo funciona [`.github/workflows/ci-cd.yml`](../.github/workflows/ci-cd.yml):

| Evento | Jobs que corren |
|---|---|
| Push a `main` o PR hacia `main` | **Tests** (pytest catalogo y rankings) → **E2E** (Docker Compose + `scripts/e2e-compose.sh`) · **Validar manifiestos** |
| *Run workflow* manual en `main` | Lo anterior → **ECR** (build + push de las 5 imágenes con el SHA del commit, vía OIDC) → si `deploy_k8s = true`: **CD** (`kubectl set image`, rollout, smoke tests) |

Si un job falla, los siguientes **no se ejecutan** (`needs:`): una prueba rota impide publicar y desplegar.

**Demo: cambiar el frontend y verlo desplegado**

```bash
git switch main && git pull
git switch -c demo/frontend-v2
sed -i 's|<h1>MINI-NETFLIX</h1>|<h1>MINI-NETFLIX · v2</h1>|' frontend/index.html
git commit -am "feat(frontend): mostrar v2 en el encabezado"
git push -u origin demo/frontend-v2
gh pr create --fill --base main
gh pr checks --watch                         # CI: tests + E2E + manifiestos
gh pr merge --merge --delete-branch
git switch main && git pull

gh workflow run "Mini-Netflix CI/CD" --ref main -f deploy_k8s=true
gh run watch                                  # elegir la ejecución; o verla en la pestaña Actions
```

Mientras corre:

```bash
aws ecr describe-images --repository-name mini-netflix/frontend \
  --query 'reverse(sort_by(imageDetails,&imagePushedAt))[0].[imageTags[0],imagePushedAt]' --output text
kubectl -n mini-netflix rollout status deploy/frontend
kubectl -n mini-netflix get deploy frontend -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
curl -s $FE/ | grep -o '<h1>.*</h1>'          # MINI-NETFLIX · v2
kubectl -n mini-netflix rollout undo deploy/frontend    # (opcional) rollback
```

**Demo: pipeline que se detiene por un test fallido**

```bash
git switch -c demo/test-roto
# editar catalogo/catalogo_api/tests.py y cambiar un valor esperado (p. ej. un assertEqual)
git commit -am "test: forzar fallo para la demo"
git push -u origin demo/test-roto && gh pr create --fill --base main --draft
gh pr checks --watch                          # Tests ✗ -> E2E, ECR y CD no se ejecutan
gh pr close --delete-branch                   # descartar
```

Probar localmente antes de subir:

```bash
cd catalogo && python -m pip install -r requirements.txt -r requirements-dev.txt && python -m pytest -v && cd ..
bash scripts/validate-k8s.sh
```

---

## Etapa 8 — Destruir todo · PDF 4.4 y 5 (P1)

```bash
scripts/destruir.sh
```

Pasos que ejecuta (para mostrarlos en el video):

```bash
kubectl delete namespace mini-netflix --wait=true      # 1. borra los Load Balancers creados por Kubernetes
cd infra/terraform
terraform plan -destroy -out=destroy.tfplan            # 2. qué se va a eliminar
terraform apply destroy.tfplan                         # 3. destrucción
terraform state list                                   # 4. vacío
aws eks list-clusters                                  #    []
aws ec2 describe-nat-gateways --filter Name=state,Values=available --query 'NatGateways'   # []
```

**Costo:** encendido ≈ $0.40/h (~$10/día). Si no se usa en más de un día, destruir y reconstruir (Etapa 2, ~25 min).
Tras reconstruir cambia la URL del frontend y las imágenes de ECR se vuelven a publicar.

---

## Guion de la demostración final (PDF sección 8, ≤ 15 min)

| # | Paso del PDF | Etapa | Tiempo |
|---|---|---|---|
| — | (antes de la demo) levantar todo | 2 | 25 min previos |
| 1-2 | Modificar funcionalidad y subir cambios | 7 | 1 min |
| 3 | Pipeline CI | 7 | 3 min |
| 4 | Construcción y publicación de imagen | 7 | 2 min |
| 5 | Despliegue automático en Kubernetes | 7 | 2 min |
| 6 | Acceder a la aplicación | 4 | 1 min |
| 7 | Prueba de carga | 5 | 3 min |
| 8 | HPA y métricas | 5, 6 | 2 min |
| 9 | Cómo se aprovisionó y cómo se reproduce | 2, 3, 8 | 1 min |

Mientras corre el pipeline (pasos 3-5) se puede mostrar la infraestructura (Etapa 3) y el dashboard.

---

## Pendientes frente al PDF (para el responsable de CI/CD)

| Requisito | Estado |
|---|---|
| 4.5 «Ejecutar análisis estático» | `ruff` y `bandit` están en `requirements-dev.txt` pero el workflow **no los ejecuta**. Agregar un paso `ruff check .` / `bandit -r .` en el job *Tests* |
| 4.2 «Generar reportes» / 4.5 «Publicar resultados» | pytest no publica reportes. Agregar `--junitxml=reporte.xml` y `actions/upload-artifact` (o un resumen en `$GITHUB_STEP_SUMMARY`) |
| 4.2 Pruebas de calificaciones y recomendaciones | La matriz de tests solo incluye `catalogo` y `rankings` |
