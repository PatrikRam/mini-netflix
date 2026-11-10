# Alerta de presupuesto mensual (Persona 1 vigila el gasto).
# Se crea solo si budget_alert_emails tiene al menos un correo (definido en terraform.tfvars).
resource "aws_budgets_budget" "monthly" {
  count = length(var.budget_alert_emails) > 0 ? 1 : 0

  name         = "${var.project}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Avisos al 50 % y 80 % del gasto real, y al 100 % del pronosticado
  dynamic "notification" {
    for_each = [50, 80]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = var.budget_alert_emails
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.budget_alert_emails
  }
}
