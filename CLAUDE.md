# Aranet4 Logger — repo instructions

Native Swift macOS menu bar app that continuously logs two Aranet4 sensors into SQLite.
See `README.md` for architecture and build details.

## Working in this repo

- **Always commit and push any changes.** After making edits in this repo, commit them
  (directly to the current branch) and `git push` without waiting to be asked. Use clear,
  descriptive commit messages.
- Build with `./build.sh` (it regenerates the Xcode project from `project.yml` and unsets the
  conda/pixi compiler env vars that otherwise break Xcode's linker).
- The Xcode project (`Aranet4Logger.xcodeproj`) is generated from `project.yml` and is
  gitignored — edit `project.yml`, not the project file.

## roborev reviews

Every commit in this repo is automatically reviewed in the background by
[roborev](https://www.roborev.io/index.md) (a post-commit hook that runs Codex). After
committing, check for findings and address open reviews before finishing:

- `roborev list --open` lists open reviews on the current branch; `roborev show <job_id>`
  shows the full review, and `roborev wait` blocks until a pending review completes.
- The reviews use a weaker model, so judge each finding yourself. If a review is invalid,
  close it with `roborev close <job_id>`. Reviews may also duplicate the Codex reviews
  posted on GitHub PRs (both use Codex) — close findings already handled there.
- If the fix is simple, run `roborev fix <job_id>` — it applies the fix with Codex (which
  has cheaper usage limits) and closes the job when done.
- If the fix is too complicated for Codex, or it's something you were going to do anyway,
  fix it yourself, then `roborev close <job_id>`.
