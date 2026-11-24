## ----------------------------------------------------------------------------
## Copyright 2017-2020 Cloud Posse, LLC
## Copyright 2026 Raring Group LLC
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##     http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
##
## Modified by Raring Group LLC from cloudposse/terraform-aws-iam-system-user:
## uses the Raring Group context module and adds IAM user and SSM pass-through inputs.
## ----------------------------------------------------------------------------

locals {
  username              = join("", aws_iam_user.default.*.name)
  create_iam_access_key = module.context.enabled && var.create_iam_access_key
  ssm_enabled           = var.ssm_enabled && local.create_iam_access_key

  key_id_ssm_path        = "/system_user/${local.username}/access_key_id"
  secret_ssm_path        = "/system_user/${local.username}/secret_access_key"
  smtp_password_ssm_path = "/system_user/${local.username}/ses_smtp_password"
}

# Defines a user that should be able to write to you test bucket
resource "aws_iam_user" "default" {
  count                = module.context.enabled ? 1 : 0
  name                 = module.context.id
  path                 = var.path
  force_destroy        = var.force_destroy
  tags                 = module.context.tags
  permissions_boundary = var.permissions_boundary
}

# Generate API credentials
resource "aws_iam_access_key" "default" {
  count = module.context.enabled && local.create_iam_access_key ? 1 : 0
  user  = local.username
}

# policies -- inline and otherwise
locals {
  inline_policies_map = merge(
    var.inline_policies_map,
    { for i in var.inline_policies : md5(i) => i }
  )
  policy_arns_map = merge(
    var.policy_arns_map,
    { for i in var.policy_arns : i => i }
  )
}

resource "aws_iam_user_policy" "inline_policies" {
  #bridgecrew:skip=BC_AWS_IAM_16:Skipping `Ensure IAM policies are attached only to groups or roles` check because this module intentionally attaches IAM policy directly to a user.
  for_each = module.context.enabled ? local.inline_policies_map : {}
  lifecycle {
    create_before_destroy = true
  }
  name_prefix = module.context.id
  user        = local.username
  policy      = each.value
}

resource "aws_iam_user_policy_attachment" "policies" {
  #bridgecrew:skip=BC_AWS_IAM_16:Skipping `Ensure IAM policies are attached only to groups or roles` check because this module intentionally attaches IAM policy directly to a user.
  for_each = module.context.enabled ? local.policy_arns_map : {}
  lifecycle {
    create_before_destroy = true
  }
  user       = local.username
  policy_arn = each.value
}

module "store_write" {
  count   = local.ssm_enabled ? 1 : 0
  source  = "cloudposse/ssm-parameter-store/aws"
  version = "0.10.0"
  context = module.context.legacy

  ignore_value_changes = var.ssm_ignore_value_changes
  parameter_write = concat([
    {
      name        = local.key_id_ssm_path
      value       = aws_iam_access_key.default[0].id
      type        = "SecureString"
      overwrite   = true
      description = "The AWS_ACCESS_KEY_ID for the ${local.username} user."
    },
    {
      name        = local.secret_ssm_path
      value       = aws_iam_access_key.default[0].secret
      type        = "SecureString"
      overwrite   = true
      description = "The AWS_SECRET_ACCESS_KEY for the ${local.username} user."
    }], var.ssm_ses_smtp_password_enabled ? [
    {
      name        = local.smtp_password_ssm_path
      value       = aws_iam_access_key.default[0].ses_smtp_password_v4
      type        = "SecureString"
      overwrite   = true
      description = "The AWS_SECRET_ACCESS_KEY converted into an SES SMTP password for the ${local.username} user."
    }] : []
  )
  additional_tag_map = {}
}


#locals {
#  encrypted_credentials               = <<EOF
#AWS_ACCESS_KEY_ID=${try(join("", local.access_key.*.id), "")}
#AWS_SECRET_ACCESS_KEY=${try(join("", local.access_key.*.secret), "")}
#EOF
#  pgp_key_is_keybase                  = length(regexall("keybase:", var.pgp_key)) > 0 ? true : false
#  keybase_credentials_pgp_message     = local.pgp_key_is_keybase ? templatefile("${path.module}/templates/keybase_credentials_pgp_message.txt", { encrypted_credentials = local.encrypted_credentials }) : ""
#  keybase_credentials_decrypt_command = local.pgp_key_is_keybase ? templatefile("${path.module}/templates/keybase_credentials_decrypt_command.sh", { encrypted_credentials = local.encrypted_credentials }) : ""
#}
