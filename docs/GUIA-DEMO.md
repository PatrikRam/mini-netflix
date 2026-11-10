# Guía de demostración y operación — Mini-Netflix en AWS EKS

Región **us-east-2** · Clúster **mini-netflix-eks** · Namespace **mini-netflix**.
Infraestructura y credenciales: [infra/RUNBOOK.md](../infra/RUNBOOK.md).

Variables que usan casi todos los comandos (ejecutar una vez por terminal):

```bash
export AWS_REGION=us-east-2 NS=mini-netflix
export FE=http://$(kubectl -n $NS get svc frontend -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo $FE
```

---

## 1. La aplicación corriendo (requisito 4.7: orquestación)

```bash
kubectl -n $NS get deploy,pods,svc,hpa -o wide
xdg-open $FE                      # o abrir la URL en el navegador

# Smoke tests contra la URL pública
FRONTEND_URL=$FE CATALOGO_URL=$FE/api/catalogo CALIFICACIONES_URL=$FE/api/calificaciones \
RANKINGS_URL=$FE/api/rankings RECOMENDACIONES_URL=$FE/api/recomendaciones bash scripts/smoke.sh

# APIs individuales
curl -s $FE/api/catalogo/peliculas | head -c 300; echo
curl -s $FE/api/rankings/rankings/top10 | head -c 300; echo
curl -s $FE/api/recomendaciones/recomendaciones/1 | head -c 300; echo
```

**Secrets y config:** `kubectl -n $NS get secrets,configmaps` (los valores nunca están en Git).
**Probes:** `kubectl -n $NS describe deploy catalogo | grep -A2 -E 'Liveness|Readiness'`.

### Recuperación ante fallos (self-healing)

```bash
kubectl -n $NS get pods -l app=catalogo -w &                 # observar
# "Matar" UNA réplica: la otra sigue atendiendo (todo 200) y el Deployment repone la borrada
kubectl -n $NS delete pod $(kubectl -n $NS get pod -l app=catalogo -o jsonpath='{.items[0].metadata.name}') --wait=false
for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code} " $FE/api/catalogo/peliculas; sleep 1; done; echo
kill %1
# (Si se borran TODAS las réplicas a la vez hay ~6 s de 502 hasta que las nuevas pasan el readiness probe:
#  por eso hay mínimo 2 réplicas.)

# Fallo dentro del contenedor: el proceso muere y kubelet reinicia el contenedor
kubectl -n $NS exec deploy/rankings -- sh -c 'kill 1'
kubectl -n $NS get pods -l app=rankings      # RESTARTS aumenta
```

---

## 2. HPA y prueba de carga (requisito 4.8)

| Deployment | min | max | métrica |
|---|---|---|---|
| catalogo | 2 | 6 | CPU 50 % del request (50m) |
| rankings | 2 | 5 | CPU 60 % del request (100m) |

Abrir **3 terminales**:

```bash
# Terminal 1: HPA en vivo
kubectl -n mini-netflix get hpa -w

# Terminal 2: pods escalando
kubectl -n mini-netflix get pods -l 'app in (catalogo,rankings)' -w

# Terminal 3: carga (60 usuarios virtuales, 4 min sostenidos)
k6 run -e BASE_URL=$FE -e VUS=60 -e DURACION=4m pruebas/k6/carga-catalogo.js
```

Después:

```bash
kubectl -n $NS describe hpa catalogo | sed -n '/Events/,$p'   # "New size: 6; reason: cpu ... above target"
kubectl -n $NS top pods
```

Resultado obtenido (10-nov-2026): catalogo **2 → 6** réplicas en ~40 s (CPU 490 % del request),
rankings **2 → 3**; 15 056 peticiones, p95 = 2.34 s, 4.2 % de errores con catalogo al máximo
(6 réplicas saturadas: subir `maxReplicas` o el límite de CPU reduce el error).
Al terminar, el HPA vuelve a 2 réplicas tras la ventana de estabilización (60 s + bajada gradual).

Instalar k6: <https://grafana.com/docs/k6/latest/set-up/install-k6/> (`sudo apt install k6` tras añadir su repo, o `brew install k6`).

---

## 3. Monitorización con CloudWatch (requisito 4.9)

Dashboard creado por Terraform (`infra/terraform/monitoring.tf`):

```bash
terraform -chdir=infra/terraform output -raw cloudwatch_dashboard_url
```

Muestra: réplicas listas por Deployment (efecto del HPA), CPU de pods vs. objetivo, CPU/memoria de
nodos, memoria de pods, reinicios y una tabla de logs de error. Rango sugerido en la consola: **1 h**.

