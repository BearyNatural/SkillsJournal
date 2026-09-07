#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
PUBLIC_TEMPLATE_URL="https://cf-templates-h4othlrjdfdl-us-east-1.s3.us-east-1.amazonaws.com/S3_CFD_CFN.yaml"
PUBLIC_TEMPLATE_COPY="/tmp/S3_CFD_CFN.yaml"
CFN_TEMPLATE_LIST="$(mktemp)"
TERRAFORM_RELEASE_JSON="$(mktemp)"
TERRAFORM_RELEASE_INDEX_URL="https://releases.hashicorp.com/terraform/index.json"

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
  record_failure "Missing tool" "python3 is not installed or not on PATH."
else
  python3 --version
fi

if ! command -v cfn-lint >/dev/null 2>&1; then
  record_failure "Missing tool" "cfn-lint is not installed or not on PATH."
else
  cfn-lint --version
fi

if ! command -v terraform >/dev/null 2>&1; then
  record_failure "Missing tool" "terraform is not installed or not on PATH."
else
  terraform version
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

echo "== Published S3 template check =="
if [[ "${SKIP_PUBLIC_TEMPLATE_CHECK:-}" == "1" ]]; then
  echo "Skipping public S3 template check because SKIP_PUBLIC_TEMPLATE_CHECK=1."
elif ! command -v cfn-lint >/dev/null 2>&1; then
  record_failure "Published S3 template check skipped" "Could not lint the published template because cfn-lint is unavailable."
elif ! curl --retry 3 --retry-delay 5 -fsSL "$PUBLIC_TEMPLATE_URL" -o "$PUBLIC_TEMPLATE_COPY"; then
  record_failure "Published S3 template download failed" "Could not download ${PUBLIC_TEMPLATE_URL}."
elif ! cfn-lint --non-zero-exit-code error --regions us-east-1 -t "$PUBLIC_TEMPLATE_COPY"; then
  record_failure "Published S3 template lint failed" "The published S3 CloudFormation template contains errors."
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
