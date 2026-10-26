#!/usr/bin/env bash
# Gate an OSV-Scanner JSON report on the organization severity definition:
# High/Critical = CVSS score >= 7.0, or advisory severity label HIGH or CRITICAL.
#
# Exit codes:
#   0  scanner ran and found no High/Critical vulnerabilities
#   1  scanner ran and found at least one High/Critical vulnerability
#   2  scanner did not produce a usable report (missing file or invalid JSON)
set -euo pipefail

file="${1:?usage: osv-gate.sh <osv-results.json>}"

if [[ ! -s "$file" ]]; then
  echo "::error::OSV-Scanner report '$file' is missing or empty: the scanner did not run successfully."
  exit 2
fi
if ! jq -e 'type == "object" and has("results")' "$file" >/dev/null 2>&1; then
  echo "::error::OSV-Scanner report '$file' is not a valid OSV JSON report: the scanner did not run successfully."
  exit 2
fi

total=$(jq '[.results[]?.packages[]?.vulnerabilities[]?] | length' "$file")

# Each package reports vulnerability groups with a computed max CVSS score, and
# each vulnerability may carry an advisory severity label from its database.
findings=$(jq -r '
  [ .results[]?.packages[]? | . as $p
    | ( ($p.groups // [])[]
        | select(((.max_severity // "0") | try tonumber catch 0) >= 7.0)
        | { pkg: $p.package.name, ver: $p.package.version, ids: (.ids | join(",")), sev: ("CVSS " + .max_severity) } ),
      ( ($p.vulnerabilities // [])[]
        | select(((.database_specific.severity // "") | ascii_upcase) | IN("HIGH", "CRITICAL"))
        | { pkg: $p.package.name, ver: $p.package.version, ids: .id, sev: ("label " + .database_specific.severity) } )
  ] | group_by(.pkg, .ver, .ids)
  | map({ pkg: .[0].pkg, ver: .[0].ver, ids: .[0].ids, sev: (map(.sev) | unique | join(", ")) })[]
  | "\(.pkg)@\(.ver)\t\(.ids)\t\(.sev)"' "$file")

if [[ -n "$findings" ]]; then
  echo "::error::High/Critical vulnerabilities found (total vulnerabilities reported: $total):"
  printf 'PACKAGE\tADVISORY\tSEVERITY\n%s\n' "$findings" | column -t -s $'\t'
  exit 1
fi

echo "OSV-Scanner ran successfully: $total vulnerabilities reported, none High/Critical."
