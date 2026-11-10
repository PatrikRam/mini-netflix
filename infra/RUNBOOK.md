# Runbook de infraestructura — Mini-Netflix (Persona 1)

Cuenta AWS privada · Región **us-east-2 (Ohio)** · Clúster **`mini-netflix-eks`** · Namespace **`mini-netflix`**

> **Regla de oro:** ninguna access key, token ni kubeconfig se sube al repositorio ni a GitHub Secrets.
> GitHub Actions entra por **OIDC** y kubectl usa **tokens EKS de 15 min** que se regeneran solos.

## Qué arregla esta infraestructura

| Síntoma | Causa | Solución en Terraform |
|---|---|---|
| CI no puede hacer push a ECR | Workflow apuntaba a `us-east-1` (bloqueada por SCP) con keys estáticas del Learner Lab | OIDC provider + rol `mini-netflix-github-actions` (`iam.tf`), región `us-east-2` |
| Nodos no Ready / `ImagePullBackOff` | Rol de nodos sin políticas | `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly` (`eks.tf`) |
| `kubectl` desde Actions: `Unauthorized` | Rol de CI no registrado en el clúster | Access Entries (modo `API`, sin `aws-auth`): Edit en `mini-netflix` + View global |
| Compañeros sin acceso | Solo el creador del clúster es admin | Rol `mini-netflix-team` asumible por los usuarios IAM del equipo |

---

## A. Fase 4 — Crear la infraestructura (Persona 1)

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars   # completar team_member_arns y budget_alert_emails
terraform init
terraform fmt -check && terraform validate
terraform plan -out=tfplan
terraform apply tfplan                          # ~15-20 min
```

Recursos: VPC con 2 subredes públicas (NAT, LoadBalancers) + 2 privadas (nodos), 1 NAT Gateway,
5 repos ECR, EKS 1.37 con node group gestionado (2× t3.medium AL2023), add-ons vpc-cni,
kube-proxy, coredns, CloudWatch Observability, IAM/OIDC y alerta de AWS Budgets.

### Output documentado (para el informe)

```bash
terraform output                                 # tabla legible
terraform output -json > ../../docs/terraform-output.json   # (no contiene secretos)
aws eks describe-cluster --name mini-netflix-eks --region us-east-2 \
  --query 'cluster.{estado:status,version:version,auth:accessConfig.authenticationMode}'
kubectl get nodes -o wide                        # 2 nodos Ready
```

## B. Fase 5 — Namespace y metrics-server

```bash
scripts/bootstrap-k8s.sh
```

Equivale a:

```bash
aws eks update-kubeconfig --region us-east-2 --name mini-netflix-eks --alias mini-netflix-eks
kubectl wait --for=condition=Ready nodes --all --timeout=600s
kubectl apply -f k8s/eks/namespace.yaml
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.8.0/components.yaml
kubectl -n kube-system rollout status deployment/metrics-server
kubectl top nodes
```

### Conectar GitHub Actions (una sola vez, después del apply)

```bash
gh auth login
scripts/refresh-aws-secrets.sh github PatrikRam/mini-netflix
scripts/refresh-aws-secrets.sh purge-legacy PatrikRam/mini-netflix   # borra keys/KUBECONFIG_B64 viejos
```

Esto crea las **Variables** (no secretos) `AWS_ROLE_ARN`, `AWS_REGION`, `EKS_CLUSTER_NAME`, `ECR_REGISTRY`.
El workflow ya usa `permissions: id-token: write` y `role-to-assume: ${{ vars.AWS_ROLE_ARN }}`.

> El rol solo acepta tokens de `repo:PatrikRam/mini-netflix:ref:refs/heads/main`. Si un job usa
> `environment: produccion`, añade `"environment:produccion"` a `github_oidc_subjects` y haz apply.

### Despliegue inicial de catálogo (Persona 1)

```bash
export ECR_REGISTRY=$(terraform -chdir=infra/terraform output -raw ecr_registry)
export IMAGE_TAG=<sha-publicado-por-CI>
kubectl -n mini-netflix create secret generic catalogo-secrets \
  --from-literal=db-password="$(openssl rand -hex 16)" \
  --from-literal=django-secret-key="$(openssl rand -hex 32)"
