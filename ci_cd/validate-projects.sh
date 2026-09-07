#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
PUBLIC_TEMPLATE_URL="https://cf-templates-h4othlrjdfdl-us-east-1.s3.us-east-1.amazonaws.com/S3_CFD_CFN.yaml"
PUBLIC_TEMPLATE_COPY="/tmp/S3_CFD_CFN.yaml"
CFN_TEMPLATE_LIST="$(mktemp)"
TERRAFORM_RELEASE_JSON="$(mktemp)"
TERRAFORM_RELEASE_INDEX_URL="https://releases.hashicorp.com/terraform/index.json"
CHECKOV_SKIP_PATH_ARGS=(
  --skip-path "EKS/aws-node_config.yaml"
  --skip-path "EKS/bootscript.yml"
  --skip-path "ECS/Websocket Fargate eCS/parent.yml"
)
TRIVY_SKIP_ARGS=(
  --skip-dirs ".git"
  --skip-dirs "**/.terraform"
  --skip-files "EKS/aws-node_config.yaml"
  --skip-files "EKS/bootscript.yml"
  --skip-files "ECS/Websocket Fargate eCS/parent.yml"
)

failures=()

record_failure() {
  local title="$1"
  local message="$2"

  failures+=("${title}: ${message}")
  echo "::error title=${title}::${message}"
}

