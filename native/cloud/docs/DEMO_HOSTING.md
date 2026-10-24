# Demo hosting — 24 October 2026

The current HTTPS API is **https://relay.stepcheck.app**. It uses:

Namecheap DNS → AWS CloudFront → HTTPS Cloudflare Quick Tunnel → this Mac's API
on loopback port8788 → Cognito, DynamoDB, S3, Transcribe and Bedrock as needed.
The worker on the same Mac processes queued batch speech and AI requests.

During build20 work on24October: the old Quick Tunnel exited and the
public domain returned Cloudflare1033. Started a detached replacement and updated
only the existing CloudFront origin to
`computation-disc-copies-improvement.trycloudflare.com`. API/worker restarted with
the same demo18 private config; `relay.stepcheck.app` is unchanged. Final preflight
and live announcement tests passed after recovery. This incident demonstrates why
the Mac/temporary-tunnel deployment is a supervised demo dependency.

CloudFront distribution `E35672O7SGUTD2` uses CachingDisabled and
AllViewerExceptHostHeader. Authorization and WebSocket headers reach the API;
the origin Host remains the Quick Tunnel hostname. API responses are no-store.
Two enrolled roles returned the correct account on repeated requests, anonymous
access returned401, and native streaming passed over the custom domain.

Only two new DNS records were added: `relay` points to
`du685az67zetl.cloudfront.net`; the ACM validation CNAME proves control of that
subdomain. The existing apex/www website, mail records and nameservers were kept.
The ACM certificate is non-exportable and covers only `relay.stepcheck.app`.

This domain is a stable address, not an always-on compute service or an ASR speed
improvement. The Mac must remain powered, awake and connected to internet. If the
Quick Tunnel restarts with another random hostname, the distribution's origin
must be updated and deployed. The current tunnel should therefore stay running
through the rehearsal. The Mac was kept awake for eight hours starting around
03:19 PDT, not indefinitely.

An always-on PC is a reasonable later origin if its OS, network and authenticated
remote access are available. No such PC connection was configured here, so no
claim of PC deployment is made. Do not use unrelated research/HPC machines.
The dedicated Lambda role `relay-cloud-mvp-execution` still did not exist at the
last check. No IAM permissions were changed to bypass that blocker.

## Start / restart the API and worker

Use Python3.13 and install `cloud/requirements.lock` into a virtual environment.
Keep the AWS config, login cache, account memberships and credentials outside Git.
After validating the intended AWS account and a refreshed login, start:

```
PYTHONPATH=cloud python -m relay_backend serve --config /private/aws-config.json --port 8788
PYTHONPATH=cloud python -m relay_backend worker --config /private/aws-config.json
```

Bind the API only to loopback; expose it through the existing TLS tunnel.
Do not run a second listener on8788. Current private runtime config is documented
in the local work plan, not committed. Liveness `/v1/health` does not invoke AI
and cannot certify that the AWS login or worker is operational. Check an enrolled
`/v1/me`, worker progress, and a bounded synthetic workflow before presenting.

## Observed limits

Service Quotas reported standard Transcribe streaming concurrency25, stream starts
25/sec, and in-region Nova Lite2,000 requests/min and4M tokens/min in us-east-1.
These are account limits, not measured performance or guaranteed capacity.
The demo's own caps were raised from30 requests/5 transcription allocations to
100/20; counters were preserved. Final observed counters were24 requests/8 transcription allocations after the renewal checks (76/12 remain). Two direct
AWS streaming probes also ran outside those application counters. Four global
live sessions and one per account are enforced in the application.

Measured single synthetic sample:1.824s of audio, ready956ms, first partial2108ms,
durable complete3663ms through the custom hostname, including realtime pacing.
This is not a latency benchmark. Noisy/8kHz speech and repeated-failure reliability
have not been measured. The observed transcription still required correction of
“Shelter A,” which AWS recognized as “Sheltering.”

## Read-only preflight

Run from the repository with the existing private runtime config and one enrolled
session file (never commit either file):

