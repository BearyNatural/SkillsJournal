#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
PUBLIC_TEMPLATE_URL="https://cf-templates-h4othlrjdfdl-us-east-1.s3.us-east-1.amazonaws.com/S3_CFD_CFN.yaml"
PUBLIC_TEMPLATE_COPY="/tmp/S3_CFD_CFN.yaml"
CFN_TEMPLATE_LIST="$(mktemp)"

cd "$ROOT_DIR"
trap 'rm -f "$CFN_TEMPLATE_LIST"' EXIT

echo "== Tool versions =="
python3 --version
cfn-lint --version

echo "== YAML syntax =="
python3 - "$CFN_TEMPLATE_LIST" <<'PY'
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

mapfile -t CFN_TEMPLATES < "$CFN_TEMPLATE_LIST"

echo "== CloudFormation lint =="
if ((${#CFN_TEMPLATES[@]} == 0)); then
  echo "No CloudFormation templates found."
else
  printf 'Found CloudFormation templates:\n'
  printf ' - %s\n' "${CFN_TEMPLATES[@]}"
  cfn-lint --non-zero-exit-code error --regions us-east-1 ap-southeast-2 -t "${CFN_TEMPLATES[@]}"
fi

echo "== Published S3 template check =="
if [[ "${SKIP_PUBLIC_TEMPLATE_CHECK:-}" == "1" ]]; then
  echo "Skipping public S3 template check because SKIP_PUBLIC_TEMPLATE_CHECK=1."
else
  curl --retry 3 --retry-delay 5 -fsSL "$PUBLIC_TEMPLATE_URL" -o "$PUBLIC_TEMPLATE_COPY"
  cfn-lint --non-zero-exit-code error --regions us-east-1 -t "$PUBLIC_TEMPLATE_COPY"
fi

echo "== Shell syntax =="
shell_errors=0
while IFS= read -r -d '' script; do
  echo "Checking ${script#./}"
  if ! bash -n "$script"; then
    shell_errors=1
  fi
done < <(find . -type f \( -name "*.sh" -o -name "*.bash" \) -not -path "./.git/*" -print0)

if ((shell_errors)); then
  echo "One or more shell scripts failed syntax validation."
  exit 1
fi

echo "All monthly project validation checks passed."
