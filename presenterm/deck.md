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

*<Your Name> — HashiCorp Solutions Engineering*

<!-- end_slide -->

Prep — is everything ready?
===========================

```bash +exec
[ -f Makefile ] || cd ..
export AWS_PROFILE="${AWS_PROFILE:-default}"
echo "== env: set HCP_ORG_ID / HCP_PROJECT_ID (your HCP Packer org + project UUIDs)"
[ -n "$HCP_ORG_ID" ] && [ -n "$HCP_PROJECT_ID" ] && echo "HCP org/project set" || echo "HCP_ORG_ID / HCP_PROJECT_ID MISSING"
echo "== AWS session"
aws sts get-caller-identity --query Account --output text
echo "== GitHub CLI"
gh auth status 2>&1 | grep -m1 "Logged in"
echo "== HCP principal"
[ -n "$HCP_CLIENT_ID" ] && echo "HCP_CLIENT_ID set" || echo "HCP creds MISSING"
env | grep -q AWS_SESSION_TOKEN && echo "WARN - stale AWS_* env keys shadow the profile; unset them"
echo "== webapp-a production channel (expect N-1)"
TOKEN=$(curl -s https://auth.idp.hashicorp.com/oauth2/token -H "Content-Type: application/x-www-form-urlencoded" -d "grant_type=client_credentials&client_id=$HCP_CLIENT_ID&client_secret=$HCP_CLIENT_SECRET&audience=https://api.hashicorp.cloud" | python3 -c "import json,sys; print(json.load(sys.stdin).get('access_token',''))")
python3 - "$TOKEN" <<'EOF'
import json, os, sys, urllib.request
H = {"Authorization": "Bearer " + sys.argv[1]}
base = "https://api.cloud.hashicorp.com/packer/2023-01-01/organizations/" + os.environ["HCP_ORG_ID"] + "/projects/" + os.environ["HCP_PROJECT_ID"] + "/buckets/webapp-a"
get = lambda p: json.load(urllib.request.urlopen(urllib.request.Request(base + p, headers=H)))
prod = get("/channels/production")["channel"]["version"]["fingerprint"]
vers = sorted(get("/versions")["versions"], key=lambda v: v["created_at"])
print("production ->", prod[:16], " latest ->", vers[-1]["fingerprint"][:16])
print("OK - production is N-1; the promotion click will move the pin" if prod == vers[-2]["fingerprint"] else "WARN - production is on latest; roll it back one or the promotion is a no-op")
EOF
```

All four checks green — the demo cannot hit a wall mid-flow.

<!-- speaker_note: Run this before every delivery. The AWS check catches an expired SSO token; the channel check catches production sitting on the latest build - which would turn the promotion step into a no-op -->

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

This is the starting line for most customers.

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

<!-- speaker_note: Ask - do not tell. Let the customer answer each question out loud and write the numbers down. Pause after each one. Never say the word treadmill - the audience assembles the metaphor from their own answers. These same numbers resurface on the Sell it slide, so capture them. -->

<!-- end_slide -->

<!-- jump_to_middle -->
<!-- alignment: center -->
<!-- font_size: 2 -->

What if patch day was just a merge?

<!-- end_slide -->

The building blocks
===================

HCP Packer is five nouns. Everything the demos show is built from these.

<!-- column_layout: [1, 1] -->

<!-- column: 0 -->

<!-- list_item_newlines: 2 -->

- **Bucket** — one image family, one owning team (`base-os`, `webapp-a`)
- **Version** — an immutable build of a bucket; fingerprint + labels, never mutated
- **Label** — key/value metadata on a version (`patch-level`, `owner`)
- **Channel** — a named, movable pointer to one version; the only thing that changes (`dev`, `staging`, `production`)
- **Lineage** — every build remembers its parent version — an audit tree, not a guess

<!-- column: 1 -->

```
bucket: webapp-a
┌──────────────────────────────────┐
│ v3   fingerprint · labels newest │
│ v2   ◄── production pins this    │
│ v1   revoked — the kill switch   │
└─────────────────┬────────────────┘
                  ▼
   channel: production → v2
                  ▼
    Terraform reads the channel

lineage: base-os ──► webapp-a
```

<!-- reset_layout -->

<!-- speaker_note: Say the five nouns out loud before the next slide wires them together. Point at v2 and v3 - the demo replays exactly this, a fresh build waiting while production sits one version back, promoted with one click. -->

<!-- end_slide -->

How it fits together
====================

<!-- column_layout: [1, 3, 1] -->

<!-- column: 1 -->

