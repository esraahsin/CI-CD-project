# Required
key_pair_name = "my-sandbox-key"   # must exist in AWS already
ssh_cidr      = "102.172.207.55/32"    # get it from https://checkip.amazonaws.com

# Storage
use_json_storage = false                # false = uses RDS MySQL
use_ssm_parameters = true

# Correct Angular 19 build output
frontend_build_output_path = "dist/client/browser"

# Optional overrides
aws_region   = "us-east-1"
project_name = "ci-cd-project"
environment  = "dev"
