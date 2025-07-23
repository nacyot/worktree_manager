# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2025-07-23

### Added
- GitHub Actions CI/CD pipeline with Ruby 3.1-3.4 test matrix
- Windows CI testing support for all Ruby versions
- MIT LICENSE file
- RubyGems metadata including MFA requirement
- This CHANGELOG file

### Changed
- Minimum Ruby version requirement from 3.0 to 3.1
- Updated gemspec to use `git ls-files` for better file inclusion
- Fixed `wm reset` to always perform hard reset, preventing dirty working directory issues
- Release script now updates Gemfile.lock to prevent version mismatch in CI

### Fixed
- CI failures caused by version mismatch between .version and Gemfile.lock
- Reset command leaving uncommitted changes in working directory

## [0.1.8] - 2025-07-21

### Added
- `wm init` command to initialize worktree configuration file
- `wm reset` command to reset worktree branch to origin/main
- Support for `--help` flag on all commands (e.g., `wm add --help`)

### Changed
- Refactored configuration example file from `.worktree.yml.sample` to `.worktree.yml.example`

## [0.1.7] - 2025-07-21

### Added
- Interactive force removal prompt for worktrees with uncommitted changes

## [0.1.6] - 2025-07-21

### Added
- `--no-hooks` option to skip hook execution during worktree operations
- Comprehensive test coverage for main repository protection

## Previous versions

Earlier versions were released to GitHub Packages only. This is the first public release to RubyGems.org.