print_failure_summary() {
  if ((${#failures[@]} == 0)); then
    echo "All monthly project validation checks passed."
    return 0
  fi

  echo "== Validation failures =="
  printf ' - %s\n' "${failures[@]}"
  echo "Monthly project validation finished with ${#failures[@]} failure(s)."
  return 1
}

cd "$ROOT_DIR" || {
  record_failure "Repository path error" "Could not change directory to ${ROOT_DIR}."
  print_failure_summary
  exit $?
}

trap 'rm -f "$CFN_TEMPLATE_LIST" "$TERRAFORM_RELEASE_JSON"' EXIT

echo "== Tool versions =="
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3: not installed"
else
  python3 --version
fi

if ! command -v cfn-lint >/dev/null 2>&1; then
  echo "cfn-lint: not installed"
else
  cfn-lint --version
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform: not installed"
else
  terraform version
fi

if ! command -v tflint >/dev/null 2>&1; then
  echo "tflint: not installed"
else
  tflint --version
fi

if [[ "${SKIP_SECURITY_SCAN:-}" == "1" ]]; then
  echo "Advanced security/compliance scanner version checks skipped because SKIP_SECURITY_SCAN=1."
else
  if ! command -v checkov >/dev/null 2>&1; then
    echo "checkov: not installed"
  else
    checkov --version
  fi

  if ! command -v trivy >/dev/null 2>&1; then
    echo "trivy: not installed"
  else
    trivy --version
  fi

  if ! command -v cfn_nag_scan >/dev/null 2>&1; then
    echo "cfn_nag_scan: not installed"
  else
    echo "cfn_nag_scan: $(command -v cfn_nag_scan)"
  fi
fi

echo "== Terraform version policy =="
if command -v terraform >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  installed_terraform_version="$(
    terraform version -json 2>/dev/null \
      | python3 -c 'import json, sys; print(json.load(sys.stdin)["terraform_version"])' 2>/dev/null
  )"

  if [[ -z "$installed_terraform_version" ]]; then
    record_failure "Terraform version check failed" "Could not read the installed Terraform version."
  fi

  if [[ "${SKIP_TERRAFORM_LATEST_CHECK:-}" == "1" ]]; then
    echo "Skipping latest Terraform release check because SKIP_TERRAFORM_LATEST_CHECK=1."
  elif ! curl --retry 3 --retry-delay 5 -fsSL "$TERRAFORM_RELEASE_INDEX_URL" -o "$TERRAFORM_RELEASE_JSON"; then
    record_failure "Terraform latest check failed" "Could not query HashiCorp for the latest stable Terraform release."
  else
    latest_terraform_version="$(
      python3 - "$TERRAFORM_RELEASE_JSON" <<'PY'
import json
import re
import sys

with open(sys.argv[1]) as release_file:
    release_index = json.load(release_file)

stable_versions = []
for version in release_index["versions"]:
    if re.fullmatch(r"\d+\.\d+\.\d+", version):
        stable_versions.append((tuple(int(part) for part in version.split(".")), version))

if not stable_versions:
    raise SystemExit("No stable Terraform releases found.")

print(max(stable_versions)[1])
PY
    )"

    if [[ "$installed_terraform_version" != "$latest_terraform_version" ]]; then
      record_failure "Terraform is out of date" "Installed Terraform ${installed_terraform_version:-unknown} does not match latest stable ${latest_terraform_version}."
    elif ! python3 - "$latest_terraform_version" <<'PY'
import re
import sys

latest = sys.argv[1]


def stable_version_tuple(version):
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", version)
    if not match:
        raise ValueError(f"Unsupported Terraform version format: {version}")
    return tuple(int(part) for part in match.groups())


stable_version_tuple(latest)
PY
    then
      record_failure "Terraform latest check failed" "Latest Terraform version '${latest_terraform_version}' did not match the expected stable version format."
    else
      echo "Terraform ${installed_terraform_version} matches the latest stable release."
    fi
  fi
else
  record_failure "Terraform version policy skipped" "Could not run the Terraform version policy because terraform or python3 is unavailable."
fi

echo "== Terraform validation =="
terraform_projects=(
  "ECS_Fargate_CWMetrics"
)

if command -v terraform >/dev/null 2>&1; then
  for project in "${terraform_projects[@]}"; do
    echo "Checking Terraform project: $project"

    if ! terraform -chdir="$project" fmt -check -recursive; then
      record_failure "Terraform format failed" "${project} is not formatted. Run terraform fmt -recursive in that project."
    fi

    if ! terraform -chdir="$project" init -backend=false -input=false; then
      record_failure "Terraform init failed" "${project} could not initialize."
      continue
    fi

    if ! terraform -chdir="$project" validate; then
      record_failure "Terraform validate failed" "${project} is not valid Terraform."
    fi
  done
else
  record_failure "Terraform validation skipped" "Could not run Terraform validation because terraform is unavailable."
fi

echo "== Terraform lint: TFLint =="
if command -v tflint >/dev/null 2>&1; then
  for project in "${terraform_projects[@]}"; do
    echo "Checking TFLint project: $project"

    if [[ -f "$project/.tflint.hcl" || -f "$project/.tflint.json" ]]; then
      if ! (cd "$project" && tflint --init); then
        record_failure "TFLint init failed" "${project} could not initialize TFLint plugins."
        continue
      fi
    fi

    if ! (cd "$project" && tflint --format compact); then
      record_failure "TFLint failed" "${project} has Terraform lint findings or TFLint could not complete."
    fi
  done
else
  record_failure "TFLint skipped" "Could not run TFLint because it is unavailable."
fi

echo "== YAML syntax =="
if command -v python3 >/dev/null 2>&1; then
  if ! python3 - "$CFN_TEMPLATE_LIST" <<'PY'
from pathlib import Path
import sys

import yaml


class CloudFormationSafeLoader(yaml.SafeLoader):
    pass


def construct_unknown_tag(loader, tag_suffix, node):
    if isinstance(node, yaml.ScalarNode):
        return loader.construct_scalar(node)
    if isinstance(node, yaml.SequenceNode):
        return loader.construct_sequence(node)
    if isinstance(node, yaml.MappingNode):
        return loader.construct_mapping(node)
    return None


CloudFormationSafeLoader.add_multi_constructor("!", construct_unknown_tag)

root = Path.cwd()
output_path = Path(sys.argv[1])
excluded_yaml_paths = {
    Path("EKS/aws-node_config.yaml"),
    Path("EKS/bootscript.yml"),
}
excluded_cloudformation_templates = {
    Path("ECS/Websocket Fargate eCS/parent.yml"),
}
yaml_paths = sorted(
    path
    for path in root.rglob("*")
    if path.is_file()
    and path.suffix in {".yaml", ".yml"}
    and ".git" not in path.parts
    and ".terraform" not in path.parts
    and path.relative_to(root) not in excluded_yaml_paths
)

errors = []
cloudformation_templates = []

for path in yaml_paths:
    relative_path = path.relative_to(root)
    try:
        documents = list(yaml.load_all(path.read_text(), Loader=CloudFormationSafeLoader))
    except yaml.YAMLError as error:
        errors.append(f"{relative_path}: {error}")
        continue

    for document in documents:
        if not isinstance(document, dict):
            continue

        resources = document.get("Resources")
        has_aws_resource = (
            isinstance(resources, dict)
            and any(
                isinstance(resource, dict)
                and str(resource.get("Type", "")).startswith(("AWS::", "Custom::"))
                for resource in resources.values()
            )
        )

        if "AWSTemplateFormatVersion" in document or has_aws_resource:
            if relative_path not in excluded_cloudformation_templates:
                cloudformation_templates.append(str(relative_path))
            else:
                print(
                    f"Skipping incomplete CloudFormation parent template: {relative_path}",
                    file=sys.stderr,
                )
            break

if errors:
    print("YAML syntax errors found:", file=sys.stderr)
    for error in errors:
        print(f" - {error}", file=sys.stderr)
    sys.exit(1)

print(f"Parsed {len(yaml_paths)} YAML files successfully.", file=sys.stderr)
output_path.write_text("\n".join(cloudformation_templates))
PY
  then
    record_failure "YAML syntax failed" "One or more YAML files failed to parse."
  fi
else
  record_failure "YAML syntax skipped" "Could not run YAML syntax validation because python3 is unavailable."
fi

mapfile -t CFN_TEMPLATES < "$CFN_TEMPLATE_LIST"

echo "== CloudFormation lint =="
if ! command -v cfn-lint >/dev/null 2>&1; then
  record_failure "CloudFormation lint skipped" "Could not run cfn-lint because it is unavailable."
elif ((${#CFN_TEMPLATES[@]} == 0)); then
  echo "No CloudFormation templates found."
else
  printf 'Found CloudFormation templates:\n'
  printf ' - %s\n' "${CFN_TEMPLATES[@]}"
  if ! cfn-lint --non-zero-exit-code error --regions us-east-1 ap-southeast-2 -t "${CFN_TEMPLATES[@]}"; then
    record_failure "CloudFormation lint failed" "One or more CloudFormation templates contain errors."
  fi
fi

if [[ "${SKIP_SECURITY_SCAN:-}" == "1" ]]; then
  echo "Skipping IaC security/compliance scans because SKIP_SECURITY_SCAN=1."
else
  echo "== CloudFormation security: cfn_nag =="
  if ! command -v cfn_nag_scan >/dev/null 2>&1; then
    record_failure "cfn_nag skipped" "Could not run cfn_nag because cfn_nag_scan is unavailable."
  elif ((${#CFN_TEMPLATES[@]} == 0)); then
    echo "No CloudFormation templates found for cfn_nag."
  else
    for template in "${CFN_TEMPLATES[@]}"; do
      echo "Checking cfn_nag template: $template"
      if ! cfn_nag_scan --input-path "$template"; then
        record_failure "cfn_nag failed" "${template} has CloudFormation security findings or cfn_nag could not complete."
      fi
    done
  fi

  echo "== IaC security/compliance: Checkov =="
  if ! command -v checkov >/dev/null 2>&1; then
    record_failure "Checkov skipped" "Could not run Checkov because it is unavailable."
  else
    for project in "${terraform_projects[@]}"; do
      echo "Checking Checkov Terraform project: $project"
      if ! checkov --directory "$project" --framework terraform --quiet --compact; then
        record_failure "Checkov Terraform failed" "${project} has Terraform security/compliance findings or Checkov could not complete."
      fi
    done

    if ((${#CFN_TEMPLATES[@]} == 0)); then
      echo "No CloudFormation templates found for Checkov."
    else
      for template in "${CFN_TEMPLATES[@]}"; do
        echo "Checking Checkov CloudFormation template: $template"
        if ! checkov --file "$template" --framework cloudformation --quiet --compact; then
          record_failure "Checkov CloudFormation failed" "${template} has CloudFormation security/compliance findings or Checkov could not complete."
        fi
      done
    fi

    if [[ -d "EKS" ]]; then
      echo "Checking Checkov Kubernetes manifests: EKS"
      if ! checkov --directory "EKS" --framework kubernetes --quiet --compact "${CHECKOV_SKIP_PATH_ARGS[@]}"; then
        record_failure "Checkov Kubernetes failed" "EKS has Kubernetes security/compliance findings or Checkov could not complete."
      fi
    else
      echo "No EKS directory found for Checkov Kubernetes scanning."
    fi
  fi

  echo "== IaC security/compliance: Trivy =="
  if ! command -v trivy >/dev/null 2>&1; then
    record_failure "Trivy skipped" "Could not run Trivy because it is unavailable."
  elif ! trivy fs \
    --scanners misconfig,secret \
    --misconfig-scanners terraform,cloudformation,kubernetes \
    --severity HIGH,CRITICAL \
    --exit-code 1 \
    --no-progress \
    "${TRIVY_SKIP_ARGS[@]}" \
    .; then
    record_failure "Trivy failed" "Trivy found high/critical IaC misconfigurations, secrets, or could not complete."
  fi
fi

echo "== Published S3 template check =="
if [[ "${SKIP_PUBLIC_TEMPLATE_CHECK:-}" == "1" ]]; then
  echo "Skipping public S3 template check because SKIP_PUBLIC_TEMPLATE_CHECK=1."
elif ! curl --retry 3 --retry-delay 5 -fsSL "$PUBLIC_TEMPLATE_URL" -o "$PUBLIC_TEMPLATE_COPY"; then
  record_failure "Published S3 template download failed" "Could not download ${PUBLIC_TEMPLATE_URL}."
else
  if ! command -v cfn-lint >/dev/null 2>&1; then
    record_failure "Published S3 template lint skipped" "Could not lint the published template because cfn-lint is unavailable."
  elif ! cfn-lint --non-zero-exit-code error --regions us-east-1 -t "$PUBLIC_TEMPLATE_COPY"; then
    record_failure "Published S3 template lint failed" "The published S3 CloudFormation template contains errors."
  fi

  if [[ "${SKIP_SECURITY_SCAN:-}" != "1" ]]; then
    if ! command -v cfn_nag_scan >/dev/null 2>&1; then
      record_failure "Published S3 cfn_nag skipped" "Could not run cfn_nag on the published template because cfn_nag_scan is unavailable."
    elif ! cfn_nag_scan --input-path "$PUBLIC_TEMPLATE_COPY"; then
      record_failure "Published S3 cfn_nag failed" "The published S3 CloudFormation template has cfn_nag security findings."
    fi

    if ! command -v checkov >/dev/null 2>&1; then
      record_failure "Published S3 Checkov skipped" "Could not run Checkov on the published template because Checkov is unavailable."
    elif ! checkov --file "$PUBLIC_TEMPLATE_COPY" --framework cloudformation --quiet --compact; then
      record_failure "Published S3 Checkov failed" "The published S3 CloudFormation template has Checkov security/compliance findings."
    fi
  fi
fi

echo "== Shell syntax =="
shell_errors=0
while IFS= read -r -d '' script; do
  echo "Checking ${script#./}"
  if ! bash -n "$script"; then
    shell_errors=1
  fi
done < <(find . -type f \( -name "*.sh" -o -name "*.bash" \) -not -path "./.git/*" -not -path "*/.terraform/*" -print0)

if ((shell_errors)); then
  record_failure "Shell syntax failed" "One or more shell scripts failed syntax validation."
fi

print_failure_summary
exit $?
