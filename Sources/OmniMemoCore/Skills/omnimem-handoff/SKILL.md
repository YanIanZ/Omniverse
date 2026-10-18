---
name: omnimem-handoff
description: Save a concise OmniMemo checkpoint at a milestone or before changing coding agents.
---
Call the project's OmniMemo `memory_checkpoint` with done, next, blocked, tests, and changed_files.
Supply relative existing source paths; omit deleted files from changed_files and describe them in done.
Report tests as observations with their command and result; do not invent verification.
Save decisions separately with `memory_save` and source references when useful.
Do not capture raw chat, credentials, environment files or private keys. Keep project knowledge scoped.
If memory is unavailable, preserve a short local checkpoint explicitly; do not silently report a successful save.