Desde la terminal:

```bash
# Réplicas de catalogo (evidencia del HPA en CloudWatch)
aws cloudwatch get-metric-statistics --namespace ContainerInsights --metric-name replicas_ready \
  --dimensions Name=PodName,Value=catalogo Name=ClusterName,Value=mini-netflix-eks Name=Namespace,Value=mini-netflix \
  --start-time $(date -u -d '-1 hour' +%FT%TZ) --end-time $(date -u +%FT%TZ) --period 60 --statistics Maximum \
  --query 'sort_by(Datapoints,&Timestamp)[].[Timestamp,Maximum]' --output text

# CPU de los nodos
aws cloudwatch get-metric-statistics --namespace ContainerInsights --metric-name node_cpu_utilization \
  --dimensions Name=ClusterName,Value=mini-netflix-eks \
  --start-time $(date -u -d '-1 hour' +%FT%TZ) --end-time $(date -u +%FT%TZ) --period 300 --statistics Average --output table

# Logs de la aplicación en vivo (todos los pods del namespace)
aws logs tail /aws/containerinsights/mini-netflix-eks/application --follow --format short \
  --filter-pattern '"mini-netflix"'

# Eventos y errores de Kubernetes
kubectl -n $NS get events --sort-by=.lastTimestamp | tail -20
kubectl -n $NS logs deploy/catalogo --tail=20
```

Consola: **CloudWatch → Insights → Container Insights → Performance monitoring** (vista por clúster,
namespace, servicio y pod) y **CloudWatch → Logs → Logs Insights** con el grupo `/aws/containerinsights/mini-netflix-eks/application`:

```
fields @timestamp, kubernetes.pod_name, log
| filter kubernetes.namespace_name = 'mini-netflix'
| sort @timestamp desc | limit 100
```

---

## 4. Demostración del CI/CD (requisitos 4.5, 4.6 y sección 8 del enunciado)

Requisito previo (una vez): el PR de infraestructura con el workflow OIDC debe estar en `main`.

```bash
# 1. Modificar una funcionalidad visible
git switch main && git pull
git switch -c demo/cambio-frontend
sed -i 's|<h1>MINI-NETFLIX</h1>|<h1>MINI-NETFLIX · v2</h1>|' frontend/index.html
git commit -am "feat(frontend): mostrar version v2 en el encabezado"

# 2. Subir los cambios y abrir PR -> corre CI (pytest, E2E con Docker Compose, validación de manifiestos)
git push -u origin demo/cambio-frontend
gh pr create --fill --base main
gh pr checks --watch

# 3. Merge a main
gh pr merge --merge --delete-branch

# 4. Disparar build + push a ECR + despliegue en EKS + smoke tests
gh workflow run "Mini-Netflix CI/CD" --ref main -f deploy_k8s=true
gh run watch $(gh run list --workflow "Mini-Netflix CI/CD" --limit 1 --json databaseId -q '.[0].databaseId')
```

(Desde la web: **Actions → Mini-Netflix CI/CD → Run workflow → main → deploy_k8s ✔**.)

Qué mostrar mientras corre:

```bash
# Nueva imagen en ECR con el SHA del commit
aws ecr describe-images --repository-name mini-netflix/frontend \
  --query 'reverse(sort_by(imageDetails,&imagePushedAt))[0].[imageTags[0],imagePushedAt]' --output text

# Rolling update en vivo (sin caída)
kubectl -n $NS rollout status deploy/frontend
kubectl -n $NS get deploy frontend -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
kubectl -n $NS rollout history deploy/frontend

# El cambio publicado
curl -s $FE/ | grep -o '<h1>.*</h1>'
```

**Pipeline que falla y se detiene** (requisito 4.2): rompe un test (`catalogo/catalogo_api/tests.py`,
p. ej. cambia un `assertEqual`), sube la rama y muestra que el job *Tests* falla y *E2E / ECR / CD* no se ejecutan.

**Rollback** si algo sale mal: `kubectl -n $NS rollout undo deploy/frontend`.

---

## 5. Cómo lo replican los compañeros

Tres niveles, de menor a mayor acceso:

### Nivel 1 — Solo ver la app (sin AWS)
Abrir en el navegador la URL `$FE` que comparte Persona 1 (`kubectl -n mini-netflix get svc frontend`).
Cualquiera puede ejecutar la prueba de carga contra esa URL con k6 (no necesita credenciales):

```bash
k6 run -e BASE_URL=http://<url-del-frontend> pruebas/k6/carga-catalogo.js
```

