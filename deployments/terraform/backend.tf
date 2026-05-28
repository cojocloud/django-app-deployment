terraform {
  backend "s3" {
    bucket  = "django-app1-tfstate"
    region  = "us-east-1"
    key     = "state/terraform.tfstate"
    encrypt = true
  }
}
