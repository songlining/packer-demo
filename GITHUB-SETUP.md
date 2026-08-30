# GitHub setup — one-time, ~20 minutes

## 1. Repo
```sh
git init && git add -A && git commit -m "packer demo: packer + hcp packer + terraform + gitops"
gh repo create packer-demo --private --source=. --push
```

## 2. HCP service principal → repo secrets
Reuse the same service principal the laptop uses (or make a CI-only one, cleaner story).
- Secrets: `HCP_CLIENT_ID`, `HCP_CLIENT_SECRET`
- Principal needs **Contributor** on the HCP Packer registry project

## 3. AWS OIDC (no static keys — worth saying out loud in the demo)
```sh
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com

# role: packer-demo-github, trust policy below, attach PowerUserAccess (demo) or scope it down
```
Trust policy — replace `<account>` and `<org>/<repo>`:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::<account>:oidc-provider/token.actions.githubusercontent.com"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"},
      "StringLike": {"token.actions.githubusercontent.com:sub": "repo:<org>/<repo>:*"}
    }
  }]
}
```
- Secret: `AWS_ROLE_ARN` = the role ARN

Note: this OIDC role is only used by `build.yml` (Packer needs AWS credentials on
the runner). `deploy.yml` does not use it — its Terraform runs remotely in HCP
Terraform, which authenticates to AWS via its own dynamic-credentials role
(`tfc-packer-demo`, see section 5).

## 4. Approval gate
Done (2026-08-30): `production` environment exists. Add **Required reviewers** in
Repo → Settings → Environments → production (the API-created environment has no
reviewers yet). This is the pre-deployment gate the deploy workflow waits on.

## 5. Terraform state for CI
Done: state and runs live in **HCP Terraform** (org `lab-larry`, workspace
`packer-demo`). `terraform/main.tf` carries the `cloud {}` block; local runs
use your `terraform login` credentials, CI uses the `TFE_TOKEN` secret set in
the `production` GitHub environment (the same token as `~/.terraform.d/credentials.tfrc.json`).
With the cloud block, `terraform apply` executes remotely in HCP Terraform -
GitHub Actions only triggers and reports the run.

## Demo flow
1. Branch, edit the webapp (e.g. index.html line in the playbook), open PR → `validate` runs
2. Merge → `build` runs → show the action log (logging story), then HCP Packer UI: new version, labels, lineage (registry GUI story)
3. Assign the version to `production` channel (one click)
4. Run `deploy` → approvals gate → instance running the new image
5. Optional: flip Trivy `--exit-code` to `1` in webapp.pkr.hcl, PR with a vulnerable package → build fails red in Actions (security gating story)
