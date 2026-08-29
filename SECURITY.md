# Security policy

Please report suspected vulnerabilities through GitHub's private security
advisory flow instead of a public issue. Include the affected addon and
companion versions, a minimal reproduction, and the impact you observed. Do not
include Warcraft Logs credentials, access tokens, or private character data.

Security fixes target the latest published ApplicantScout Addon and its paired
`ApplicantScout-Companion` release train.

## Automated coverage

- Dependabot monitors every pinned GitHub Actions dependency. Repository
  dependency alerts and security updates must also remain enabled in GitHub.
- CodeQL does not support Lua. Runtime source is instead checked with pinned
  LuaLS diagnostics, Lua 5.1 syntax checks, paired behavioral contract tests,
  archive validation, and review.
- The paired companion repository runs CodeQL over its Python source. That scan
  does not extend into this repository's Lua source.
