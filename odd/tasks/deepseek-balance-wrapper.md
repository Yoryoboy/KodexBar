# DeepSeek Balance Wrapper

## Goal
Normalize the DeepSeek balance returned by CodexBar CLI so the KodexBar popup can consume it as structured credit data.

## Tasks
- [x] Transform DeepSeek's balance description into structured `credits` fields in `~/.local/bin/codexbar-multi`.
- [x] Verify combined usage output, shell syntax, and the deployed popup data path without exposing credentials.

## Evidence
- `bash -n ~/.local/bin/codexbar-multi` passed.
- Combined usage still returns 3 Codex entries, 1 OpenCode Go entry, and 1 DeepSeek entry.
- DeepSeek now exposes structured USD `remaining`, `paidBalance`, and `grantedBalance` credit fields.
- The cost pass-through still exposes Codex 30-day tokens and estimated cost.
- Wrapper and backup retain executable mode `0700`.
- Backup: `~/.local/bin/codexbar-multi.bak-before-deepseek-balance-20260917`.
