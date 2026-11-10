#!/usr/bin/env bash
# =============================================================================
# demo.sh — Recorrido completo del Proyecto Integrador para GRABAR LA PANTALLA.
#
# Uso:
#   scripts/demo.sh                 # etapas 1-6 en orden, con pausas (Enter para seguir)
#   scripts/demo.sh 4               # solo una etapa (útil para repetir una toma)
#   scripts/demo.sh 5 6             # varias etapas
#   scripts/demo.sh destruir        # etapa 7: destrucción limpia
#   scripts/demo.sh reconstruir     # etapa 8: volver a levantar todo
#   DEMO_AUTO=1 scripts/demo.sh 1   # sin pausas
#   DEMO_K6_DURACION=2m DEMO_K6_VUS=60 scripts/demo.sh 5
#
# Etapas (PDF):
#   1 Infraestructura (IaC, EKS, nodos EC2, ECR)          4.4
#   2 Aplicación funcionando + smoke tests                 4.7 / demo 6
#   3 Kubernetes: secrets, probes, recursos, self-healing  4.7
#   4 CI/CD: cambio -> PR -> CI -> merge -> CD automático  4.1, 4.2, 4.5, 4.6 / demo 1-5
#   5 Prueba de carga k6 + HPA en vivo + gráficos          4.8 / demo 7-8
#   6 CloudWatch: dashboard, métricas, logs, eventos       4.9 / demo 8
#   7 Destrucción (terraform plan -destroy / apply)        4.4, 5 / demo 9
#   8 Reconstrucción desde cero                            4.4 / demo 9
#
# Requiere: aws, kubectl, gh, git, k6, curl. (terraform solo Persona 1)
# Evidencias generadas: evidencias/<fecha>/ (ignorado por git)
# =============================================================================
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

export AWS_REGION="${AWS_REGION:-us-east-2}"
NS="${NAMESPACE:-mini-netflix}"
CLUSTER="${CLUSTER_NAME:-mini-netflix-eks}"
REPO="${GITHUB_REPO:-PatrikRam/mini-netflix}"
K6_VUS="${DEMO_K6_VUS:-60}"
K6_DURACION="${DEMO_K6_DURACION:-3m}"
EVID="evidencias/$(date +%Y%m%d-%H%M)"
mkdir -p "$EVID"

# ---------------------------------------------------------------- utilidades
B=$'\033[1m'; C=$'\033[1;36m'; G=$'\033[1;32m'; Y=$'\033[1;33m'; R=$'\033[1;31m'; D=$'\033[2m'; N=$'\033[0m'
mask() { sed -E 's/[0-9]{12}/<cuenta>/g'; }          # nunca mostrar el ID de cuenta en el video
titulo() {
  echo; echo "${C}══════════════════════════════════════════════════════════════════════${N}"
  echo "${C}  $*${N}"
  echo "${C}══════════════════════════════════════════════════════════════════════${N}"
}
nota()  { echo "${D}# $*${N}"; }
ok()    { echo "${G}✔ $*${N}"; }
warn()  { echo "${Y}⚠ $*${N}"; }
pausa() { [ -n "${DEMO_AUTO:-}" ] && return 0; echo; read -r -p "${Y}▶ Enter para continuar...${N}" _; }
run()   { echo; echo "${B}\$ $*${N}"; eval "$*" 2>&1 | mask; return "${PIPESTATUS[0]}"; }
abrir() { [ -n "${DEMO_NO_OPEN:-}" ] && return 0; command -v xdg-open >/dev/null && { xdg-open "$1" >/dev/null 2>&1 & }; }
need()  { command -v "$1" >/dev/null || { echo "${R}Falta '$1'${N}"; exit 1; }; }
tf_ok() { command -v terraform >/dev/null && [ -d infra/terraform/.terraform ] && terraform -chdir=infra/terraform output cluster_name >/dev/null 2>&1; }
fe_url() { echo "http://$(kubectl -n "$NS" get svc frontend -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)"; }

for t in aws kubectl curl; do need "$t"; done

