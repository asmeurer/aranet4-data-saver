# Aranet4 Logger — repo instructions

Native Swift macOS menu bar app that continuously logs two Aranet4 sensors into SQLite.
See `README.md` for architecture and build details.

## Working in this repo

- **Always commit any changes.** After making edits in this repo, commit them (directly to
  the current branch) without waiting to be asked. Use clear, descriptive commit messages.
- Build with `./build.sh` (it regenerates the Xcode project from `project.yml` and unsets the
  conda/pixi compiler env vars that otherwise break Xcode's linker).
- The Xcode project (`Aranet4Logger.xcodeproj`) is generated from `project.yml` and is
  gitignored — edit `project.yml`, not the project file.
