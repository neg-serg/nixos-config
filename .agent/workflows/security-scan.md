# Security Scan

Read-only evidence-backed vulnerability discovery (ported from omp security/ + oh-my-opencode
security-research). Produces ONE report with honest coverage; findings calibrated by actual
exploitability, not just severity labels.

## Steps

1. **Define the immutable scan plan** before any work:

   - Repository root, target kind (repo / diff / file set), base and head revisions.
   - Include/exclude paths; knowledge bases (if any); plan fingerprint.
   - Scope is fixed: do not silently expand or shrink it mid-scan.

1. **Inventory the exact scope first** — what is actually in scope, what is out.

1. **Delegate disjoint review assignments** (omp security-reviewer pattern):

   - Split the scope into non-overlapping slices; each slice to a read-only reviewer agent (tools:
     read, grep, glob, lsp, ast_grep) with a structured findings schema: rule_id, title, summary,
     severity (critical/high/medium/low/informational), confidence, category, locations (path + line
     range), cwe, evidence.
   - Each reviewer must attach evidence (file:line + explanation), never assert without a source.

1. **Reconcile all worker output**: dedupe, resolve conflicts by inspecting evidence, re-read code
   where claims conflict.

1. **Severity by actual exploitability** (security-research idea): a finding's severity is judged by
   whether/how an attacker could trigger it in this codebase, not by the CWE label alone.

1. **Publish ONE report** (omp security_publish): findings + honest coverage summary (what was and
   was NOT scanned) + final verdict. No silent partial coverage.

## Rules

- Read-only: scan never modifies the target.
- Empty search result → try at least one alternate strategy before concluding absence.
- Coverage honesty: report skipped/unscanned areas explicitly.
