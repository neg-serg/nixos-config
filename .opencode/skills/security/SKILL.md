______________________________________________________________________

---
name: security
description: "Network scanning (nmap), vulnerability scanning (nuclei), code analysis (semgrep), secret detection (gitleaks), and network diagnostics"
---

# Security Tools

Use CLI tools directly instead of MCP nmap, nuclei, semgrep, gitleaks, and nettools servers.

## Nmap — Network Scanning

```bash
# Quick scan
nmap -F TARGET

# Service/version detection
nmap -sV TARGET

# OS detection
nmap -O TARGET

# Full TCP scan
nmap -p- TARGET

# Script scan
nmap -sC TARGET

# UDP scan
nmap -sU TARGET

# Aggressive (OS + version + scripts + traceroute)
nmap -A TARGET
```

## Nuclei — Vulnerability Scanning

```bash
# Basic scan
nuclei -u https://TARGET

# With specific templates
nuclei -u https://TARGET -t cves/ -t exposures/

# List URLs from file
nuclei -l urls.txt

# Severity filter
nuclei -u https://TARGET -severity critical,high

# Output JSON
nuclei -u https://TARGET -json -o results.json
```

## Semgrep — Code Analysis

```bash
# Run all rules
semgrep --config=auto .

# Specific language
semgrep --config=p/python .

# Custom pattern
semgrep -e 'os.system(...)' --lang=py .

# Output SARIF
semgrep --config=auto --sarif -o results.sarif .

# Autofix
semgrep --config=auto --autofix .
```

## Gitleaks — Secret Detection

```bash
# Scan repo
gitleaks detect --source=/path/to/repo

# Scan with verbose
gitleaks detect -v --source=.

# Pre-commit scan
gitleaks protect --staged

# Output JSON
gitleaks detect --source=. --report-path=leaks.json
```

## Network Diagnostics

```bash
# DNS lookup
dig example.com
dig -x 1.2.3.4  # reverse lookup

# Connectivity
ping -c 4 HOST
traceroute HOST
mtr HOST

# Port check
nc -zv HOST PORT
ss -tlnp  # listening ports

# HTTP debug
curl -v https://example.com
curl -I https://example.com  # headers only

# SSL check
openssl s_client -connect example.com:443 -servername example.com
```

## Usage Notes

- Port scanning requires appropriate permissions (sudo for SYN scan)
- Nuclei and semgrep need updated templates/rules databases
- Respect scope and authorization when scanning
