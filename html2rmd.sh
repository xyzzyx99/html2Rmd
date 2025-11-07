#!/usr/bin/env bash
# html2rmd.sh — Convert HTML → cleaned Rmd, optionally add header/footer
# Usage:
#   ./html2rmd.sh [--no-header] input.html [output.Rmd]
#
# Options:
#   --no-header    Do not insert YAML header and reference section
#
# Default output: basename(input).Rmd

set -euo pipefail

# --- dependencies ---
if ! command -v pandoc >/dev/null 2>&1; then
  echo "Error: pandoc not found." >&2
  exit 1
fi
if ! sed --version >/dev/null 2>&1 || ! sed --version | head -n1 | grep -qi 'gnu'; then
  echo "Error: GNU sed required (for -z multi-line mode)." >&2
  exit 1
fi
if ! command -v perl >/dev/null 2>&1; then
  echo "Error: perl not found." >&2
  exit 1
fi

# --- parse args ---
add_header=true
if [[ "${1:-}" == "--no-header" ]]; then
  add_header=false
  shift
fi

in_html="${1:-}"
if [[ -z "${in_html}" ]]; then
  echo "Usage: $0 [--no-header] input.html [output.Rmd]" >&2
  exit 1
fi
if [[ ! -f "$in_html" ]]; then
  echo "Error: input file '$in_html' not found." >&2
  echo "Usage: $0 [--no-header] input.html [output.Rmd]" >&2
  exit 1
fi

out="${2:-${in_html%.html}.Rmd}"

# --- define HEADER and REFERENCE blocks ---
read -r -d '' HEADER <<'HEADER_EOF' || true
---
params:
  homework: "HW3"
  group: "Group 12"
  git_url: https://example.com
  author: "Joe, Han, Jonathan"
title: "`r params$homework`"
subtitle: |
  `r params$group`
  [![GitHub](https://img.shields.io/badge/GitHub-Repo-blue?logo=github)](`r params$git_url`)
  <span style="font-size:70%"><`r params$git_url`></span>
author: "`r params$author`"
date: "`r Sys.Date()`"
output: html_document
---
HEADER_EOF

read -r -d '' REFERENCE <<'REFERENCE_EOF' || true
# References
- Answer 1: <https://chatgpt.com/share/690d6e2e-82a4-8005-9b67-2af0a1bc3581>
- Answer 2: <>
- Answer 3: <>
REFERENCE_EOF

# --- temp files ---
tmp_md="$(mktemp --suffix=.md)"
tmp1="$(mktemp)"
tmp2="$(mktemp)"
tmp3="$(mktemp)"
tmp_body="$(mktemp)"
trap 'rm -f "$tmp_md" "$tmp1" "$tmp2" "$tmp3" "$tmp_body"' EXIT

# --- 1) Convert HTML → Markdown ---
pandoc "$in_html" -o "$tmp_md"

# --- 2) Cleanup passes ---
sed -E '
  /^:::/d;                                 # drop ::: lines
  /^[[:space:]]*-{2,}[[:space:]]*$/d;      # drop lines of repeated dashes
  s/\[([^]]*)\]\{[^}]*\}/\1/g;             # [text]{...} -> text
' "$tmp_md" > "$tmp1"

sed -zE 's/\{[^}]*\.[^}]+[^}]*\}//g' "$tmp1" > "$tmp2"

sed -E '
  s/\\{2,}([[(])/\\\1/g;       # \\[ or \\( -> \[ or \(
  s/\\{2,}([])])/\\\1/g;       # \\] or \\) -> \] or \)
  s/\[\s*(\\[[(])/\1/g;        # [ \[  -> \[
  s/(\\[][)])\s*\]/\1/g;       # \] ]  -> \]
' "$tmp2" > "$tmp3"

# --- 3) Inside-math unescaping (two-step rule with sentinel) ---
perl -0777 - "$tmp3" > "$tmp_body" <<'PERL'
use strict;
use warnings;
use utf8;
local $/ = undef;
my $s = <>;

my $SENT = "\x{E000}"; # sentinel character

sub clean_math {
  my ($m) = @_;
  # Step 1: \\X -> (sentinel)X
  $m =~ s/\\\\(.)/${SENT}$1/gs;
  # Step 2: \X -> X
  $m =~ s/\\(.)/$1/gs;
  # Step 3: restore sentinel to literal backslash
  $m =~ s/\Q$SENT\E/\\/g;
  return $m;
}

# \[ ... \]
$s =~ s{ \\ \[ (.*?) \\ \] }{ "\\[" . clean_math($1) . "\\]" }egsx;
# \( ... \)
$s =~ s{ \\ \( (.*?) \\ \) }{ "\\(" . clean_math($1) . "\\)" }egsx;
# $$ ... $$
$s =~ s{ \$\$ (.*?) \$\$ }{ "\$\$" . clean_math($1) . "\$\$" }egsx;

print $s;
PERL

# --- 4) Assemble final output ---
if $add_header; then
  {
    printf '%s\n\n' "$HEADER"
    cat "$tmp_body"
    printf '\n%s\n' "$REFERENCE"
  } > "$out"
else
  cat "$tmp_body" > "$out"
fi

echo " Converted ${in_html} → ${out}"
if ! $add_header; then
  echo "   (Header and reference section omitted)"
fi