```
PYTHONPATH=cloud /path/to/venv/bin/python cloud/scripts/demo_preflight.py \
  --config /private/aws-config.json \
  --session-file /private/enrolled-session.json \
  --output /tmp/relay-preflight.json
```

It checks valid HTTPS, account identity, anonymous rejection, authorized receiving
addresses, the AWS account and remaining application allocations. It never invokes
AI. A worker process being present is not proof of completed job processing; use
the synthetic app rehearsal for that. One restart during simultaneous simulator
setup took several minutes in local Python imports; the API later started normally.
Start and verify the runtime before presenting, not during a live demo.

## Move to the always-on PC later

The Mac is the verified origin today. An always-on PC can remove dependence on the
laptop's lid/battery, but no PC address, OS or authenticated connection was available
in this task, and no PC deployment has been performed.

1. Clone this private repository on the PC. Install Python3.13 and create a virtual
   environment; install `cloud/requirements.lock`. Run the backend tests there.
2. Sign into the same authorized AWS workshop account/profile on the PC. Configure
   its own local AWS login/cache paths. Do not put credentials into the repository,
   app, domain DNS, Docker image or public URL.
3. Copy the non-secret backend settings/memberships into a private config, adjusting
   filesystem paths for that OS. Preserve the DynamoDB namespace and account guard.
4. Run one API and one worker. On Windows, set `PYTHONPATH` to the checkout's `cloud`
   directory and use the virtual environment's `Scripts/python.exe`; on Linux use
   the commands above. The same Python API supports both; this host migration has
   not been tested here.
5. Start an authenticated TLS ingress/tunnel on that PC and verify health, account
   isolation, WebSocket speech and the full synthetic workflow before switching.
6. Update only this CloudFront distribution's origin to the new HTTPS hostname;
   retain its alias, certificate, disabled cache and authorization forwarding.
   Wait for deployment and re-run preflight. Phones keep `relay.stepcheck.app`.
7. Only after the new origin passes, stop the old Mac API/worker/tunnel. Add normal
   OS service supervision and verify reboot recovery on the PC.

Changing the domain alone cannot speed up AWS inference. Live transcription and
avoiding excessive serial refresh calls address the latency observed in this demo.

## Workshop login expiry and renewal

At the final check, `/v1/health` still worked while storage calls returned503 because
the AWS CLI refresh token had expired. The same workshop role was renewed at about
05:17PDT on24 October, then API and worker were restarted. Preflight, native live
speech and a new Bedrock worker request all passed afterward. No IAM grant changed.

Use AWS CLI2's `aws login --profile relay-workshop --region us-east-1 --remote`
with this runtime's private `AWS_CONFIG_FILE`, `AWS_SHARED_CREDENTIALS_FILE`, and
`AWS_LOGIN_CACHE_DIRECTORY`. The official CLI is locally extracted under
`/Users/RELAY_DEVELOPER/Documents/Codex/2026-10-23/b/work/awscli-package/aws-cli.pkg/Payload/aws-cli/aws`.
It is not on PATH. Keep those private paths in the local runtime configuration.

Open the generated URL, select the existing **WSParticipantRole/Participant** session
in account **928489693154**, and copy the page's full verification code into the
CLI that started the login. Do not use a different account or paste codes into chat.
If that session expired, open **AWS Workshop Studio → Open AWS console** first to
renew the existing workshop federation. Do not create new IAM credentials.
Verify `aws sts get-caller-identity --profile relay-workshop`, then restart only the
owned API/worker, preserving the existing tunnel and persistent stores. Run preflight
and a small synthetic flow before presenting. Workshop access is temporary; this
is not unattended permanent hosting.


Build19 update: live runtime uses the private `aws-config-demo18.private.json`
configuration with `accelerate_previews=true`. API process3671 and ordinary worker
2040 use it; tunnel44716 was preserved. Final observed app allocations34/100 and
10/20. There were two additional direct synthetic Bedrock diagnostic calls outside
that counter. Read [EXTRACTION.md](EXTRACTION.md) for the one-slot preview lane and
foreground snapshot polling. Runtime PIDs are observations, not permanent IDs.
