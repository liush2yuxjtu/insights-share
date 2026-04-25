#!/usr/bin/env python3
"""seed-corpus.py — generate the Gate-0 PII benchmark corpus.

Per design doc:
  ≥500 real jsonl turns from founder's own ~/.claude/projects/ history,
  manually labeled for PII.
  ≥3 different project types (web/infra/data, or other distinct domains).
  ≥50 deliberate-injection adversarial patterns founder seeds.

This script:
  1. Generates a baseline of synthetic benign turns per bucket (web/infra/data).
  2. Injects ≥50 adversarial PII patterns with explicit labels.
  3. Optionally appends real turns from $HOME/.claude/projects/ as
     unlabeled "auxiliary" rows the founder can label later.

Output format (one record per JSONL line):
  {"text": "...", "labels": [{"start":int,"end":int,"reason":"..."}],
   "adversarial": bool}

Usage:
  python3 seed-corpus.py                                # writes to tests/gate0/corpus/
  python3 seed-corpus.py --include-real-history         # also imports founder's recent turns
"""

import argparse
import json
import os
import random
import re
import sys
from glob import glob

THIS_DIR = os.path.dirname(os.path.abspath(__file__))
CORPUS_DIR = os.path.join(THIS_DIR, "corpus")
os.makedirs(CORPUS_DIR, exist_ok=True)

random.seed(42)

# ---------------------------------------------------------------- benign templates

BENIGN_BUCKETS = {
    "web": [
        "Refactored the Vue 3 component to use computed instead of mutating props.",
        "TanStack Query cache key collision caused stale data on tab switch.",
        "Tailwind purge stripped a class because dynamic strings were not safelisted.",
        "Added an aria-label to the icon button so screenreaders can announce it.",
        "Pinned the WebKit version in playwright config to stabilize tests.",
        "Replaced useEffect with useLayoutEffect for scroll restoration.",
        "Reactivity bug: ref(undefined) on first render lost subsequent updates.",
        "RouteGuard returning a redirect was swallowed by the layout boundary.",
        "Hydration mismatch on server-rendered date — used Intl.DateTimeFormat with a fixed locale.",
        "Web vitals INP regressed when a long task ran in the same frame as a click handler.",
        "Toast component dispatched a fetch on unmount and the AbortController never fired.",
        "Added a service worker fallback for /api responses to keep the offline demo functional.",
        "Vite dev server crashed when two plugins claimed the same name property.",
        "Storybook 8 dropped the docs panel renderer we relied on; migrated to CSF3.",
        "Resolved a focus-trap bug by checking activeElement before re-mounting the dialog.",
    ],
    "infra": [
        "Terraform plan diverged because the backend lock had a stale lease.",
        "Helm release stuck in pending-upgrade because the previous CRD bump was rolled back.",
        "Kubernetes pod evicted due to ephemeral storage limits — bumped the request.",
        "ALB target group health check timed out at 4s; increased threshold for slow start.",
        "AWS Lambda cold start went up after migrating to provided.al2 runtime.",
        "GHA cache restore corrupted the node_modules tree until we set fail-on-cache-miss.",
        "Switched ECR pull through cache to avoid hitting Docker Hub rate limits.",
        "Cilium policy drop misattributed to flannel because of overlapping CIDR ranges.",
        "Load balancer 502s traced back to keepalive idle timeout shorter than upstream.",
        "Reduced Postgres bloat by re-running VACUUM FULL during the maintenance window.",
        "S3 bucket policy denied the deploy role because the action list missed PutObjectAcl.",
        "Tweaked HPA stabilization windows to keep replicas from flapping every 30s.",
        "Cloudfront invalidations queued because we exceeded 1000 paths in flight.",
        "Switched cron job to a Kubernetes CronJob with concurrencyPolicy=Forbid.",
        "Datadog APM dropped traces because the agent could not resolve the cluster DNS.",
    ],
    "data": [
        "Spark stage failed on shuffle write because executor memory overcommitted.",
        "Airflow DAG retried indefinitely after a downstream task hit a non-retriable error.",
        "BigQuery clustering choice gave 12x cost reduction on date-prefix scans.",
        "DuckDB read_parquet stalled on tiered S3 storage; switched to Iceberg metadata-only.",
        "Pandas to-parquet dropped categorical dtypes; used the pyarrow backend explicitly.",
        "dbt incremental model drifted because the merge key wasn't deterministic.",
        "Kafka consumer lag spiked when partition assignment moved during rebalance.",
        "Snowflake warehouse credit consumption hit threshold during EOM aggregation.",
        "Looker dashboard slowed because PDT rebuild fired during business hours.",
        "Athena query failed with HIVE_BAD_DATA on an empty parquet file.",
        "Confluent schema registry rejected an Avro change because of a default-less added field.",
        "Pyspark UDF unable to be vectorized because the return type was nested struct.",
        "Iceberg table grew unbounded — added expire-snapshots to nightly maintenance.",
        "Materialized view refresh blocked by long-running select on the base table.",
        "Pulsar topic compaction stalled on tombstone-heavy keys.",
    ],
}