### Nivel 2 — Ver pods, HPA, logs y CloudWatch (con AWS)
Persona 1 crea su usuario y lo añade a `team_member_arns` (RUNBOOK, sección D.0). Luego cada uno sigue
**RUNBOOK D.1–D.3** (instalar aws/kubectl, perfil `mini-netflix` que asume el rol del equipo, `update-kubeconfig`).
Con eso funcionan **todas** las secciones 1-4 de esta guía, el dashboard y los logs de CloudWatch
(el rol del equipo incluye `CloudWatchReadOnlyAccess`).

```bash
export AWS_PROFILE=mini-netflix
aws eks update-kubeconfig --region us-east-2 --name mini-netflix-eks --alias mini-netflix-eks
kubectl config set-context --current --namespace mini-netflix
kubectl get pods,hpa
```

### Nivel 3 — Correr todo en su propia máquina (sin AWS)

```bash
git clone https://github.com/PatrikRam/mini-netflix.git && cd mini-netflix
cp .env.example .env                       # completar contraseñas locales
docker compose up -d --build
docker compose exec catalogo python manage.py migrate
docker compose exec catalogo python manage.py seed
docker compose exec calificaciones python seed.py
xdg-open http://localhost:8080
bash scripts/smoke.sh
```

HPA en local con **Minikube** (ver `k8s/eks/README.md`):

```bash
minikube start --cpus 4 --memory 6g && minikube addons enable metrics-server
eval $(minikube docker-env)
for s in catalogo calificaciones rankings recomendaciones frontend; do docker build -t local/mini-netflix/$s:dev ./$s; done
kubectl apply -f k8s/eks/namespace.yaml
kubectl -n mini-netflix create secret generic catalogo-secrets --from-literal=db-password=local --from-literal=django-secret-key=local
kubectl -n mini-netflix create configmap peliculas-dataset --from-file=docs/peliculas.json
export ECR_REGISTRY=local IMAGE_TAG=dev CALIFICACIONES_DB_PASSWORD=local
for f in catalogo-db catalogo catalogo-migrate-job catalogo-hpa calificaciones rankings recomendaciones frontend; do
  envsubst '${ECR_REGISTRY} ${IMAGE_TAG} ${CALIFICACIONES_DB_PASSWORD}' < k8s/eks/$f.yaml | kubectl apply -n mini-netflix -f -
done
kubectl -n mini-netflix get pods,hpa -w
k6 run -e BASE_URL=$(minikube service frontend -n mini-netflix --url) pruebas/k6/carga-catalogo.js
```

---

## 6. Apagar, destruir y reconstruir

**Costo encendido:** ≈ $0.40/h ≈ **$10/día** (control plane $0.10 + 2 EC2 $0.08 + NAT $0.045 + 2 ELB $0.05 + CloudWatch).

| Situación | Qué hacer |
|---|---|
| Vuelven a trabajar en < 1 día | Dejarlo encendido |
| Más de 1 día sin usarlo | **Destruir** y reconstruir (~25 min) |
| Después de la demo final | **Destruir** (requisito del enunciado) |

> Escalar los nodos a 0 **no** es buen "apagado": el control plane, el NAT y los ELB siguen cobrando
> (~$6/día) y la app queda caída igual. Destruir/reconstruir es más barato y además demuestra IaC.

```bash
scripts/destruir.sh       # borra namespace (ELBs) -> terraform plan -destroy -> apply -> verifica
scripts/reconstruir.sh    # terraform apply -> bootstrap -> vars GitHub -> build/push -> deploy-inicial
```

Pasos manuales equivalentes a `reconstruir.sh`:

```bash
cd infra/terraform && terraform init && terraform plan -out=tfplan && terraform apply tfplan && cd ../..
scripts/bootstrap-k8s.sh
scripts/refresh-aws-secrets.sh github          # los ARN no cambian, pero no hace daño
# Imágenes: o bien Actions -> Run workflow (deploy_k8s = false), o build local:
export IMAGE_TAG=manual-$(git rev-parse --short HEAD)
REG=$(terraform -chdir=infra/terraform output -raw ecr_registry)
aws ecr get-login-password | docker login -u AWS --password-stdin $REG
for s in catalogo calificaciones rankings recomendaciones frontend; do
  docker build -t $REG/mini-netflix/$s:$IMAGE_TAG ./$s && docker push $REG/mini-netflix/$s:$IMAGE_TAG
done
scripts/deploy-inicial.sh
```

Tras reconstruir: la URL del frontend **cambia** (nuevo ELB); las contraseñas de las BD se regeneran
y los datos de ejemplo se recargan con los Jobs de seed.
