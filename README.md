# Platform Engineer (DevOps) – Technical Challenge

Welcome to the take-home technical challenge for the **Platform Engineer (DevOps)** role.

This challenge is designed to assess your real-world skills in Kubernetes, Infrastructure as Code, CI/CD, observability, and security. It mirrors the kind of work you will do day-to-day on our platform team.

---

## ⏱ Time Expectation

**3–4 hours.** You are not expected to complete every section perfectly. We care more about your reasoning, code quality, and how you handle trade-offs than about a fully working end-to-end solution.

---

## 📁 Repository Structure

```
.
├── README.md                  ← You are here
├── SUBMISSION.md              ← Fill this in before submitting
├── terraform/
│   ├── environments/
│   │   └── staging/           ← Broken Terraform config (Task 1)
│   └── modules/
│       └── eks-cluster/       ← Incomplete EKS module (Task 1)
├── kubernetes/
│   ├── base/                  ← Base Kubernetes manifests (Task 2)
│   └── overlays/
│       └── staging/           ← Kustomize overlay (Task 2)
├── ci-cd/
│   └── pipeline.yml           ← Broken GitHub Actions pipeline (Task 3)
├── scripts/
│   └── incident.sh            ← Incident triage helper (Task 4)
└── docs/
    └── architecture-brief.md  ← Context for Task 5
```

---

## 🧩 Tasks Overview

| # | Area | Task |
|---|------|------|
| 1 | Terraform / IaC | Fix and extend a broken EKS Terraform module |
| 2 | Kubernetes | Harden a misconfigured application deployment |
| 3 | CI/CD | Repair and improve a GitHub Actions pipeline |
| 4 | Scripting | Write an incident triage script |
| 5 | Architecture | Design a hybrid cluster observability stack |

Full task details are in [`docs/TASKS.md`](docs/TASKS.md).

---

## 🚀 Getting Started

```bash
# Fork this repository to your own GitHub account
# Clone your fork
git clone https://github.com/YOUR_USERNAME/platform-engineer-challenge.git
cd platform-engineer-challenge

# Create a branch for your work
git checkout -b solution/your-name

# Work through the tasks — commit as you go
# Meaningful commit messages are assessed

# When done, open a Pull Request against your own fork's main branch
# Share the PR link with us
```

> **Do not open a PR against the original repository.**

---

## 📝 Submission

Before submitting, fill in [`SUBMISSION.md`](SUBMISSION.md) with:
- What you completed
- Key decisions and trade-offs
- What you would do with more time
- Any assumptions you made

Then share the **GitHub PR link** with your hiring contact.

---

## 💡 Assessment Criteria

| Criterion | Weight |
|-----------|--------|
| Correctness – does it work? | 30% |
| Security posture | 20% |
| Code quality and clarity | 20% |
| Documentation and reasoning | 15% |
| Git hygiene (commits, PR description) | 15% |

---

## ❓ Questions

If anything is unclear, make a reasonable assumption, document it in `SUBMISSION.md`, and move on. This is intentional — we want to see how you handle ambiguity.
