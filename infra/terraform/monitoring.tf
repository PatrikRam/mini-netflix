# ===========================================================================
# Dashboard de CloudWatch (Container Insights) para la demo de HPA y carga.
# Las métricas las publica el add-on amazon-cloudwatch-observability (eks.tf).
# ===========================================================================

locals {
  ci_ns     = "ContainerInsights"
  hpa_apps  = ["catalogo", "rankings"]
  all_apps  = ["catalogo", "calificaciones", "rankings", "recomendaciones", "frontend"]
  app_logs  = "/aws/containerinsights/${var.cluster_name}/application"
  dash_name = "${var.project}-eks"

  pod_metric = { for m in ["pod_cpu_utilization", "pod_memory_utilization", "replicas_ready", "pod_number_of_container_restarts"] :
    m => [for a in local.all_apps : [local.ci_ns, m, "PodName", a, "ClusterName", var.cluster_name, "Namespace", var.kubernetes_namespace]]
  }
}

resource "aws_cloudwatch_dashboard" "eks" {
  dashboard_name = local.dash_name

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "text", x = 0, y = 0, width = 24, height = 2
        properties = {
          markdown = "## Mini-Netflix en EKS (${var.region})\nRéplicas listas = efecto del **HPA** (catalogo: 2-6 al 50 % CPU · rankings: 2-5 al 60 % CPU). Lanzar carga: `k6 run -e BASE_URL=http://<elb> pruebas/k6/carga-catalogo.js`"
        }
      },
      {
        type = "metric", x = 0, y = 2, width = 12, height = 7
        properties = {
          title   = "Réplicas listas por Deployment (HPA)"
          region  = var.region
          view    = "timeSeries"
          stat    = "Maximum"
          period  = 60
          metrics = local.pod_metric["replicas_ready"]
          yAxis   = { left = { min = 0 } }
        }
      },
      {
        type = "metric", x = 12, y = 2, width = 12, height = 7
        properties = {
          title   = "CPU de pods (% del request) — objetivo HPA catalogo 50 %"
          region  = var.region
          view    = "timeSeries"
          stat    = "Average"
          period  = 60
          metrics = local.pod_metric["pod_cpu_utilization"]
          annotations = {
            horizontal = [{ label = "objetivo catalogo", value = 50 }]
          }
        }
      },
      {
        type = "metric", x = 0, y = 9, width = 8, height = 6
        properties = {
          title  = "Nodos: CPU y memoria (%)"
          region = var.region
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            [local.ci_ns, "node_cpu_utilization", "ClusterName", var.cluster_name],
            [local.ci_ns, "node_memory_utilization", "ClusterName", var.cluster_name],
          ]
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      {
        type = "metric", x = 8, y = 9, width = 8, height = 6
        properties = {
          title   = "Memoria de pods (%)"
          region  = var.region
          view    = "timeSeries"
          stat    = "Average"
          period  = 60
          metrics = local.pod_metric["pod_memory_utilization"]
        }
      },
      {
        type = "metric", x = 16, y = 9, width = 8, height = 6
        properties = {
          title  = "Pods en el namespace y reinicios"
          region = var.region
          view   = "timeSeries"
          stat   = "Maximum"
          period = 60
          metrics = concat(
            [[local.ci_ns, "namespace_number_of_running_pods", "ClusterName", var.cluster_name, "Namespace", var.kubernetes_namespace]],
            local.pod_metric["pod_number_of_container_restarts"],
          )
        }
      },
      {
        type = "log", x = 0, y = 15, width = 24, height = 7
        properties = {
          title  = "Logs de la aplicación: errores (5xx, Error, Exception, Traceback)"
          region = var.region
          view   = "table"
          query  = "SOURCE '${local.app_logs}' | fields @timestamp, kubernetes.pod_name, log | filter kubernetes.namespace_name = '${var.kubernetes_namespace}' | filter log like /(?i)(error|exception|traceback| 5\\d\\d )/ | sort @timestamp desc | limit 50"
        }
      },
    ]
  })
}

output "cloudwatch_dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${local.dash_name}"
}
