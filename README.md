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

### Step 1 — Clone the repository

```bash
git clone https://github.com/Palladium-hub/platform-engineer-challenge.git
cd platform-engineer-challenge
```

### Step 2 — Create your own GitHub repository

1. Go to [github.com/new](https://github.com/new)
2. Name it `platform-engineer-challenge` (or similar)
3. Set it to **Public**
4. **Do not** initialise it with a README, .gitignore, or licence

### Step 3 — Push to your own repository

```bash
# Point the remote to your own repo
git remote set-url origin https://github.com/YOUR_USERNAME/platform-engineer-challenge.git

# Push
git push -u origin master
```

### Step 4 — Work on a branch

```bash
git checkout -b solution/your-name
```

Work through the tasks, committing as you go. Meaningful commit messages are part of the assessment.

### Step 5 — Submit

1. Fill in [`SUBMISSION.md`](SUBMISSION.md) honestly — what you completed, decisions made, and what you'd do with more time.
2. Push your branch and open a **Pull Request within your own repository** (base: `master` ← compare: `solution/your-name`).
3. Share the **PR link** with your hiring contact.

> **Do not open a PR against the original Palladium-hub repository.**

---

## 📝 Submission Checklist

Before sending the PR link, confirm:

- [ ] All attempted tasks are committed on your `solution/your-name` branch
- [ ] `SUBMISSION.md` is filled in
- [ ] Your repository is set to **Public** so we can review it
- [ ] The PR is opened within **your own fork**, not the original repo

---

## ❓ Questions

If anything is unclear, make a reasonable assumption, document it in `SUBMISSION.md`, and move on. This is intentional — we want to see how you handle ambiguity.
