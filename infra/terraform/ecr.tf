resource "aws_ecr_repository" "svc" {
  for_each             = toset(var.services)
  name                 = "${var.project}/${each.key}"
  image_tag_mutability = "IMMUTABLE" # una etiqueta (el SHA del commit) nunca cambia de contenido
  force_delete         = true        # permite terraform destroy aunque haya imágenes

  image_scanning_configuration { scan_on_push = true } # escanea vulnerabilidades al subir
}