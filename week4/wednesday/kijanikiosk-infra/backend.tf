
terraform {
  backend "s3" {
    bucket         = "kijanikiosk-terraform-state-demo"
    key            = "staging/terraform.tfstate"
    region         = "af-south-1"
    dynamodb_table = "kijanikiosk-tf-locks"
    encrypt        = true
  }
}
