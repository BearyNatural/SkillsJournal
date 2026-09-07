#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
AUTOFIX_SUMMARY="${AUTOFIX_SUMMARY:-/tmp/monthly-autofix-summary.md}"

terraform_projects=(
  "ECS_Fargate_CWMetrics"
)

if ! cd "$ROOT_DIR"; then
  echo "Could not change directory to ${ROOT_DIR}; skipping auto-fixes."
  exit 0
fi
mkdir -p "$(dirname "$AUTOFIX_SUMMARY")"

{
  echo "# Monthly Project Auto-Fixes"
  echo
  echo "This pull request contains safe automated fixes from the monthly validation workflow."
  echo
  echo "## Fixes Applied"
} >"$AUTOFIX_SUMMARY"

echo "== Auto-fix: Terraform formatting =="
if ! command -v terraform >/dev/null 2>&1; then
  echo "- Terraform formatting was skipped because Terraform was not available." >>"$AUTOFIX_SUMMARY"
  echo "Terraform is not available; skipping Terraform auto-fixes."
  exit 0
fi

for project in "${terraform_projects[@]}"; do
  echo "Formatting Terraform project: $project"
  if terraform -chdir="$project" fmt -recursive; then
    echo "- Ran \`terraform fmt -recursive\` for \`$project\`." >>"$AUTOFIX_SUMMARY"
  else
    echo "- Could not run \`terraform fmt -recursive\` for \`$project\`; validation will report the remaining issue." >>"$AUTOFIX_SUMMARY"
  fi

  echo "Refreshing Terraform dependency lock file: $project"
  if terraform -chdir="$project" init -backend=false -input=false; then
    echo "- Ran \`terraform init -backend=false -input=false\` for \`$project\` to refresh provider lock metadata." >>"$AUTOFIX_SUMMARY"
  else
    echo "- Could not refresh Terraform provider lock metadata for \`$project\`; validation will report the remaining issue." >>"$AUTOFIX_SUMMARY"
  fi
done

changed_files="$(git status --porcelain -- "${terraform_projects[@]}" | sed 's/^...//')"

if [[ -z "$changed_files" ]]; then
  echo "No safe automated fixes were needed."
else
  echo >>"$AUTOFIX_SUMMARY"
  echo "## Files Changed" >>"$AUTOFIX_SUMMARY"
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    echo "- \`$file\`" >>"$AUTOFIX_SUMMARY"
  done <<<"$changed_files"

  echo "Safe automated fixes changed these files:"
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    echo " - $file"
  done <<<"$changed_files"
fi

{
  echo
  echo "## Review Notes"
  echo
  echo "The workflow validates the repository again after applying these fixes. If any checks still fail, the workflow run fails and the logs list the remaining manual fixes."
} >>"$AUTOFIX_SUMMARY"
