# EBiM Infrastructure — documentation

Reports and documentation for the EBiM benchmark cloud simulation infrastructure pilot
(VRB / BinderHub on Google Cloud). All documents are in English.

| Document | What it is |
|---|---|
| [`collaboration-report.md`](./collaboration-report.md) | **Primary deliverable** — the academic-style results & collaboration report (contributions to EBiM and to VRB up front, engineering in appendices). **Export this to PDF** and attach to the email. Start here. |
| [`email-report.md`](./email-report.md) | Short cover note for the email (the PDF above is the attachment). |
| [`infrastructure-report.md`](./infrastructure-report.md) | Longer engineering-oriented technical report (companion / background detail). |
| [`stress-test-results.md`](./stress-test-results.md) | Load-test setup, results, and reproduction steps. |
| [`../deploy/`](../deploy/) | The GC deployment: automation scripts (`*.sh`), Kubernetes manifests (`*-gc.yaml`), and the full 16-step [`deployment-log.md`](../deploy/deployment-log.md). Sanitized for public release. |

## Before circulating — TODO

The primary deliverable is `collaboration-report.md` → export to PDF, attach to the email.
Final stress numbers and latency are already filled from `binder_stress_launch_final.ipynb` /
`stress_nodes_final.csv`. Remaining items before circulating:

- [x] Final results (20/20, startup 11–20 s, latency) in the report and `stress-test-results.md`.
- [x] Architecture diagram (Mermaid, Figure 1 in `collaboration-report.md` §3).
- [ ] Record the demo video (60–90 s) and drop the link into Figure 4 / §4.
- [ ] Capture Figure 2 (20 concurrent sessions) and Figure 3 (a live EBiM session in-browser).
- [ ] Export `collaboration-report.md` to PDF (e.g. `pandoc collaboration-report.md -o
      EBiM-VRB-collaboration-report.pdf`; render/export the Mermaid diagram to an image if your
      converter doesn't render Mermaid).
- [ ] Fill recipient names in `email-report.md`.

## Sensitive data — do NOT commit

This repository is **public** (BinderHub clones it to launch the lab). The following must
never be committed here:

- `gc-accounts.md` — GCP account emails **and passwords**.
- WireGuard private keys, Cloudflare tunnel credentials, Docker Hub tokens, `secret.yaml`.
- Account emails, static external IPs, and WireGuard public keys have been redacted
  (placeholders) in `deployment-log.md` and in the `../deploy/` scripts for this reason —
  those scripts are reference copies and **will not run until the placeholders are filled**.

The unredacted original build log and the account/credential files live in the separate
`gc-deploy` working directory, which should go to a **private** repository only.
