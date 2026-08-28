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

## 4. Approval gate
Repo → Settings → Environments → create `production` → Required reviewers = you.
This is the pre-deployment gate that the deploy workflow waits on.

## 5. Terraform state for CI
Local state lives on the laptop; CI applies need remote state. Pick one:
- **S3 backend** (quick): create a versioned bucket + dynamodb lock table, add
  `backend "s3" {}` to `terraform/main.tf`
- **HCP Terraform** (better demo story — one platform end to end): create a project +
  workspace, `cloud {}` block in main.tf, `TF_API_TOKEN` secret

## Demo flow
1. Branch, edit the webapp (e.g. index.html line in the playbook), open PR → `validate` runs
2. Merge → `build` runs → show the action log (logging story), then HCP Packer UI: new version, labels, lineage (registry GUI story)
3. Assign the version to `production` channel (one click)
4. Run `deploy` → approvals gate → instance running the new image
5. Optional: flip Trivy `--exit-code` to `1` in webapp.pkr.hcl, PR with a vulnerable package → build fails red in Actions (security gating story)
