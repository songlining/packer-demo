# Ops notes — trial-and-error log (update as you learn)

Hard-won facts from real executions. If something here is wrong, fix it —
these are notes, not law.

## HCP Packer API quirks (2023-01-01)

Org: `<org-id>` · Project: `<project-id>` · Buckets: `webapp-a`, `base-os`

Base URL:
```
https://api.cloud.hashicorp.com/packer/2023-01-01/organizations/{ORG}/projects/{PROJ}/buckets/{BUCKET}
```

1. **Auth: use `hcp auth login` + `hcp auth print-access-token`, not the creds cache.**
   `~/.config/hcp/creds-cache.json` goes stale (we saw a March token in
   September). The SP key stored in Secrets Manager `packer-demo/ci` also
   went **dead** (`access_denied` on the OAuth grant) — don't rely on it.
   ```sh
   hcp auth login          # browser flow
   TOKEN=$(hcp auth print-access-token)
   ```
2. **Endpoint is `/versions`, NOT `/iterations`.** `/iterations` 404s. The
   channel payload field is `version`, not `iteration`.
3. **Version delete key = `fingerprint`, not `id` (ULID) and not `name` (`v1`).**
   DELETE `/versions/{fingerprint}` → 200. DELETE by ULID or by name →
   404 "The version with identifier ... does not exist" even though GET lists it.
   ```
   curl -X DELETE -H "Authorization: Bearer $TOKEN" "$BASE/versions/{fingerprint}"
   ```
4. A version must be unassigned from channels to delete? No — keepers were on
   channels; we simply never deleted those. Deleting a channel-pinned version
   was not tested. Do it in the UI if you need to.

## Cleanup runbook (tidy AMIs + HCP versions)

Order matters: destroy instance → delete HCP versions → deregister AMIs →
delete snapshots → (optionally) retire a CI side.

1. **Destroy the demo instance** via TFC workspace `<your-hcptf-org>/packer-demo`
   (remote execution, **auto-apply off** — must confirm apply manually):
   ```sh
   TFE_TOKEN=$(jq -r '.credentials["app.terraform.io"].token' ~/.terraform.d/credentials.tfrc.json)
   WS=<workspace-id>   # packer-demo workspace (TFC UI → workspace → API URL)
   curl -s -X POST -H "Authorization: Bearer $TFE_TOKEN" -H "Content-Type: application/vnd.api+json" \
     "https://app.terraform.io/api/v2/runs" \
     -d "{\"data\":{\"type\":\"runs\",\"attributes\":{\"is-destroy\":true,\"message\":\"tidy-up\"},\"relationships\":{\"workspace\":{\"data\":{\"type\":\"workspaces\",\"id\":\"$WS\"}}}}}"
   # poll: run status plan->cost_estimated, then:
   curl -s -X POST -H "Authorization: Bearer $TFE_TOKEN" -H "Content-Type: application/vnd.api+json" \
     "https://app.terraform.io/api/v2/runs/{RUN_ID}/actions/apply" -d '{"comment":"ok"}'
   ```
2. **List + delete HCP versions** (keep channel-pinned ones; see quirk 3 for the key):
   ```sh
   curl -s -H "Authorization: Bearer $TOKEN" "$BASE/versions?page_size=100"   # list
   curl -s -X DELETE -H "Authorization: Bearer $TOKEN" "$BASE/versions/{FINGERPRINT}"
   ```
3. **Deregister AMIs + delete snapshots** (snapshot id is in `BlockDeviceMappings[0].Ebs`):
   ```sh
   aws --profile <profile> ec2 deregister-image --region <region> --image-id ami-xxx
   aws --profile <profile> ec2 delete-snapshot   --region <region> --snapshot-id snap-xxx
   ```
4. **Retire the GitHub Actions side** (reversible with `gh workflow enable`):
   ```sh
   gh workflow disable validate build deploy
   ```
   (To retire CodeBuild instead: `aws codebuild delete-webhook --project-name <name>` per project.)

## Pipeline gotchas (from the CodeBuild migration session)

1. CodeBuild project role needs `codeconnections:GetConnection` **+ `GetConnectionToken`**, not just `UseConnection` — else `CreateProject` fails with `OAuthProviderException`.
2. Webhook `FILE_PATH` filters are **regex, not glob** — `packer/**` is invalid, `packer/.*` works.
3. CodeBuild `standard:7.0` lacks ansible (GH runners ship it) and its old awscli lacks `--source-version-override` → use `--cli-input-json`.
4. `ansible-core 2.19` breaks tmp-dirs under packer's ansible proxy → pin `<2.19` and set `remote_tmp=/tmp/ansible`.
5. packer ansible provisioner `user` **defaults to the local packer user** (root in CodeBuild, runner on GH) → pin `user = "ec2-user"` explicitly.
6. `post_build` runs even after a failed build (unlike Actions) → gate the cascade on `CODEBUILD_BUILD_SUCCEEDING`.
7. The global "AWS OIDC" TFC varset broke the CI workspace → switch it to local execution mode.

Current live state (instance, AMIs, HCP versions, which side is enabled): see `ci/STATE.md`
(local only, gitignored — it drifts by design).
