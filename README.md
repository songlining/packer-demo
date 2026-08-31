# packer-demo

End-to-end golden-image pipeline, running on **both** AWS CodeBuild/CodePipeline and
GitHub Actions in parallel: a GitHub PR kicks off **both** validators; a merge fires
**both** builders, which build AMIs with **Packer**, register them in **HCP Packer**, and
**Terraform** (via a **CodePipeline** approval gate) deploys instances pinned to a channel —
no AMI IDs in code, no static cloud keys anywhere. Source stays in GitHub; the CodeBuild
projects pull from the same repo through a CodeConnections GitHub App.

```mermaid
flowchart TD
    PR[Pull Request] --> |checks green · then merge| validate[CodeBuild validate\npacker · ansible · terraform]
    validate --> build

    subgraph runner["CodeBuild managed runner"]
        build[Packer build]
        ansible[Ansible — nginx + app config]
        trivy[Trivy scan — CVE gate]
        build --> |invokes| ansible
        ansible --> |SSH → applies config| ec2_build[EC2 build instance\ntemporary]
        ansible --> trivy
    end

    trivy --> |pass| snapshot[snapshot → AMI]
    trivy --> |fail: CVE found| blocked([build blocked\nnever registered])
    snapshot --> hcp[HCP Packer Registry\nversion + labels]
    hcp --> |human promotes to production channel| hcp
    hcp --> |Terraform reads production channel| deploy[CodePipeline — Approve stage → terraform apply]
    deploy --> ec2[EC2 instance running]
```

## What's in here

```
packer/
  base-os.pkr.hcl      # Amazon Linux 2023 base image -> HCP bucket "base-os" (labels: patch-level)
  webapp.pkr.hcl       # nginx app layer, parent = base-os via `production` channel -> bucket "webapp-a"
  from-scratch.pkr.hcl # Alpine 3.22 AMI built from a blank disk (amazon-ebssurrogate), no base AMI
  docker.pkr.hcl       # same webapp as a container image
  playbooks/webapp.yml # Ansible: install nginx + deploy index page
  plugins.pkr.hcl      # single source of plugin requirements
terraform/
  main.tf              # resolves the `production` channel -> launches EC2
buildspec/
  validate.yml         # PR gate: packer validate (per file), ansible syntax, terraform validate
  build.yml            # on merge to main: Packer build, publish to HCP Packer, pin + cascade
  deploy.yml           # pipeline Deploy stage: triggers the remote apply in HCP Terraform
ci/                    # CodeBuild/CodePipeline CI stack: GitHub connection, projects + webhooks, pipeline, roles
ci/README.md           # one-time setup + running both pipelines in parallel
.github/workflows/     # GitHub Actions pipelines — same flow, alternative runner
```

## Demo flow (the short version)

1. Branch, edit `packer/playbooks/webapp.yml` (e.g. the index page), open a PR → `validate` goes green
2. Merge → `build` runs → new version appears in HCP Packer with labels and lineage back to `base-os`
3. Assign the version to the `production` channel (HCP Packer UI, one click)
4. Approve the pipeline's **Approve** stage → instance running the new image
5. Bonus: set Trivy `--exit-code` to `1`, PR a vulnerable package → build goes red, image never reaches the channel

## Auth model

- **CodeBuild → AWS**: the build job's IAM role (`packer-demo-codebuild-build`) is
  attached to the project directly — the runner lives inside AWS, so the OIDC
  exchange GitHub Actions needed is gone. EC2 (demo scope), read on one Secrets
  Manager secret (`packer-demo/ci`), and `codebuild:StartBuild` on itself for the
  base-os → webapp cascade.
- **CI → HCP Packer**: service principal (`HCP_CLIENT_ID` / `HCP_CLIENT_SECRET`,
  keys of secret `packer-demo/ci`).
  Packer publishes versions automatically via the `hcp_packer_registry` blocks; Terraform reads
  channels with the same principal. HCP's token endpoint is `auth.idp.hashicorp.com/oauth2/token`.
- **CI → HCP Terraform**: state and runs live in workspace `lab-larry/packer-demo`. The
  deploy job authenticates with the `TFE_TOKEN` key of secret `packer-demo/ci` and `terraform apply`
  executes as a remote TFC run — it never touches state locally. The TFC run authenticates to
  AWS with dynamic credentials (OIDC role `tfc-packer-demo`, trust scoped to the workspace's
  run phases) — no static keys anywhere. Terraform is one consumer of HCP Packer metadata;
  the same channel works from any API-capable tool.
- The CI stack itself (projects, webhooks, pipeline, roles) is Terraform in `ci/`,
  applied once — setup in `ci/README.md`.

## Why the state lives in HCP Terraform

- **CI applies need shared state.** The deploy runner is ephemeral — without remote state,
  every run would see "no resources" and create a duplicate instance, and a later
  `terraform destroy` would never know it existed.
- **One truth.** Laptop and CI share one workspace, so the next run — whoever triggers it —
  sees the same reality.
- **Locking.** Concurrent deploys queue in TFC instead of racing on a local state file.
- **Run history is the audit.** Every plan/apply records who triggered it, the diff, and the
  outcome.
- **Drift fails loudly.** Delete an AMI a channel still points at, and the next plan errors
  instead of silently drifting.

Division of labour: **HCP Packer remembers what images exist; HCP Terraform remembers what
you deployed; AWS remembers what's running.**

### Image lifecycle across the registry boundary

Registry events drive proportionate AWS actions via HCP Packer webhooks — never less, never
more:

- **Version revoked** → webhook marks the AMI *deprecated* in AWS (EC2 deprecation API).
  Running instances are unaffected, new launches wind down, and the action is reversible
  ("restore" in the registry un-deprecates). Revocation is a safe panic button, so it must
  not destroy anything.
- **Version deleted** → webhook deregisters the AMI and deletes the EBS snapshots. Permanent,
  by design — it fires only on the explicit delete event.

Without the webhook handler, registry actions are paper-only: revocation stops new
deployments, but the AMI and snapshots remain in AWS until removed manually
(`aws ec2 deregister-image --delete-snapshots`). A reference handler (API Gateway + Lambda,
from HashiCorp's Field CTO org) lives at https://github.com/danbarr/hcp-packer-webhook-aws.

## Presenting the deck

`presenterm/deck.md` is the slide deck (install: `brew install presenterm`).

```sh
make deck         # present; Ctrl+e executes the live demo blocks
make deck-notes   # terminal 1 — same, but publishes speaker notes
make notes        # terminal 2 — shows only the speaker notes, follows slide changes
```

The live blocks assume you run from a shell with `gh` authenticated and
`AWS_PROFILE=personal` logged in (only the proof and cleanup slides touch AWS).

## Local runs

```sh
cd packer && packer init . && packer validate webapp.pkr.hcl   # per-file; dir mode conflicts on purpose
packer build base-os.pkr.hcl   # first run only (~4 min), then assign to `production` channel
packer build webapp.pkr.hcl    # ~6 min
cd ../terraform && terraform apply
```

AWS profile must point at the same account CI builds into, or the channel will
reference AMIs that don't exist locally.

## Cleanup

`terraform destroy` — everything else is registry metadata and EBS snapshots.
