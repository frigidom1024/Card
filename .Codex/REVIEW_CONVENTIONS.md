# Review Conventions

- Keep commits narrowly scoped; do not change files, behavior, or assets outside the stated task.
- Preserve Godot scene node names, unique node paths, layout, resources, and gameplay flow unless the task explicitly requires changes.
- Prefer minimal, reviewable diffs and validate changed user-facing strings with the relevant project checks.
- Use descriptive names, explicit error handling, and focused interfaces in Go code; keep domain logic independent from infrastructure concerns.
- Follow `internal/pkg/logger/CONVENTIONS.md` whenever it is present; do not add logging that exposes secrets or duplicates error reporting.