```
  PR ──► GitHub Actions
        validate gate
               │
               │
               ▼
         Packer build
        Trivy + Ansible
               │
               │
               ▼
     HCP Packer registry
   versions · labels · lineage
               │
               │
               ▼
     production channel
               │
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

Where each stage of that pipeline lives:

```
packer/
  base-os.pkr.hcl         AL2023 base image → bucket "base-os"
  webapp.pkr.hcl          app layer; parent = base-os/production
  playbooks/webapp.yml    what goes inside — nginx + index page
.github/workflows/
  validate.yml            the PR gate — packer · ansible · terraform
  build.yml               merge → build → scan → publish → cascade
  deploy.yml              manual dispatch, environment-gated
terraform/
  main.tf                 production channel → EC2 — no AMI IDs
```

That's the entire system. The demos that follow run only these files.

<!-- speaker_note: Point at each stage of the previous diagram and name its file. Two bonus templates exist (from-scratch, docker) but stay off today's path. -->

<!-- end_slide -->

Two images, one lineage
=======================

The demo bakes two images — a foundation and what runs on it.

<!-- list_item_newlines: 2 -->

- **`base-os`** — bare Amazon Linux 2023, owned by the platform team; the value is the metadata chain, not the bytes
- **`webapp-a`** — the app image; its source AMI is whatever `base-os/production` points at, resolved from the registry at build time
- **The link is lineage** — HCP Packer records `webapp-a` as a child of that exact base version, visible as a tree

Rebake the base, republish its channel, and the child rebuilds on top —
foundation and apps move together, with the ancestry to prove it.

<!-- end_slide -->

Demo — the PR gate
==================

A pull request against the repo triggers `validate` — Packer validate,
Ansible syntax check, Terraform validate. Ctrl+e opens the PR live:

```bash +exec
[ -f packer/webapp.pkr.hcl ] || cd ..
git checkout -b demo/update-index 2>/dev/null || git checkout demo/update-index
sed -i '' "s|<h1>.*</h1>|<h1>webapp-a from a golden image ($(date +%H:%M))</h1>|" packer/playbooks/webapp.yml
git commit -am "demo: update index page"
git push -u origin demo/update-index
gh pr create --fill 2>/dev/null || echo "PR already open: $(gh pr list --head demo/update-index --state open --json url -q '.[0].url')"
```

Nothing merges until the image definition is proven sound.

<!-- list_item_newlines: 2 -->

- `validate.yml` — per-template checks, no cloud credentials needed
- Red check blocks the merge — the gate is the branch policy

<!-- speaker_note: Ctrl+e creates the PR - or updates it if it already exists, reruns push a fresh timestamp commit to the same PR. Then switch to the browser and show the checks tab. The PR must touch packer/ or terraform/ or validate.yml will not run. This is the pre-deployment testing story from the requirements list. -->

<!-- end_slide -->

Demo — merge, and the build runs
================================

The merge is a git operation; the build is a consequence. Ctrl+e merges,
then the Actions tab shows the run queuing:

```bash +exec
gh pr merge demo/update-index --squash --delete-branch
sleep 8
gh run list --workflow=build.yml --limit 3
```

Trivy scans, Ansible provisions, Packer publishes — hands off. The log
below is the pipeline's previous run, the same four stages this run will
repeat:

```bash +exec
LAST=$(gh run list -w build.yml --status success -L 1 --json databaseId -q '.[0].databaseId')
echo "----- output of gh run view ----"
gh run view "$LAST" --log | grep -iE "Trivy|PLAY RECAP|Published|Tracking" | tail -4
```

Change `base-os` instead? The workflow re-pins the base channel and
dispatches the webapp build — downstream images rebuild themselves.

<!-- speaker_note: The live build takes about six minutes - it finishes while you walk the portal slides, and the version it publishes lands in HCP Packer unassigned. The greped log is the previous run of the identical pipeline. Switch to the browser if you want the Actions tab visual while the run queues. -->

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

The build just landed as a version, but nothing points at it — and `production`
is deliberately pinned one build behind. Assign the fresh version to
`production` in the UI. That click is the whole promotion.

<!-- list_item_newlines: 2 -->

- Consumers never reference versions — only channels
- Roll forward is an assignment; roll back is an assignment
- Revocation marks a version bad for compliance trails

<!-- speaker_note: Assign the just-built version to production while the audience watches. Then the next slide shows what deploys it - not a laptop, the deploy workflow in CI. -->

<!-- end_slide -->

Demo — deploy from the channel
==============================

No laptop apply — the deployment runs where every other stage runs:
in the pipeline.

```yaml
# .github/workflows/deploy.yml — the whole deployment
on: workflow_dispatch               # a human pulls the trigger
jobs:
  apply:
    runs-on: ubuntu-latest
    environment: production         # the approval gate
    env:
      TFE_TOKEN: ${{ secrets.TFE_TOKEN }}   # the only credential
    steps:
      - run: terraform apply        # executes remotely in HCP Terraform
