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

Prep — is everything ready?
===========================

```bash +exec
# export AWS_PROFILE=personal
[ -f Makefile ] || cd ..
echo "== AWS session"
aws --profile personal sts get-caller-identity --query Account --output text
echo "== GitHub CLI"
gh auth status 2>&1 | grep -m1 "Logged in"
echo "== HCP principal"
[ -n "$HCP_CLIENT_ID" ] && echo "HCP_CLIENT_ID set" || echo "HCP creds MISSING"
env | grep -q AWS_SESSION_TOKEN && echo "WARN - stale AWS_* env keys shadow the profile; unset them"
echo "== webapp-a production channel"
TOKEN=$(curl -s https://auth.idp.hashicorp.com/oauth2/token -H "Content-Type: application/x-www-form-urlencoded" -d "grant_type=client_credentials&client_id=$HCP_CLIENT_ID&client_secret=$HCP_CLIENT_SECRET&audience=https://api.hashicorp.cloud" | python3 -c "import json,sys; print(json.load(sys.stdin).get('access_token',''))")
curl -s -H "Authorization: Bearer $TOKEN" "https://api.cloud.hashicorp.com/packer/2023-01-01/organizations/53068552-945f-4bf9-bf0a-71a457d452a3/projects/afe3e74a-ee44-4897-a674-c80beb132505/buckets/webapp-a/channels/production" | python3 -c "import json,sys; c=json.load(sys.stdin).get('channel',{}); print('production ->', (c.get('version') or {}).get('fingerprint','NOT ASSIGNED'))"
```

All four checks green — the demo cannot hit a wall mid-flow.

<!-- speaker_note: Run this before every delivery. The AWS check catches an expired SSO token, the channel check catches a missing version assignment - the two failures that stall this demo -->

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
<!-- list_item_newlines: 2 -->

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

What if patch day was just a merge?

<!-- end_slide -->

How it fits together
====================

<!-- column_layout: [1, 3, 1] -->

<!-- column: 1 -->

```
  PR ──► GitHub Actions
        validate gate
               │
               ▼
         Packer build
        Trivy + Ansible
               │
               ▼
     HCP Packer registry
   versions · labels · lineage
               │
               ▼
     production channel
               │
               ▼
   Terraform apply ──► EC2
 tagged: image + channel
```

<!-- reset_layout -->

<!-- alignment: center -->

Every arrow is code in one Git repo.

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

Change `base-os` instead? The workflow re-pins the base channel and
dispatches the webapp build — downstream images rebuild themselves.

<!-- speaker_note: If time allows, dispatch a fresh build live with gh workflow run and watch it stream. The recent green history proves the pipeline is real. A base-os rebuild with a new patch level cascades automatically into a webapp rebuild - that is the lineage propagation story. -->

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
<!-- list_item_newlines: 2 -->

1. A PR validates the image definition before anything runs
2. A merge builds, scans, and publishes — hands off
3. The registry tracks what exists; the channel decides what ships
4. Terraform deploys whatever the channel pins — and proves it in tags

Honest limits — no native Artifactory connector, no bulk image import,
no package-level diff. A seller who says that first is a trusted one.

<!-- end_slide -->

Cleanup
=======

Tear down the demo instance so the next run starts clean.

```bash +exec
# export AWS_PROFILE=personal
[ -f terraform/main.tf ] || cd ..
cd terraform && terraform destroy -auto-approve
```

<!-- speaker_note: Run this after the demo. Skip it only if the audience wants to keep the instance for exploration. The registry versions and channels can stay - they are metadata, not cost. -->

<!-- end_slide -->

Reset for another round
=======================

```bash +exec
# export AWS_PROFILE=personal
[ -f Makefile ] || cd ..
git restore packer/webapp.pkr.hcl 2>/dev/null || true
git status --short
echo "repo clean — relaunch the deck with: make deck"
echo "channel is still pinned; slide 'deploy from the channel' applies again"
```

One round leaves no residue — the instance is gone, the repo is untouched,
and the channel still points at the latest version. Re-running the demo
is `terraform apply` on slide thirteen.

<!-- speaker_note: If the red-build flip was performed live, git restore reverts it. The registry keeps every version - history is an asset, not residue. -->