kubectl -n mini-netflix create configmap peliculas-dataset --from-file=docs/peliculas.json
for f in catalogo-db catalogo catalogo-migrate-job catalogo-hpa; do
  envsubst '${ECR_REGISTRY} ${IMAGE_TAG}' < k8s/eks/$f.yaml | kubectl apply -f -
done
kubectl -n mini-netflix get pods,svc,hpa
```

## Operación durante las sesiones

```bash
scripts/refresh-aws-secrets.sh check        # ¿sesión AWS válida? ¿clúster ACTIVE? ¿nodos?
scripts/refresh-aws-secrets.sh kubeconfig   # si kubectl da "Unauthorized" o cambió de contexto
scripts/refresh-aws-secrets.sh token        # muestra expiración del token EKS (se renueva solo)
scripts/refresh-aws-secrets.sh rotate-keys  # rota tu access key IAM local (cada pocas semanas)
```

Costo aproximado con todo encendido: control plane $0.10/h + 2× t3.medium ~$0.083/h + NAT ~$0.045/h
+ LoadBalancers ~$0.025/h c/u ≈ **$0.30–0.40/h (~$7–9/día)**. Destruye entre sesiones si no se usa varios días.

```bash
aws ce get-cost-and-usage --time-period Start=$(date +%Y-%m-01),End=$(date -d tomorrow +%F) \
  --granularity MONTHLY --metrics UnblendedCost --query 'ResultsByTime[0].Total.UnblendedCost'
```

---

## C. Fase 11 — Destrucción limpia (grabar en video)

Los LoadBalancers y volúmenes creados **por Kubernetes** no están en el state de Terraform; si
no se borran antes, el `destroy` de la VPC queda colgado por ENIs/ELBs huérfanos.

```bash
# 1. Evidencia previa
terraform -chdir=infra/terraform output
kubectl get nodes; kubectl get svc -A | grep LoadBalancer

# 2. Liberar recursos creados por Kubernetes
kubectl delete namespace mini-netflix --wait=true      # Services LoadBalancer + PVC (EBS)
kubectl get svc -A | grep LoadBalancer || echo "sin LoadBalancers"

# 3. Plan de destrucción (mostrar en el video)
cd infra/terraform
terraform plan -destroy -out=destroy.tfplan
terraform apply destroy.tfplan          # equivalente a: terraform destroy -auto-approve
# (alternativa interactiva: terraform destroy  → escribir "yes")

# 4. Verificar que no quedó nada facturable
terraform state list                    # vacío
aws eks list-clusters --region us-east-2
aws ec2 describe-nat-gateways --region us-east-2 --filter Name=state,Values=available --query 'NatGateways[].NatGatewayId'
aws elbv2 describe-load-balancers --region us-east-2 --query 'LoadBalancers[].LoadBalancerName'
aws elb describe-load-balancers --region us-east-2 --query 'LoadBalancerDescriptions[].LoadBalancerName'
aws ec2 describe-volumes --region us-east-2 --filters Name=status,Values=available --query 'Volumes[].VolumeId'
aws logs describe-log-groups --region us-east-2 --log-group-name-prefix /aws/containerinsights/mini-netflix-eks \
  --query 'logGroups[].logGroupName' --output text | xargs -rn1 aws logs delete-log-group --region us-east-2 --log-group-name
```

---

## D. Runbook para el equipo (Personas 2, 3 y 4)

### D.0 — Lo que hace Persona 1 por cada compañero (una vez)

```bash
U=persona2   # repetir con persona3, persona4
aws iam create-user --user-name $U --tags Key=Project,Value=mini-netflix
aws iam create-login-profile --user-name $U --password '<temporal-generada>' --password-reset-required
aws iam attach-user-policy --user-name $U --policy-arn arn:aws:iam::aws:policy/IAMUserChangePassword
# Permiso para que el compañero cree/rote SU PROPIA access key desde la consola:
aws iam put-user-policy --user-name $U --policy-name self-manage-keys --policy-document '{
  "Version":"2012-10-17","Statement":[{"Effect":"Allow",
  "Action":["iam:CreateAccessKey","iam:DeleteAccessKey","iam:ListAccessKeys","iam:UpdateAccessKey","iam:GetUser"],
  "Resource":"arn:aws:iam::*:user/${aws:username}"}]}'
