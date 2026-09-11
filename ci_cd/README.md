<!-- Working as a team in repositories and code buckets -->

# Monthly validation

This repository has a GitHub Actions workflow at `.github/workflows/monthly-project-validation.yml`.

It runs on every push to a repository branch, on the first day of each month, and can also be started manually from the GitHub Actions tab. Auto-fix branches under `automated/monthly-project-autofixes/**` are ignored so the workflow does not trigger itself in a loop.

The workflow checks:

- YAML syntax across repository `.yaml` and `.yml` files.
- CloudFormation template validity with `cfn-lint`.
- CloudFormation security findings with `cfn_nag`.
- Terraform formatting and validation for `ECS_Fargate_CWMetrics`.
- Terraform linting with `TFLint`.
- IaC security/compliance findings with `Checkov`.
- High/critical IaC misconfigurations and secrets with `Trivy`.
- Terraform CLI freshness against HashiCorp's latest stable release index.
- Public access to the published S3 CloudFormation template URL.
- Shell script syntax with `bash -n`.

The scan intentionally skips files that are stored with a YAML extension but are not real YAML manifests, the AWS VPC CNI vendor manifest at `EKS/aws-k8s-cni.yaml`, and the incomplete nested-stack parent at `ECS/Websocket Fargate eCS/parent.yml` because it references a `vpc.yml` file that is not present in the repository.

Before validation, the workflow applies safe automated fixes. Currently this means `terraform fmt -recursive` and Terraform provider lock-file refreshes for `ECS_Fargate_CWMetrics`. If those fixes change files, GitHub Actions opens or updates a pull request named `Apply monthly validation auto-fixes` and notes the changed files in the workflow logs and PR body.

Auto-fix pull request branches include the source branch name, for example `automated/monthly-project-autofixes/feature/my-change`, so scans from different branches do not reuse the same auto-fix branch.

The validator continues running after a check fails so the workflow logs show all issues found in the same scan. At the end, any recorded error makes the GitHub Actions run fail and triggers failure notifications. If auto-fixes resolve every issue, the run succeeds and the auto-fix pull request can be reviewed and merged.

The workflow installs the current scanner versions each run:

- Terraform is installed as `latest`.
- TFLint is installed as `latest`.
- Trivy is installed as `latest`.
- `cfn-lint`, `PyYAML`, and `Checkov` are installed with `pip --upgrade`.
- `cfn-nag` is installed from the latest Ruby gem.

Python is set to the latest available `3.12` patch because Checkov currently supports Python 3.9 through 3.12.
Ruby is set to `3.3` for `cfn-nag` compatibility while still installing the latest `cfn-nag` gem each run.

Pull request creation uses the workflow's `GITHUB_TOKEN`. In GitHub repository settings, Actions must have read/write workflow permissions and permission to create pull requests.

Run the same checks locally:

```bash
./ci_cd/validate-projects.sh
```

Run safe auto-fixes locally:

```bash
./ci_cd/autofix-projects.sh
```

If you only want the offline checks, skip the public S3 template download:

```bash
SKIP_PUBLIC_TEMPLATE_CHECK=1 ./ci_cd/validate-projects.sh
```

If you only want syntax and validity checks, skip the advanced security/compliance scanners:

```bash
SKIP_SECURITY_SCAN=1 ./ci_cd/validate-projects.sh
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
