resource "aws_ecr_repository" "svc" {
  for_each             = toset(var.services)
  name                 = "${var.project}/${each.key}"
  image_tag_mutability = "IMMUTABLE" # una etiqueta (el SHA del commit) nunca cambia de contenido
  force_delete         = true        # permite terraform destroy aunque haya imágenes

  image_scanning_configuration { scan_on_push = true }

  encryption_configuration { encryption_type = "AES256" }
}

# Conserva solo las últimas 15 imágenes por servicio (controla el costo de almacenamiento)
resource "aws_ecr_lifecycle_policy" "svc" {
  for_each   = aws_ecr_repository.svc
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Mantener las 15 imagenes mas recientes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 15
      }
      action = { type = "expire" }
    }]
  })
}