aws iam get-user --user-name $U --query User.Arn --output text   # → añadir a team_member_arns
```

Luego: añadir los 3 ARNs en `terraform.tfvars` → `terraform apply` → compartir por canal privado
(nunca en el repo) el ID de cuenta, el usuario y la contraseña temporal.
El usuario **no tiene permisos propios**: todo lo hace asumiendo el rol `mini-netflix-team`.

### D.1 — Instalar herramientas (Ubuntu/WSL)

```bash
curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip && unzip -q awscliv2.zip && sudo ./aws/install
curl -sSLO "https://dl.k8s.io/release/$(curl -sSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && sudo install kubectl /usr/local/bin/
sudo apt-get install -y gettext-base jq      # envsubst
aws --version && kubectl version --client
```

(macOS: `brew install awscli kubectl gettext jq`)

### D.2 — Configurar credenciales propias (sin compartir claves)

1. Inicia sesión en la consola con el usuario que te dio Persona 1 y cambia la contraseña.
2. IAM → Users → *tu usuario* → Security credentials → **Create access key** (CLI).
3. En tu terminal:

```bash
aws configure --profile mini-netflix-base
#   Access Key / Secret: los tuyos · region: us-east-2 · output: json

cat >> ~/.aws/config <<'EOF'

[profile mini-netflix]
role_arn = arn:aws:iam::<ACCOUNT_ID>:role/mini-netflix-team
source_profile = mini-netflix-base
region = us-east-2
duration_seconds = 14400
EOF

export AWS_PROFILE=mini-netflix                     # añádelo a ~/.bashrc
aws sts get-caller-identity                         # debe mostrar assumed-role/mini-netflix-team/...
```

### D.3 — Conectar kubectl al clúster de Ohio

```bash
aws eks update-kubeconfig --region us-east-2 --name mini-netflix-eks --alias mini-netflix-eks --profile mini-netflix
kubectl config set-context --current --namespace mini-netflix
kubectl auth whoami
kubectl get nodes                                   # 2 nodos Ready
kubectl auth can-i create deployments -n mini-netflix   # yes
```

O con el script del repo: `AWS_PROFILE=mini-netflix scripts/refresh-aws-secrets.sh kubeconfig`

### D.4 — Publicar imágenes en ECR (pruebas manuales; el camino normal es el pipeline)

```bash
export ECR_REGISTRY=<ACCOUNT_ID>.dkr.ecr.us-east-2.amazonaws.com
aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin $ECR_REGISTRY
export IMAGE_TAG=$(git rev-parse --short HEAD)-manual   # tags inmutables: no reutilizar
docker build -t $ECR_REGISTRY/mini-netflix/rankings:$IMAGE_TAG ./rankings
docker push $ECR_REGISTRY/mini-netflix/rankings:$IMAGE_TAG
```

### D.5 — Desplegar tu servicio

```bash
export ECR_REGISTRY=<ACCOUNT_ID>.dkr.ecr.us-east-2.amazonaws.com IMAGE_TAG=<tag>
envsubst '${ECR_REGISTRY} ${IMAGE_TAG} ${CALIFICACIONES_DB_PASSWORD}' < k8s/eks/<servicio>.yaml | kubectl apply -f -
kubectl rollout status deployment/<servicio>
kubectl get pods,svc,hpa
```

### D.6 — Errores frecuentes

| Error | Solución |
|---|---|
| `ExpiredToken` / `InvalidClientTokenId` | `export AWS_PROFILE=mini-netflix` y `aws sts get-caller-identity` |
| `AccessDenied ... sts:AssumeRole` | Tu ARN no está en `team_member_arns` → avisar a Persona 1 |
| `error: You must be logged in to the server (Unauthorized)` | Repetir D.3 con `--profile mini-netflix` |
| `forbidden ... in the namespace "default"` | `kubectl config set-context --current --namespace mini-netflix` |
| `AccessDeniedException ... us-east-1` | Estás en la región equivocada: usa siempre `us-east-2` |
| `ImagePullBackOff` | Revisa que el tag exista: `aws ecr list-images --repository-name mini-netflix/<svc> --region us-east-2` |
| HPA `<unknown>/50%` | metrics-server aún no listo o el pod no tiene `resources.requests.cpu` |
| `tag invalid: The image tag already exists` | Los tags son inmutables: usa un tag nuevo |
