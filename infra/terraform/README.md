# Terraform AWS Deployment

This folder provisions the AWS infrastructure for the backend and frontend apps, including VPC networking, EC2 instances, and (optionally) an RDS database.

## Prerequisites

- Terraform >= 1.5
- AWS credentials configured locally (for example via `aws configure` or environment variables)
- An existing EC2 key pair name for SSH access
- An S3 bucket and DynamoDB table for remote state locking

## Remote State (S3 + DynamoDB)

Update `backend.tf` with your bucket/table values **or** supply them during init:

```bash
terraform init \
  -backend-config="bucket=YOUR_BUCKET" \
  -backend-config="key=ci-cd-project/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=YOUR_DYNAMO_TABLE" \
  -backend-config="encrypt=true"
```

## Inputs

Create a `terraform.tfvars` with the required values:

```hcl
key_pair_name = "your-key-pair"
use_json_storage = true
ssh_cidr = "YOUR_IP/32"
```

Optional values for RDS (when `use_json_storage = false`):

```hcl
db_password = "change-me"
db_backup_retention_period = 7
db_skip_final_snapshot = false
db_deletion_protection = true
db_final_snapshot_identifier = "ci-cd-project-final"
```

Optional values for frontend build output:

```hcl
frontend_build_output_path = "dist/client"
```

Optional values for SSM/Secrets Manager:

```hcl
use_ssm_parameters   = true
ssm_parameter_path   = "/ci-cd-project/backend"
db_password_secret_arn = "arn:aws:secretsmanager:REGION:ACCOUNT:secret:NAME"
```

When using database storage, the backend expects DB credentials from SSM or Secrets Manager (to avoid plaintext in user data). Provide either `use_ssm_parameters = true` with the required parameters or `db_password_secret_arn`.

When `use_ssm_parameters = true`, the instances read these parameters:

- `${ssm_parameter_path}/DB_HOST`
- `${ssm_parameter_path}/DB_USER`
- `${ssm_parameter_path}/DB_PASSWORD`
- `${ssm_parameter_path}/DB_NAME`

## Apply

```bash
terraform plan
terraform apply
```

## Destroy

```bash
terraform destroy
```

## Outputs

Terraform outputs include the backend and frontend public URLs and the RDS endpoint (if provisioned).
