terraform {
  backend "s3" {
    bucket         = "seunadio-tfstate"
    key            = "casetriage/infra.tfstate"
    region         = "eu-west-2"
    encrypt        = true
    dynamodb_table = "terraform-states-table"
  }
}

## Make sure the bucket is created