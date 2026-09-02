# CI stack setup — one-time, ~15 minutes

CodeBuild + CodePipeline replace GitHub Actions. Source stays in GitHub — the
projects pull from your repo (pass `-var github_repo=<owner>/<name>` when applying)
via a CodeConnections GitHub App,
`buildspec/*.yml` are the pipelines and live in the repo like `.github/workflows/` did.

Also set `HCP_ORG_ID` / `HCP_PROJECT_ID` env vars on the `packer-demo-build` project
after creating it — `buildspec/build.yml` has placeholders.

## 1. One Secrets Manager secret (all three CI credentials, JSON)

```sh
aws secretsmanager create-secret --region <region> --name packer-demo/ci \
  --secret-string '{
    "HCP_CLIENT_ID":     "<same service principal as before>",
    "HCP_CLIENT_SECRET": "<...>",
    "TFE_TOKEN":         "<~/.terraform.d/credentials.tfrc.json value>"
  }'
```

Not managed by Terraform on purpose — no static keys in state.

## 2. Apply

```sh
cd ci && terraform init && terraform apply -var github_repo=<owner>/packer-demo
```

State lands in HCP Terraform workspace `<your-hcptf-org>/packer-demo-ci` (separate from
the app workspace `packer-demo` — CI shouldn't re-concile on every deploy run).

## 3. Authorize the GitHub App (one console click)

Output `connection_status` shows `PENDING`. Console → Developer Settings →
Connections → `packer-demo-github` → **Update pending connection** → Install the
AWS Connector for GitHub app → status flips to `AVAILABLE`. Webhooks and the
pipeline start working immediately after; nothing else to redo.

## 4. Behavior notes (vs the old Actions setup)

| Old | New |
|---|---|
| PR → `validate` checks | PR → `packer-demo-validate` build (path-filtered, reports commit status back to the PR) |
| Merge → `build` runs | Push to `main` with `packer/**` → `packer-demo-build` (webhook) |
| `workflow_dispatch` + template choice | `aws codebuild start-build --project-name packer-demo-build --environment-variables-override name=TEMPLATE,value=base-os.pkr.hcl` |
| base-os → webapp cascade | same, via `codebuild:StartBuild` on itself |
| `production` GitHub environment approval | **Approve stage in the pipeline** — every push to `main` parks there; assign the HCP channel, then approve |
| deploy triggered manually | pipeline auto-parks at Approve on push (no path filter in pipeline sources); approving on a no-change push is a no-op apply |

## 5. Running both pipelines in parallel

Both CI systems stay active on the same repo and watch the same events:

- A PR touching `packer/**` or `terraform/**` runs **two** validators (Actions `validate`,
  CodeBuild `packer-demo-validate`) — both report status on the PR.
- A merge to `main` touching `packer/**` fires **two** builds — two AMIs, two HCP Packer
  versions of the same commit. Promote whichever; they're identical.
- Demo tip: to run exactly one pipeline on demand, dispatch it instead of pushing:

```sh
gh workflow run build.yml -f template=webapp.pkr.hcl                    # GitHub Actions
aws codebuild start-build --project-name packer-demo-build \\
  --environment-variables-override name=TEMPLATE,value=webapp.pkr.hcl   # CodeBuild
```

Retire one side when you're done comparing: `gh workflow disable validate build deploy`
for Actions, or `aws codebuild delete-webhook --project-name <name>` per project for CodeBuild.

## 6. Cleanup

```sh
cd ci && terraform destroy
aws secretsmanager delete-secret --region <region> --secret-id packer-demo/ci
```

The artifact bucket has `force_destroy = true`, so destroy just works.
