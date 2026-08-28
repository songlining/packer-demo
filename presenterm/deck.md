---
---

<!-- jump_to_middle -->
<!-- alignment: center -->
<!-- no_footer -->
<!-- font_size: 2 -->

Golden Images, the GitOps Way

<!-- new_lines: 2 -->
<!-- font_size: 1 -->

Packer + HCP Packer + Terraform — a partner walkthrough

<!-- new_lines: 4 -->

*Larry Song — HashiCorp Solutions Engineering*

<!-- end_slide -->

The product in one slide
========================

<!-- column_layout: [1, 1, 1] -->

<!-- column: 0 -->

**Packer builds**

HCL templates bake machine images for AWS, Azure, GCP, Docker — identical config, every platform.

<!-- column: 1 -->

**HCP Packer governs**

The registry — versions, labels, lineage, channels, revocation. One source of truth for images.

<!-- column: 2 -->

**Terraform deploys**

Infrastructure reads a channel, never an AMI ID. Promote a version and the fleet follows.

<!-- reset_layout -->

<!-- end_slide -->

The world as-is
===============

<!-- list_item_newlines: 2 -->

- Golden images built by hand, on someone's laptop, once
- Tribal knowledge — "ask Dave what's in the 2023 AMI"
- Nobody can say which instance runs which image
- Auditors ask for evidence; screenshots are the evidence

This is the starting line for most AWS customers.

<!-- end_slide -->

The treadmill
=============

<!-- incremental_lists: true -->

- How many golden images does the customer maintain today?
- How often is each one rebaked — and by whom, on what?
- How long from "patch released" to "fleet patched"?
- How many audit findings trace back to stale images?
- What happens to an image the moment a CVE drops?

Multiply their answers. That is the cost of the status quo.

<!-- end_slide -->

<!-- jump_to_middle -->
<!-- alignment: center -->
<!-- font_size: 2 -->

What if image lifecycle was a pipeline — not a project?

<!-- end_slide -->

How it fits together
====================

<!-- column_layout: [1, 3, 1] -->

<!-- column: 1 -->

```
 PR ──► GitHub Actions ──► Packer build
 validate gate            Trivy + Ansible
                               │
                               ▼
                    HCP Packer registry
                    versions · labels · lineage
                               │
        ┌── production channel ┘
        ▼
 Terraform apply ──► EC2, tagged with image + channel
```

<!-- reset_layout -->

Every arrow is code in one Git repo.

<!-- end_slide -->

Positioning — EC2 Image Builder vs Packer + HCP Packer
======================================================

<!-- column_layout: [1, 1] -->

<!-- column: 0 -->

**EC2 Image Builder**

- AWS-only, managed UI pipelines
- Recipe-based, no code review flow
- Distribution inside AWS
- Fine for AWS-only shops

<!-- column: 1 -->

**Packer + HCP Packer**

- One config — AWS, Azure, GCP, Docker
- HCL in Git — PRs, review, audit
- Registry with lineage + revocation
- Channels consumed natively by Terraform

<!-- reset_layout -->

Sell both honestly. Code-first multi-cloud is where we win.

<!-- end_slide -->

The repo is the demo
====================

```bash +exec
[ -f packer/webapp.pkr.hcl ] || cd ..
ls packer/ terraform/ .github/workflows/
echo ---
sed -n '1,20p' packer/webapp.pkr.hcl
```

<!-- speaker_note: Walk the three Packer templates, the Ansible playbook, and the two workflows. Everything the audience will see run lives in this one Git repository. -->

<!-- end_slide -->

Demo — the PR gate
==================

Open a pull request against the repo and GitHub Actions runs
`validate` — Packer validate, Ansible syntax check, Terraform validate.

Nothing merges until the image definition is proven sound.

<!-- list_item_newlines: 2 -->

- `validate.yml` — per-template checks, no cloud credentials needed
- Red check blocks the merge — the gate is the branch policy

<!-- speaker_note: Switch to the browser here. Show the checks tab on a real PR. This is the pre-deployment testing story from the requirements list. -->

<!-- end_slide -->

Demo — merge, and the build runs
================================

```bash +exec
gh run list --workflow=build.yml --limit 5
LAST=$(gh run list -w build.yml -L 1 --json databaseId -q '.[0].databaseId')
gh run view "$LAST" --log | grep -iE "Trivy|PLAY RECAP|Published|Tracking" | tail -4
```

Merge to `main` triggers the build — Trivy scans, Ansible provisions,
Packer publishes the version to HCP Packer. No human touches a console.

<!-- speaker_note: If time allows, dispatch a fresh build live with gh workflow run and watch it stream. The recent green history proves the pipeline is real. -->

<!-- end_slide -->

Demo — HCP Packer registry
==========================