```

The channel decides; HCP Terraform executes. The run resolves `production`
at apply time, authenticates to AWS via dynamic credentials (OIDC role
scoped to this workspace's runs) — no AMI IDs and no static keys anywhere.

<!-- speaker_note: If the audience wants to see it live, gh workflow run deploy.yml triggers the run and the production environment approval appears in the Actions tab - about two minutes end to end. Terraform is one consumer of the channel - any API-capable tool can resolve it the same way. Left as a talk-through so demo time goes to the registry story instead of a progress bar. -->

<!-- end_slide -->

Demo — proof
============

```bash +exec
export AWS_PROFILE=personal
IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=golden-image-demo" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
curl -s "http://$IP"; echo
aws ec2 describe-tags --filters "Name=resource-id,Values=$(aws ec2 describe-instances --filters Name=tag:Name,Values=golden-image-demo Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].InstanceId' --output text)" --query 'Tags[?Key==`image` || Key==`channel`].[Key,Value]' --output table
```

The page comes from the golden image; the tags prove which one.

<!-- speaker_note: This instance was deployed by the pipeline on an earlier round - the curl shows the baked page and the tags prove which image and channel. Today's promotion deploys the same way after the talk. -->

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
**✅ 8 available**

AWS AMI flow, AL2023, Terraform integration, Ansible, as-code, build orchestration, pre-deploy testing, version tracking

<!-- column: 1 -->
**🟢 12 native**

GCP, Azure, Docker, RHEL, Windows, repository mgmt, API-first, multi-cloud, notifications, global scale, audit, hooks

<!-- column: 2 -->
**🟡 7 via CI**

GUI, schedules, security testing, logging, dashboards, CIS benchmark, CVE scans

<!-- column: 3 -->
**🟠 4 partial**

Artifactory, import legacy, package diff, org-wide discovery

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
export AWS_PROFILE=personal
[ -f terraform/main.tf ] || cd ..
terraform -chdir=terraform destroy -auto-approve   # whatever TFC tracks
IDS=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=golden-image-demo" "Name=instance-state-name,Values=pending,running,stopped" --query 'Reservations[].Instances[].InstanceId' --output text)
[ -n "$IDS" ] && aws ec2 terminate-instances --instance-ids $IDS --query 'TerminatingInstances[].InstanceId' --output text || echo "no untracked instances"
```

<!-- speaker_note: Run this after the demo. The destroy covers everything HCP Terraform tracks; the tag sweep catches instances from rounds that predate the TFC backend. Skip only if the audience wants to keep the instance for exploration. The registry versions and channels can stay - they are metadata, not cost. -->

<!-- end_slide -->

Reset for another round
=======================

```bash +exec
[ -f Makefile ] || cd ..
git restore packer/webapp.pkr.hcl 2>/dev/null || true
git status --short
echo "== roll production back to N-1 so the promotion story replays"
TOKEN=$(curl -s https://auth.idp.hashicorp.com/oauth2/token -H "Content-Type: application/x-www-form-urlencoded" -d "grant_type=client_credentials&client_id=$HCP_CLIENT_ID&client_secret=$HCP_CLIENT_SECRET&audience=https://api.hashicorp.cloud" | python3 -c "import json,sys; print(json.load(sys.stdin).get('access_token',''))")
python3 - "$TOKEN" <<'EOF'
import json, os, sys, urllib.request
H = {"Authorization": "Bearer " + sys.argv[1], "Content-Type": "application/json"}
base = "https://api.cloud.hashicorp.com/packer/2023-01-01/organizations/" + os.environ["HCP_ORG_ID"] + "/projects/" + os.environ["HCP_PROJECT_ID"] + "/buckets/webapp-a"
vers = sorted(json.load(urllib.request.urlopen(urllib.request.Request(base + "/versions", headers=H)))["versions"], key=lambda v: v["created_at"])
body = json.dumps({"version_fingerprint": vers[-2]["fingerprint"], "update_mask": "versionFingerprint"}).encode()
urllib.request.urlopen(urllib.request.Request(base + "/channels/production", body, H, method="PATCH"))
print("production ->", vers[-2]["fingerprint"][:16], "(N-1); latest", vers[-1]["fingerprint"][:16], "left unassigned")
EOF
echo "relaunch the deck with: make deck"
```

One round leaves no residue — the instance is destroyed, the repo is untouched,
and production sits one build behind the latest again. The promotion click and
the apply both replay on the next run.

<!-- speaker_note: If the red-build flip was performed live, git restore reverts it. Rolling production back to N-1 is what makes the demo repeatable - the registry keeps every version, history is an asset, not residue. -->
