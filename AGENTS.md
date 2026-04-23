# Agent Ground Rules

These rules apply to AI-assisted development on this project.

## Red-Green-Refactor TDD

- Write or update a failing test before changing production code.
- Run the test to confirm it fails for the right reason (red).
- Make the smallest change to production code that makes the test pass (green).
- Refactor only with a green test suite. Run tests after every refactoring step.
- If a change breaks existing tests, fix the test or the code — never disable tests to get a green build.

## Commits: Small, Topical, Early and Often

- Commit after every red-green-refactor cycle, or after any coherent, reviewable unit of work.
- A commit should do one thing: fix a bug, add a feature, refactor a module, or update tests.
- Do not batch unrelated changes into a single commit.
- Write clear commit messages that explain _why_ the change was made, not just _what_ changed.
- Run `mix test` before committing. Do not commit on a failing test suite.
- Follow the project's changelog convention: add entries to `changelog.d/` rather than editing `CHANGELOG.md`.

## Performance and Database Safety

- Never add an N+1 query. If you see a loop that calls the database, batch it.
- Never materialize large result sets in memory only to return a slice. Move pagination, limits, and counts into SQL.
- Before adding an index, confirm the query is actually hot and that the index matches the filter _and_ sort pattern.
- Before changing a query, run `EXPLAIN` (or explain in tests) and verify the plan.
- Be especially careful with:
  - `Repo.all/1` on unbounded queries
  - Aggregate queries inside hot write paths
  - Per-row lookups inside views and renderers
- When in doubt, benchmark or ask before optimizing.

## General Safety

- Make minimal changes. Solve the stated problem; do not refactor adjacent code unless it is directly required.
- Preserve existing behavior for all code paths not explicitly being changed.
- If a task is large, break it into small steps and confirm each step with tests before moving on.