# Antes de las etapas que usan la aplicación: comprobar que está desplegada y accesible
verificar_app() {
  local faltan=() lb
  kubectl get nodes >/dev/null 2>&1 || {
    echo "${R}✖ kubectl no conecta con el clúster. Ejecuta: scripts/refresh-aws-secrets.sh kubeconfig${N}"; exit 1; }
  for d in catalogo calificaciones rankings recomendaciones frontend; do
    kubectl -n "$NS" get deploy "$d" >/dev/null 2>&1 || faltan+=("$d")
  done
  if [ ${#faltan[@]} -gt 0 ]; then
    echo "${R}✖ La aplicación no está desplegada (faltan: ${faltan[*]}).${N}"
    echo "  Si acabas de reconstruir y falló a medias:  DESDE=4 scripts/reconstruir.sh"
    echo "  Si ya hay imágenes en ECR:                  IMAGE_TAG=<tag> scripts/deploy-inicial.sh"
    exit 1
  fi
  lb=$(kubectl -n "$NS" get svc frontend -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  [ -n "$lb" ] || { echo "${R}✖ El LoadBalancer del frontend aún no tiene URL. Espera 1-2 min y repite.${N}"; exit 1; }
  for _ in $(seq 1 18); do curl -sf -o /dev/null --max-time 5 "http://$lb/" && return 0; sleep 10; done
  echo "${R}✖ http://$lb no responde todavía (el DNS de un ELB nuevo tarda hasta 3 min).${N}"; exit 1
}

# ===================================================================== 1
etapa1() {
  titulo "1/6 · INFRAESTRUCTURA COMO CÓDIGO (Terraform → VPC, EKS, EC2, ECR)   [PDF 4.4]"
  if tf_ok; then
    nota "Todo lo creado por Terraform (estado):"
    run "terraform -chdir=infra/terraform state list | sed 's/\\[.*//' | sort | uniq -c | sort -rn | head -20"
    run "terraform -chdir=infra/terraform state list | wc -l"
    nota "Outputs documentados:"
    run "terraform -chdir=infra/terraform output"
  else
    warn "Sin state de Terraform en esta máquina (normal para el equipo): se muestra desde AWS."
  fi
  pausa
  nota "Clúster EKS = plano de control administrado por AWS"
  run "aws eks describe-cluster --name $CLUSTER --query 'cluster.{Estado:status,Version:version,Autenticacion:accessConfig.authenticationMode,Endpoint_publico:resourcesVpcConfig.endpointPublicAccess}' --output table"
  nota "Node group gestionado: los worker nodes"
  run "aws eks describe-nodegroup --cluster-name $CLUSTER --nodegroup-name mini-netflix-ng --query 'nodegroup.{Estado:status,AMI:amiType,Tipo:instanceTypes[0],Min:scalingConfig.minSize,Deseado:scalingConfig.desiredSize,Max:scalingConfig.maxSize}' --output table"
  nota "Las instancias EC2 detrás de los nodos (sin IP pública: subredes privadas)"
  run "aws ec2 describe-instances --filters Name=tag:eks:cluster-name,Values=$CLUSTER Name=instance-state-name,Values=running --query 'Reservations[].Instances[].[InstanceId,InstanceType,Placement.AvailabilityZone,PrivateIpAddress,PublicIpAddress||\`ninguna\`]' --output table"
  pausa
  nota "Cada NODO de Kubernetes ES una instancia EC2 (providerID):"
  run "kubectl get nodes -o custom-columns=NODO:.metadata.name,EC2:.spec.providerID,ESTADO:.status.conditions[-1].type,VERSION:.status.nodeInfo.kubeletVersion"
  nota "Los PODS corren DENTRO de los nodos (EKS decide en cuál):"
  run "kubectl -n $NS get pods -o custom-columns=POD:.metadata.name,NODO:.spec.nodeName,ESTADO:.status.phase"
  run "kubectl get pods -A -o custom-columns=NODO:.spec.nodeName --no-headers | sort | uniq -c"
  pausa
  nota "Las imágenes de los pods vienen de Amazon ECR:"
  run "aws ecr describe-repositories --query 'repositories[].[repositoryName,imageTagMutability,imageScanningConfiguration.scanOnPush]' --output table"
  run "kubectl -n $NS get deploy -o custom-columns=DEPLOYMENT:.metadata.name,IMAGEN:.spec.template.spec.containers[0].image"
  nota "Permisos: quién puede entrar al clúster (Access Entries, sin claves en GitHub)"
  run "aws eks list-access-entries --cluster-name $CLUSTER --output table"
  pausa
}

# ===================================================================== 2
etapa2() {
  titulo "2/6 · APLICACIÓN FUNCIONANDO EN EKS   [PDF 4.7 · demo paso 6]"
  run "kubectl -n $NS get deploy,svc,hpa"
  FE=$(fe_url)
  echo; ok "URL pública: $FE"
  abrir "$FE"
  pausa
  nota "Smoke tests contra la URL pública (frontend → microservicios)"
  run "FRONTEND_URL=$FE CATALOGO_URL=$FE/api/catalogo CALIFICACIONES_URL=$FE/api/calificaciones RANKINGS_URL=$FE/api/rankings RECOMENDACIONES_URL=$FE/api/recomendaciones bash scripts/smoke.sh"
  nota "Respuestas reales de las APIs:"
  run "curl -s $FE/api/catalogo/peliculas | python3 -c 'import sys,json; d=json.load(sys.stdin); print(len(d), \"películas\"); [print(\"  \", p[\"id\"], p[\"titulo\"], \"-\", p[\"genero\"]) for p in d[:5]]'"
  run "curl -s $FE/api/rankings/rankings/top10 | python3 -m json.tool | head -15"
  run "curl -s $FE/api/recomendaciones/recomendaciones/1 | python3 -m json.tool | head -12"
  pausa
}

# ===================================================================== 3
etapa3() {
  titulo "3/6 · KUBERNETES: configuración, secretos, probes y recuperación ante fallos   [PDF 4.7]"
  nota "Secretos y configuración (los valores NO están en Git: se generan en el clúster)"
  run "kubectl -n $NS get secrets,configmaps"
  nota "Readiness/Liveness probes y recursos (requests/limits) del catálogo"
  run "kubectl -n $NS get deploy catalogo -o jsonpath='{range .spec.template.spec.containers[*]}readiness: {.readinessProbe.httpGet.path}  liveness: {.livenessProbe.httpGet.path}{\"\\n\"}requests: {.resources.requests}{\"\\n\"}limits:   {.resources.limits}{\"\\n\"}{end}'"
  pausa
  FE=$(fe_url)
  POD=$(kubectl -n "$NS" get pod -l app=catalogo -o jsonpath='{.items[0].metadata.name}')
  nota "FALLO 1: se elimina un pod del catálogo. El Deployment lo repone y el servicio NO se cae."
  run "kubectl -n $NS get pods -l app=catalogo"
  run "kubectl -n $NS delete pod $POD --wait=false"
  echo; echo "${B}\$ curl cada segundo a /api/catalogo/peliculas${N}"
  for _ in $(seq 1 12); do printf '%s ' "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$FE/api/catalogo/peliculas")"; sleep 1; done; echo
  run "kubectl -n $NS get pods -l app=catalogo"
  pausa
  nota "FALLO 2: se mata el proceso principal de un contenedor. Kubernetes lo reinicia (RESTARTS +1)."
  POD=$(kubectl -n "$NS" get pod -l app=rankings -o jsonpath='{.items[0].metadata.name}')
  run "kubectl -n $NS get pod $POD"
  run "kubectl -n $NS exec $POD -- sh -c 'kill 1'"
  sleep 8
  run "kubectl -n $NS get pod $POD"
  run "kubectl -n $NS get events --field-selector involvedObject.name=$POD --sort-by=.lastTimestamp | tail -5"
  pausa
}

# ===================================================================== 4
etapa4() {
  titulo "4/6 · CI/CD: cambio → PR → CI → merge → build → ECR → despliegue automático   [PDF 4.5, 4.6 · demo 1-5]"
  need gh; need git
  gh auth status >/dev/null 2>&1 || { echo "${R}Ejecuta: gh auth login${N}"; return 1; }
  local ORIG TS BR MSG FE URL PR MERGE_SHA RID
  ORIG=$(git rev-parse --abbrev-ref HEAD)
  TS=$(date +%H:%M)
  BR="demo/frontend-$(date +%Y%m%d-%H%M)"
  FE=$(fe_url)

  nota "Lo que se ve HOY en la aplicación:"
  run "curl -s $FE/ | grep -o '<h1>[^<]*</h1>'"
  pausa

  nota "PASO 1 · Modificar una funcionalidad (encabezado del frontend) en una rama nueva"
  run "git fetch -q origin main && git switch -c $BR origin/main"
  sed -i -E "s|<h1>[^<]*</h1>|<h1>MINI-NETFLIX · demo $TS</h1>|" frontend/index.html
  run "git diff -- frontend/index.html"
  pausa

  nota "PASO 2 · Subir los cambios y abrir un Pull Request"
  run "git add frontend/index.html && git commit -q -m 'feat(frontend): encabezado demo $TS' && git log --oneline -1"
  run "git push -q -u origin $BR"
  URL=$(gh pr create --repo "$REPO" --base main --head "$BR" \
        --title "Demo: encabezado del frontend $TS" \
        --body "Cambio de demostración del pipeline CI/CD (scripts/demo.sh)." 2>&1 | tail -1)
  PR=${URL##*/}
  ok "PR creado: $URL"
  abrir "$URL"
  pausa

  nota "PASO 3 · CI: análisis estático → tests → E2E → validación de manifiestos (obligatorios para el merge)"
  run "gh pr checks $PR --repo $REPO --watch --interval 10"
  pausa

  nota "PASO 4 · Merge del PR a main (GitHub exige que los checks hayan pasado)"
  MERGE_SHA=$(gh api -X PUT "repos/$REPO/pulls/$PR/merge" -f merge_method=merge -q .sha) \
    || { echo "${R}No se pudo hacer merge (¿checks fallidos?)${N}"; git switch -q "$ORIG"; return 1; }
  ok "Merge realizado: ${MERGE_SHA:0:7}"
  gh api -X DELETE "repos/$REPO/git/refs/heads/$BR" >/dev/null 2>&1 || true

  nota "PASO 5 · El merge dispara el pipeline en main: build → push a ECR (OIDC) → deploy → smoke tests"
  for _ in $(seq 1 30); do
    RID=$(gh run list --repo "$REPO" --branch main --event push --limit 5 --json databaseId,headSha \
          -q ".[] | select(.headSha==\"$MERGE_SHA\") | .databaseId" | head -1)
    [ -n "$RID" ] && break; sleep 4
  done
  ok "Ejecución: https://github.com/$REPO/actions/runs/$RID"
  abrir "https://github.com/$REPO/actions/runs/$RID"
  run "gh run watch $RID --repo $REPO --interval 10 --exit-status"
  pausa

  nota "Nueva imagen publicada en ECR con el SHA del commit"
  run "aws ecr describe-images --repository-name mini-netflix/frontend --query 'reverse(sort_by(imageDetails,&imagePushedAt))[:3].[imageTags[0],imagePushedAt]' --output table"
  nota "Kubernetes hizo un rolling update a esa imagen"
  run "kubectl -n $NS get deploy frontend -o jsonpath='{.spec.template.spec.containers[0].image}{\"\\n\"}'"
  run "kubectl -n $NS rollout history deploy/frontend | tail -4"
  run "kubectl -n $NS get pods -l app=frontend"
  nota "El cambio ya está en producción:"
  run "curl -s $FE/ | grep -o '<h1>[^<]*</h1>'"
  abrir "$FE"
  git switch -q "$ORIG" 2>/dev/null || true
  git branch -q -D "$BR" 2>/dev/null || true
  pausa
}

# ===================================================================== 5
etapa5() {
  titulo "5/6 · PRUEBA DE CARGA (k6) + HPA ESCALANDO EN VIVO   [PDF 4.8 · demo 7-8]"
  need k6
  FE=$(fe_url)
  nota "Configuración del autoscaling: mínimo, máximo y métrica (CPU % del request)"
  run "kubectl -n $NS get hpa"
  run "kubectl -n $NS top pods"
  pausa

  nota "Lanzando k6: $K6_VUS usuarios virtuales, $K6_DURACION sostenidos. Gráficos en vivo: http://localhost:5665"
  K6_WEB_DASHBOARD=true K6_WEB_DASHBOARD_PERIOD=5s K6_WEB_DASHBOARD_EXPORT="$EVID/k6-reporte.html" \
    k6 run --quiet -e BASE_URL="$FE" -e VUS="$K6_VUS" -e DURACION="$K6_DURACION" \
    pruebas/k6/carga-catalogo.js > "$EVID/k6-resumen.txt" 2>&1 &
  local K6PID=$!
  sleep 4; abrir "http://localhost:5665"

  echo "HORA     | HPA catalogo (CPU/obj · réplicas) | HPA rankings (CPU/obj · réplicas) | pods Running" | tee "$EVID/hpa-evolucion.txt"
  while kill -0 "$K6PID" 2>/dev/null; do
    linea_hpa | tee -a "$EVID/hpa-evolucion.txt"
    sleep 10
  done
  wait "$K6PID"
  ok "Carga terminada"
  pausa

  nota "Resultado de k6 (latencias, peticiones, errores):"
  run "grep -E 'checks_succeeded|http_req_duration|http_req_failed|http_reqs|iterations|vus_max|✓|✗' $EVID/k6-resumen.txt"
  nota "Decisiones del HPA (eventos):"
  run "kubectl -n $NS describe hpa catalogo | sed -n '/Events/,\$p' | grep -E 'Rescale|Type|----'"
  run "kubectl -n $NS describe hpa rankings | sed -n '/Events/,\$p' | grep -E 'Rescale|Type|----'"
  run "kubectl -n $NS get pods -l 'app in (catalogo,rankings)' -o wide"
  pausa

  nota "Sin carga, el HPA vuelve al mínimo (ventana de estabilización 60 s). Observando 2 min:"
  for _ in $(seq 1 12); do linea_hpa | tee -a "$EVID/hpa-evolucion.txt"; sleep 10; done
  ok "Reporte HTML con gráficos de k6: $EVID/k6-reporte.html"
  abrir "$EVID/k6-reporte.html"
  pausa
}

linea_hpa() {
  local hc hr p
  hc=$(kubectl -n "$NS" get hpa catalogo --no-headers 2>/dev/null | awk '{print $3,$4,"·",$7}')
  hr=$(kubectl -n "$NS" get hpa rankings --no-headers 2>/dev/null | awk '{print $3,$4,"·",$7}')
  p=$(kubectl -n "$NS" get pods -l 'app in (catalogo,rankings)' --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
  printf '%s | %-33s | %-33s | %s\n' "$(date +%T)" "$hc" "$hr" "$p"
}

# ===================================================================== 6
etapa6() {
  titulo "6/6 · MONITORIZACIÓN CON CLOUDWATCH (Container Insights)   [PDF 4.9 · demo 8]"
  local DASH="https://$AWS_REGION.console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards/dashboard/mini-netflix-eks"
  nota "Agentes que envían métricas y logs desde cada nodo (DaemonSets)"
  run "kubectl -n amazon-cloudwatch get pods -o wide"
  ok "Dashboard: $DASH"
  abrir "$DASH"
  pausa

  nota "Gráfico desde CloudWatch: réplicas listas de catalogo en los últimos 45 min (efecto del HPA)"
  grafico_cw replicas_ready Maximum "PodName=catalogo Namespace=$NS"
  nota "CPU de los pods de catalogo (% del request)"
  grafico_cw pod_cpu_utilization Average "PodName=catalogo Namespace=$NS"
  nota "CPU de los nodos (%)"
  grafico_cw node_cpu_utilization Average ""
  pausa

  nota "CloudWatch Logs Insights: peticiones HTTP por servicio en la última hora (sin probes)"
  logs_insights "filter kubernetes.namespace_name = '$NS' and log like /HTTP\\/1/ and log not like /kube-probe|\\/health/
| stats count(*) as peticiones by kubernetes.container_name as servicio | sort peticiones desc"
  nota "CloudWatch Logs Insights: últimas líneas de log de la aplicación (sin probes)"
  logs_insights "fields @timestamp, kubernetes.pod_name as pod, log
| filter kubernetes.namespace_name = '$NS' and log not like /kube-probe|\\/health/
| sort @timestamp desc | limit 12"
  nota "Eventos de Kubernetes (escalados, reinicios, despliegues)"
  run "kubectl -n $NS get events --sort-by=.lastTimestamp | grep -E 'Scaled|Killing|Pulled|Started|BackOff|Unhealthy|SuccessfulRescale' | tail -15"
  nota "Consumo actual de CPU y memoria"
  run "kubectl top nodes"
  run "kubectl -n $NS top pods"
  pausa
}

# Ejecuta una consulta de CloudWatch Logs Insights (última hora) y la muestra como tabla
logs_insights() {
  local q=$1 qid st
  echo "${B}\$ aws logs start-query --log-group-name /aws/containerinsights/$CLUSTER/application --query-string \"…\"${N}"
  echo "${D}$q${N}"
  qid=$(aws logs start-query --log-group-name "/aws/containerinsights/$CLUSTER/application" \
        --start-time $(( $(date +%s) - 3600 )) --end-time "$(date +%s)" \
        --query-string "$q" --query queryId --output text) || return 0
  for _ in $(seq 1 30); do
    st=$(aws logs get-query-results --query-id "$qid" --query status --output text)
    [ "$st" = "Complete" ] && break; sleep 2
  done
  aws logs get-query-results --query-id "$qid" --query results --output json | python3 -c '
import sys, json
rows = json.load(sys.stdin)
if not rows: print("  (sin resultados)"); sys.exit()
for r in rows:
    print("  " + "  ".join(c["value"].strip()[:120].ljust(22) for c in r if c["field"] != "@ptr"))
' | mask
}

# Gráfico de barras en la terminal a partir de una métrica de CloudWatch
grafico_cw() {
  local metric=$1 stat=$2 extra=$3 dims
  dims="Name=ClusterName,Value=$CLUSTER"
  for kv in $extra; do dims="$dims Name=${kv%%=*},Value=${kv#*=}"; done
  echo "${B}\$ aws cloudwatch get-metric-statistics --metric-name $metric ...${N}"
  # shellcheck disable=SC2086
  aws cloudwatch get-metric-statistics --namespace ContainerInsights --metric-name "$metric" \
    --dimensions $dims --statistics "$stat" --period 180 \
    --start-time "$(date -u -d '-45 min' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
    --query "sort_by(Datapoints,&Timestamp)[].[Timestamp,$stat]" --output text |
  python3 -c '
import sys
from datetime import datetime
rows=[l.split() for l in sys.stdin if l.strip()]
if not rows: print("  (sin datos todavía: Container Insights publica cada ~1 min)"); sys.exit()
mx=max(float(v) for _,v in rows) or 1
for t,v in rows:
    v=float(v); h=datetime.fromisoformat(t).astimezone().strftime("%H:%M")
    barra = "█" * max(1, int(v / mx * 50))
    print(f"  {h} {barra:<50} {v:6.1f}")
'
}

# ===================================================================== 7 / 8
etapa_destruir()    { titulo "7 · DESTRUCCIÓN LIMPIA DE LA INFRAESTRUCTURA   [PDF 4.4, 5 · demo 9]"; scripts/destruir.sh || exit 1; }
etapa_reconstruir() {
  titulo "8 · RECONSTRUCCIÓN COMPLETA DESDE CÓDIGO   [PDF 4.4 · demo 9]"
  scripts/reconstruir.sh || { echo "${R}✖ La reconstrucción no terminó: corrige y reanuda con DESDE=<paso> scripts/reconstruir.sh${N}"; exit 1; }
}

# ===================================================================== main
[ $# -eq 0 ] && set -- 1 2 3 4 5 6
titulo "MINI-NETFLIX · Proyecto Integrador Cloud Computing · AWS $AWS_REGION · $(date '+%d/%m/%Y %H:%M')"
nota "Identidad AWS: $(aws sts get-caller-identity --query Arn --output text 2>/dev/null | mask)"
nota "Contexto kubectl: $(kubectl config current-context 2>/dev/null)"
nota "Evidencias en: $EVID/"
for e in "$@"; do
  case "$e" in 2|3|4|5|6) verificar_app; break ;; esac
done
for e in "$@"; do
  case "$e" in
    1) etapa1 ;; 2) etapa2 ;; 3) etapa3 ;; 4) etapa4 ;; 5) etapa5 ;; 6) etapa6 ;;
    7|destruir) etapa_destruir ;;
    8|reconstruir) etapa_reconstruir ;;
    *) echo "Etapa desconocida: $e"; exit 1 ;;
  esac
done
titulo "FIN · evidencias en $EVID/"
ls -1 "$EVID"