The build pushed a new version to the `webapp-a` bucket. In the portal:

<!-- list_item_newlines: 2 -->

- **Versions** — v1, v2, v3 auto-named; fingerprint per version
- **Labels** — patch-level, owner — machine-readable metadata
- **Lineage** — webapp-a descends from base-os, visible as a tree

<!-- speaker_note: Switch to the HCP portal. Show the bucket, the version list, and the heritage view. This is the governance layer that Image Builder does not have. -->

<!-- end_slide -->

Demo — channels are the pin
===========================

A channel is a named pointer to one version — `dev`, `staging`, `production`.

Assign the new version to `production` in the UI. One click.

<!-- list_item_newlines: 2 -->

- Consumers never reference versions — only channels
- Roll forward is an assignment; roll back is an assignment
- Revocation marks a version bad for compliance trails

<!-- speaker_note: Assign the just-built version to production while the audience watches. Then the next slide deploys from that channel. -->

<!-- end_slide -->

Demo — deploy from the channel
==============================

```bash +exec
# export AWS_PROFILE=personal
[ -f terraform/main.tf ] || cd ..
terraform -chdir=terraform apply -auto-approve
```

Terraform resolves the `production` channel and launches the instance.
No AMI ID appears anywhere in the code.

<!-- speaker_note: Point out the datasource resolving the channel at apply time. The only pin in the whole system is the channel assignment. -->

<!-- end_slide -->

Demo — proof
============

```bash +exec
# export AWS_PROFILE=personal
[ -f terraform/main.tf ] || cd ..
cd terraform
curl -s "http://$(terraform output -raw public_ip)"
aws ec2 describe-tags --filters "Name=resource-id,Values=$(aws ec2 describe-instances --filters Name=tag:Name,Values=golden-image-demo --query 'Reservations[0].Instances[0].InstanceId' --output text)" --query 'Tags[?Key==`image` || Key==`channel`].[Key,Value]' --output table
```

The page comes from the golden image; the tags prove which one.

<!-- end_slide -->

The red build — the gate in action
==================================

Flip one line in the template:

```bash {1}
trivy rootfs --scanners vuln --severity HIGH,CRITICAL --exit-code 0 /
trivy rootfs --scanners vuln --severity HIGH,CRITICAL --exit-code 1 /
```

A HIGH or CRITICAL finding now fails the build — the broken image
never becomes a version, never reaches a channel, never deploys.

Security tools are plugged into the pipeline, not bolted on after.

<!-- speaker_note: Run this live if time allows — add a vulnerable package, PR it, and let the audience watch the build go red. It is the single most persuasive moment in the deck. -->

<!-- end_slide -->

The requirements scoreboard
===========================

<!-- column_layout: [1, 1, 1, 1] -->

<!-- column: 0 -->
**✅ 8 live today**

AWS AMI flow, AL2023, registry, Terraform, as-code, tracking, audit

<!-- column: 1 -->
**🟢 11 native**

GCP, Azure, Docker, RHEL, Windows, API, Ansible, multi-cloud, pre-deploy test, global scale, hooks

<!-- column: 2 -->
**🟡 9 via CI**

GUI, schedules, sec testing, notify, logs, discovery, dashboards, CIS, CVE scans

<!-- column: 3 -->
**🟠 3 partial**

Artifactory, import legacy, package diff

<!-- reset_layout -->

31 requirements from the customer sheet — zero unanswered.

<!-- end_slide -->

Sell it
=======

<!-- list_item_newlines: 2 -->

- **Ask the four questions** — image count, patch cadence, audit findings, drift incidents
- **Anchor on the channel** — "your code never mentions an AMI ID again"
- **Co-sell grows AWS** — every rebuild consumes EC2 and S3 on the customer's account
- **Lead with the red build** — the gate demo closes security-minded buyers

The product answers the spreadsheet. The pipeline answers the audit.

<!-- end_slide -->

Recap — what we proved
======================

<!-- jump_to_middle -->
<!-- alignment: center -->

1. A PR validates the image definition before anything runs
2. A merge builds, scans, and publishes — hands off
3. The registry tracks what exists; the channel decides what ships
4. Terraform deploys whatever the channel pins — and proves it in tags

Honest limits — no native Artifactory connector, no bulk image import,
no package-level diff. A seller who says that first is a trusted one.

<!-- end_slide -->

Cleanup / Reset
===============

Tear down the demo instance so the next run starts clean.

```bash +exec
# export AWS_PROFILE=personal
[ -f terraform/main.tf ] || cd ..
cd terraform && terraform destroy -auto-approve
```

<!-- speaker_note: Run this after the demo. Skip it only if the audience wants to keep the instance for exploration. The registry versions and channels can stay — they are metadata, not cost. -->
