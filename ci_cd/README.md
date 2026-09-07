<!-- Working as a team in repositories and code buckets -->

# Monthly validation

This repository has a GitHub Actions workflow at `.github/workflows/monthly-project-validation.yml`.

It runs on the first day of each month and can also be started manually from the GitHub Actions tab. The workflow checks:

- YAML syntax across repository `.yaml` and `.yml` files.
- CloudFormation template validity with `cfn-lint`.
- Terraform formatting and validation for `ECS_Fargate_CWMetrics`.
- Terraform CLI freshness against HashiCorp's latest stable release index.
- Public access to the published S3 CloudFormation template URL.
- Shell script syntax with `bash -n`.

The scan intentionally skips files that are stored with a YAML extension but are not real YAML manifests, and the incomplete nested-stack parent at `ECS/Websocket Fargate eCS/parent.yml` because it references a `vpc.yml` file that is not present in the repository.

The validator continues running after a check fails so the workflow logs show all issues found in the same scan. At the end, any recorded error makes the GitHub Actions run fail and triggers failure notifications.

Run the same checks locally:

```bash
./ci_cd/validate-projects.sh
```

If you only want the offline checks, skip the public S3 template download:

```bash
SKIP_PUBLIC_TEMPLATE_CHECK=1 ./ci_cd/validate-projects.sh
```

The workflow installs the latest stable Terraform release and confirms the installed version matches HashiCorp's Terraform release index before validating the Terraform project. If a runner is not using the latest stable version, the workflow records `Terraform is out of date`, continues scanning, and fails at the end so GitHub can notify you.

# Step 1. Ensure the local repository is up-to-date
git pull origin main

# Step 2. Create a new branch for your changes
git checkout -b feature/my-change

# Step 3. Make your changes to the code or documentation
git add -A
git commit -m "Describe change"

# Step 4. Push your changes to the remote repository
git push -u origin feature/my-change

# Step 5. Create a Pull Request (PR) when approved
#   Open a PR: feature/my-change -> main
#   Let CI run + review happen
#   Merge via PR (prefer "Squash and merge" or "Rebase and merge")
git checkout main
git pull origin main
git branch -d feature/my-change
#   optional cleanup
git push origin --delete feature/my-change   
