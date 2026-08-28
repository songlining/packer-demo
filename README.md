# packer-demo

End-to-end golden-image pipeline: a GitHub PR builds AMIs with **Packer**, registers
them in **HCP Packer**, and **Terraform** deploys instances pinned to a channel —
no AMI IDs in code, no static cloud keys anywhere.

```
PR ──► validate.yml (packer/ansible/terraform checks)
 │
 merge ──► build.yml ──► Packer build (Trivy scan + Ansible inside)
 │                            │
 │                            ▼
 │                       HCP Packer registry (version + labels + lineage)
 │                            │  assign version to `production` channel
 ▼                            ▼
deploy.yml ──► Terraform reads channel ──► EC2 instance tagged with image + channel
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
.github/workflows/
  validate.yml         # PR gate: packer validate (per file), ansible syntax, terraform validate
  build.yml            # on merge to main: OIDC -> AWS, Packer build, publish to HCP Packer
  deploy.yml           # manual dispatch, gated by the `production` GitHub environment
GITHUB-SETUP.md        # one-time setup: repo, secrets, AWS OIDC role, environments, state backend
```

## Demo flow (the short version)

1. Branch, edit `packer/playbooks/webapp.yml` (e.g. the index page), open a PR → `validate` goes green
2. Merge → `build` runs → new version appears in HCP Packer with labels and lineage back to `base-os`
3. Assign the version to the `production` channel (HCP Packer UI, one click)
4. Run `deploy` → approve the `production` environment → instance runs the new image
5. Bonus: set Trivy `--exit-code` to `1`, PR a vulnerable package → build goes red, image never reaches the channel

## Auth model

- **GitHub → AWS**: OIDC. The workflow requests a JWT from `token.actions.githubusercontent.com`,
  exchanges it at STS for temporary credentials for role `packer-demo-github`. Trust policy is
  scoped to this repo (`repo:*/packer-demo@<repo-id>:ref:refs/heads/main`) — note GitHub's newer
  `sub` claim format includes actor and repo IDs.
- **CI → HCP Packer**: service principal (`HCP_CLIENT_ID` / `HCP_CLIENT_SECRET` repo secrets).
  Packer publishes versions automatically via the `hcp_packer_registry` blocks; Terraform reads
  channels with the same principal. HCP's token endpoint is `auth.idp.hashicorp.com/oauth2/token`.

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