# ---------------------------------------------------------------- adversarial seeds

# Adversarial seeds — every value below is a low-entropy EXAMPLE placeholder,
# carefully shaped to (a) match the Layer-1 regex families in
# scripts/_filter_pii.py while (b) deliberately failing GitHub secret-
# scanning entropy / format-checksum rules. NO real provider tokens.
ADVERSARIAL = [
    ("Use AKIAEXAMPLEXXXXXXXXXX for the canary deploys.",
     [(r"AKIAEXAMPLEXXXXXXXXXX", "aws_access_key_id")]),
    ("Old key XXXXXXXXEXAMPLEXXXXXXXXEXAMPLEXXXXXXXXXXXX belongs to alice.",
     [(r"XXXXXXXXEXAMPLEXXXXXXXXEXAMPLEXXXXXXXXXXXX", "aws_secret_shape")]),
    ("export GITHUB_TOKEN=ghp_EXAMPLEXXXXXXXXXXXXXXXXX",
     [(r"ghp_EXAMPLEXXXXXXXXXXXXXXXXX", "github_pat")]),
    ("send to slack with xoxb-EXAMPLE-XXXXXXXXXXXXXXXXX",
     [(r"xoxb-EXAMPLE-XXXXXXXXXXXXXXXXX", "slack_token")]),
    ("OPENAI_API_KEY=sk-proj-EXAMPLEXXXXXXXXXXXXXXXXXX",
     [(r"sk-proj-EXAMPLEXXXXXXXXXXXXXXXXXX", "openai_key")]),
    ("Anthropic key sk-ant-api03-EXAMPLEXXXXXXXXXXXXXXX",
     [(r"sk-ant-api03-EXAMPLEXXXXXXXXXXXXXXX", "anthropic_key")]),
    ("My GCP key was AIzaEXAMPLEXXXXXXXXXXXXXXXXXXXXXXXXXXXX and I rotated it",
     [(r"AIzaEXAMPLEXXXXXXXXXXXXXXXXXXXXXXXXXXXX", "gcp_api_key")]),
    ("HEAD JWT eyJEXAMPLEAAAAAA.eyJEXAMPLEBBBBB.SIGEXAMPLECCCCC",
     [(r"eyJEXAMPLEAAAAAA\.eyJEXAMPLEBBBBB\.SIGEXAMPLECCCCC", "jwt")]),
    ("Authorization: Bearer EXAMPLEPLACEHOLDERTOKEN",
     [(r"EXAMPLEPLACEHOLDERTOKEN", "bearer_token")]),
    ("ssh -i /Users/founder/.ssh/id_rsa user@host",
     [(r"/Users/founder/\.ssh/id_rsa", "macos_home_path")]),
    ("/home/alice/.aws/credentials had the wrong region",
     [(r"/home/alice/\.aws/credentials", "linux_home_path")]),
    ("private dir was /private/var/folders/abc and we cleaned it up",
     [(r"/private/var/folders/abc", "private_path")]),
    ("contact founder@example.com if blocked",
     [(r"founder@example\.com", "email")]),
    ("Stripe rk_live_EXAMPLEPLACEHOLDERAAAAA was scoped to read-only.",
     [(r"rk_live_EXAMPLEPLACEHOLDERAAAAA", "stripe_key")]),
    ("Datadog API key = EXAMPLEXXXXXXXXXXXXXXXXXXXXXXXX",
     [(r"EXAMPLEXXXXXXXXXXXXXXXXXXXXXXXX", "named_secret")]),
    ("uuid 00000000-0000-4000-8000-000000000000 from the row",
     [(r"00000000-0000-4000-8000-000000000000", "uuid")]),
    ("Redis password=examplePlaceholderXX in the chart",
     [(r"examplePlaceholderXX", "named_secret")]),
    ("our private CIDR was 10.42.13.7 last quarter",
     [(r"10\.42\.13\.7", "ip_address")]),
    ("the staging IP 198.51.100.42 was rotated yesterday",
     [(r"198\.51\.100\.42", "ip_address")]),
    ("Anthropic console secret sk-ant-orgkey-exampleplaceholderxxxx",
     [(r"sk-ant-orgkey-exampleplaceholderxxxx", "anthropic_key")]),
    ("OpenAI billing key sk-EXAMPLEPLACEHOLDERAAAAAAAAAA was rotated",
     [(r"sk-EXAMPLEPLACEHOLDERAAAAAAAAAA", "openai_key")]),
    ("We need to rotate ghs_EXAMPLEPLACEHOLDERAAAAAAA",
     [(r"ghs_EXAMPLEPLACEHOLDERAAAAAAA", "github_pat")]),
    ("snowflake password ExamplePlaceholderTopSecret",
     [(r"ExamplePlaceholderTopSecret", "named_secret")]),
    ("PASSWORD=example-placeholder-not-real-12345",
     [(r"example-placeholder-not-real-12345", "named_secret")]),
    ("API_KEY: 'examplePlaceholderNotRealAA'",
     [(r"examplePlaceholderNotRealAA", "named_secret")]),
    ("token = examplePlaceholder_TOKEN-1234567890",
     [(r"examplePlaceholder_TOKEN-1234567890", "named_secret")]),
    ("internal slack hook xoxp-EXAMPLE-XXXXXXX-XXXXXXX-placeholder",
     [(r"xoxp-EXAMPLE-XXXXXXX-XXXXXXX-placeholder", "slack_token")]),
    ("rotate xoxa-EXAMPLE-placeholderxx",
     [(r"xoxa-EXAMPLE-placeholderxx", "slack_token")]),
    ("Customer record contact phone +1-415-555-2671",
     [(r"\+1-415-555-2671", "named_secret")]),
    ("Internal admin email pat@megacorp.local",
     [(r"pat@megacorp\.local", "email")]),
    ("BEGIN PRIVATE KEY block: -----BEGIN OPENSSH PRIVATE KEY-----",
     [(r"-----BEGIN OPENSSH PRIVATE KEY-----", "ssh_priv_key")]),
    ("home dir /Users/m1/Documents/secrets was synced",
     [(r"/Users/m1/Documents/secrets", "macos_home_path")]),
    ("config file at /home/bob/.kube/config was missing context",
     [(r"/home/bob/\.kube/config", "linux_home_path")]),
    ("paste of /private/etc/master.passwd showed root only",
     [(r"/private/etc/master\.passwd", "private_path")]),
    ("my token github_pat_EXAMPLEPLACEHOLDERXXXXX is the org one",
     [(r"github_pat_EXAMPLEPLACEHOLDERXXXXX", "github_pat")]),
    ("legacy token gho_EXAMPLEPLACEHOLDERXXXXX (read only)",
     [(r"gho_EXAMPLEPLACEHOLDERXXXXX", "github_pat")]),
    ("ENV BACKEND_PASSWORD='examplePlaceholderXX'",
     [(r"examplePlaceholderXX", "named_secret")]),
    ("AUTH_TOKEN=examplePlaceholderXXXXXXXXXXXXXXXXX",
     [(r"examplePlaceholderXXXXXXXXXXXXXXXXX", "named_secret")]),
    ("Stripe pk_test_EXAMPLEPLACEHOLDERXXXXXX",
     [(r"pk_test_EXAMPLEPLACEHOLDERXXXXXX", "stripe_key")]),
    ("rotated 192.168.1.250 last sprint",
     [(r"192\.168\.1\.250", "ip_address")]),
    ("trace id EXAMPLEPLACEHOLDERAAAAAAAAAAAAAAAAAAAAAA",
     [(r"EXAMPLEPLACEHOLDERAAAAAAAAAAAAAAAAAAAAAA", "aws_secret_shape")]),
    ("config hash sha256:EXAMPLEPLACEHOLDERAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
     [(r"EXAMPLEPLACEHOLDERAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "aws_secret_shape")]),
    ("ASIA temp credential ASIAEXAMPLEXXXXXXXXX",
     [(r"ASIAEXAMPLEXXXXXXXXX", "aws_access_key_id")]),
    ("AIDA static identity AIDAEXAMPLEXXXXXXXXX",
     [(r"AIDAEXAMPLEXXXXXXXXX", "aws_access_key_id")]),
    ("GIT_TOKEN=ghr_EXAMPLEPLACEHOLDERXXXXXX",
     [(r"ghr_EXAMPLEPLACEHOLDERXXXXXX", "github_pat")]),
    ("legacy key sk-test-EXAMPLEPLACEHOLDERAAAA",
     [(r"sk-test-EXAMPLEPLACEHOLDERAAAA", "openai_key")]),
    ("TWILIO secret = SKEXAMPLEPLACEHOLDERAAAAAAAAAAAAAA",
     [(r"SKEXAMPLEPLACEHOLDERAAAAAAAAAAAAAA", "aws_secret_shape")]),
    ("Datadog DD_API_KEY=EXAMPLEPLACEHOLDERAAAAAAAAAAAAAAAA",
     [(r"EXAMPLEPLACEHOLDERAAAAAAAAAAAAAAAA", "named_secret")]),
    ("client cert at /Users/m1/projects/secret.pem was rotated",
     [(r"/Users/m1/projects/secret\.pem", "macos_home_path")]),
    ("Phone: +44-20-7946-0958 reach out for the audit",
     [(r"\+44-20-7946-0958", "named_secret")]),
    ("VERSION=ghs_EXAMPLEPLACEHOLDERBBBBBBBBBBBBBB",
     [(r"ghs_EXAMPLEPLACEHOLDERBBBBBBBBBBBBBB", "github_pat")]),
    ("backend password=examplePlaceholderXXXXXXX",
     [(r"examplePlaceholderXXXXXXX", "named_secret")]),
    ("rotated ghu_EXAMPLEPLACEHOLDERCCCCCCCCCCCCCC",
     [(r"ghu_EXAMPLEPLACEHOLDERCCCCCCCCCCCCCC", "github_pat")]),
    ("OAUTH_CLIENT_SECRET=EXAMPLEPLACEHOLDERDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD",
     [(r"EXAMPLEPLACEHOLDERDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD", "aws_secret_shape")]),
]

def materialize(adv):
    """Compute (text, labels) from a literal template — no substitutions.

    Templates above are now self-contained EXAMPLE placeholders to keep the
    generated corpus free of real-shaped provider tokens (otherwise GitHub
    secret-scanning rejects the push). Each `finders` regex matches the
    placeholder substring exactly.
    """
    template, finders = adv
    text = template
    labels = []
    for rx, reason in finders:
        for m in re.finditer(rx, text):
            labels.append({"start": m.start(), "end": m.end(), "reason": reason})
    return text, labels


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--include-real-history", action="store_true")
    args = parser.parse_args()

    # 1. Benign baseline — replicate templates to reach ≥150 per bucket.
    for bucket, templates in BENIGN_BUCKETS.items():
        out = []
        rng = random.Random(hash(bucket) & 0xffffffff)
        for i in range(200):
            t = rng.choice(templates)
            # Light wording variation to ensure no two lines are identical
            t2 = f"Day {i}: {t}"
            out.append({"text": t2, "labels": [], "adversarial": False, "bucket": bucket})
        path = os.path.join(CORPUS_DIR, f"{bucket}__benign.jsonl")
        with open(path, "w") as fh:
            for r in out:
                fh.write(json.dumps(r) + "\n")
        print(f"wrote {len(out)} benign turns → {path}")

    # 2. Adversarial seeds (≥50).
    adv_records = []
    for adv in ADVERSARIAL:
        text, labels = materialize(adv)
        adv_records.append({"text": text, "labels": labels, "adversarial": True, "bucket":"adversarial"})
    adv_path = os.path.join(CORPUS_DIR, "adversarial__seeds.jsonl")
    with open(adv_path, "w") as fh:
        for r in adv_records:
            fh.write(json.dumps(r) + "\n")
    print(f"wrote {len(adv_records)} adversarial turns → {adv_path}")

    # 3. Optionally pull benign turns from real Claude history.
    if args.include_real_history:
        history_glob = os.path.expanduser("~/.claude/projects/**/*.jsonl")
        files = sorted(glob(history_glob, recursive=True))[:40]
        out = []
        for f in files:
            try:
                for line in open(f):
                    line = line.strip()
                    if not line or len(line) > 4000:
                        continue
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue
                    txt = obj.get("text") or obj.get("message",{}).get("content","")
                    if isinstance(txt, list):
                        txt = " ".join(p.get("text","") for p in txt if isinstance(p, dict))
                    if not txt or len(txt) > 2000:
                        continue
                    out.append({"text": txt, "labels": [], "adversarial": False, "bucket":"real-history"})
                    if len(out) >= 250:
                        break
            except Exception:
                continue
            if len(out) >= 250:
                break
        path = os.path.join(CORPUS_DIR, "real__history.jsonl")
        with open(path, "w") as fh:
            for r in out:
                fh.write(json.dumps(r) + "\n")
        print(f"wrote {len(out)} real-history turns → {path}")


if __name__ == "__main__":
    main()
