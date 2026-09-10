# CI pipeline

`ci.yml` runs on every pull request and on push to `main`. Jobs:

- Create a version number
- Unit tests
- Build, run the smoke test, and pack the tool
- Publish to NuGet.org (push to `main` only, via trusted publishing)
- Create a GitHub release (push to `main` only)
- Cloud code review (pull requests only)
