# WorktreeManager

A Ruby gem for managing Git worktrees with ease. WorktreeManager provides a simple and intuitive interface for creating, managing, and removing Git worktrees with built-in hook support.

## Features

- **Easy worktree management**: Create, list, and remove Git worktrees
- **Branch operations**: Create new branches or checkout existing ones
- **Hook system**: Execute custom scripts before/after worktree operations
- **Conflict detection**: Automatic validation to prevent path and branch conflicts
- **CLI interface**: Simple command-line tool for quick operations
- **Ruby API**: Programmatic access for integration with other tools
- **Configuration initialization**: Easy setup with `wm init` command
- **Branch reset**: Reset worktree branches to origin/main with `wm reset`
- **Help support**: All commands support `--help` flag for usage information

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'worktree_manager'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install worktree_manager
```

## Usage

### Command Line Interface

WorktreeManager provides a CLI tool called `wm` for managing worktrees:

```bash
# Initialize configuration file
wm init

# List all worktrees
wm list

# Create a new worktree using just a name (uses worktrees_dir)
wm add feature-branch

# Create a worktree with a relative path
wm add ../feature-branch

# Create a worktree with an absolute path
wm add /path/to/feature-branch

# Create a worktree with an existing branch
wm add feature-branch existing-branch

# Create a worktree with a new branch
wm add feature-branch -b new-feature-branch

# Remove a worktree using just a name
wm remove feature-branch

# Remove a worktree with a path
wm remove ../feature-branch

# Force operations (bypass safety checks)
wm add existing-dir -f
wm remove worktree-with-changes -f

# Track remote branches
wm add pr-154 -t origin/pr-154        # Create local pr-154 tracking origin/pr-154
wm add pr-154 origin/pr-154           # Auto-detect remote branch
wm add hotfix -t upstream/hotfix-123  # Track from different remote

# Reset worktree branch to origin/main (must be run from worktree)
wm reset                              # Reset current branch to origin/main
wm reset -f                           # Force reset (discard uncommitted changes)

# Get help for any command
wm --help                             # Show all commands
wm add --help                         # Show help for add command
wm remove -h                          # Short help flag also works
```

#### Working with Remote Branches

WorktreeManager makes it easy to work with remote branches:

```bash
# Method 1: Using --track (-t) option
wm add pr-154 -t origin/pr-154
# This will:
# 1. Fetch origin/pr-154
# 2. Create a new local branch 'pr-154' tracking 'origin/pr-154'
# 3. Create worktree at '../worktrees/pr-154' (or configured location)

# Method 2: Auto-detection (when branch name contains '/')
wm add pr-154 origin/pr-154
# Automatically detects that origin/pr-154 is a remote branch

# Method 3: Different local and remote names
wm add my-fix -t origin/pr-154
# Creates local branch 'my-fix' tracking 'origin/pr-154'

# Working with different remotes
wm add upstream-fix -t upstream/fix-123
wm add fork-feature -t fork/new-feature
```

Example workflow for Pull Request review:

```bash
# Review PR #154
wm add pr-154 -t origin/pr-154
cd ../worktrees/pr-154
# Make changes, test, etc.

# When done, remove the worktree
cd ../main-repo
wm remove pr-154
```

### Ruby API

```ruby
require 'worktree_manager'

# Create a manager instance
manager = WorktreeManager.new

# List existing worktrees
worktrees = manager.list
worktrees.each do |worktree|
  puts "Path: #{worktree.path}"
  puts "Branch: #{worktree.branch}"
  puts "Detached: #{worktree.detached?}"
end

# Add a new worktree
worktree = manager.add("../feature-branch", "feature-branch")

# Add a worktree with a new branch
worktree = manager.add_with_new_branch("../new-feature", "new-feature-branch")

# Remove a worktree
manager.remove("../feature-branch")

# Clean up removed worktrees
manager.prune
```

## Hook System

WorktreeManager supports hooks that execute before and after worktree operations:

### Hook Types

- `pre_add`: Execute before creating a worktree
- `post_add`: Execute after creating a worktree
- `pre_remove`: Execute before removing a worktree
- `post_remove`: Execute after removing a worktree

### Configuration

Create a `.worktree.yml` file in your repository root to configure WorktreeManager:

```yaml
# Base directory for worktrees (default: "../")
# When you run 'wm add feature', it creates worktree at '../feature' by default
# With worktrees_dir set to "../worktrees", it creates at '../worktrees/feature'
worktrees_dir: "../worktrees"

# Main branch name for reset command (default: "main")
# Used by 'wm reset' to determine which branch to reset to
main_branch_name: "main"  # or "master" for older repositories

# Hook configuration (see below)
hooks:
  # ...
```

#### Worktrees Directory

The `worktrees_dir` option allows you to specify a default location for your worktrees:

- **Default value**: `../` (parent directory of your main repository)
- **Purpose**: Organize all worktrees in a specific directory
- **Usage**: When you use `wm add <name>` with just a name (no path), it creates the worktree in `<worktrees_dir>/<name>`

Example configurations:

```yaml
# Keep worktrees in a sibling directory
worktrees_dir: "../worktrees"

# Keep worktrees in a subdirectory of the parent
worktrees_dir: "../../git-worktrees"

# Use absolute path
worktrees_dir: "/home/user/projects/worktrees"
```

### Hook Configuration

Hooks allow you to execute custom scripts during worktree operations:

```yaml
hooks:
  # Execute before creating a worktree (runs in main repository)
  pre_add:
    commands:
      - "echo 'Creating worktree at: $WORKTREE_PATH'"
      - "echo 'Branch: $WORKTREE_BRANCH'"
    stop_on_error: true  # Stop if any command fails (default: true)

  # Execute after creating a worktree (runs in new worktree directory)
  post_add:
    commands:
      - "bundle install"
      - "echo 'Setup complete: $WORKTREE_BRANCH'"
    # Override default working directory if needed
    # pwd: "$WORKTREE_MAIN"  # Run in main repository instead

  # Execute before removing a worktree (runs in worktree directory)
  pre_remove:
    commands:
      - "git add -A"
      - "git stash push -m 'Auto stash before removal'"
    stop_on_error: false  # Continue even if commands fail

  # Execute after removing a worktree (runs in main repository)
  post_remove:
    commands:
      - "echo 'Cleanup complete: $WORKTREE_PATH'"
```

### Available Environment Variables

- `$WORKTREE_PATH`: Path where the worktree will be created/removed (relative path)
- `$WORKTREE_ABSOLUTE_PATH`: Absolute path to the worktree
- `$WORKTREE_BRANCH`: Branch name (if specified)
- `$WORKTREE_MAIN`: Main repository path
- `$WORKTREE_MANAGER_ROOT`: Main repository path (legacy, same as `$WORKTREE_MAIN`)
- `$WORKTREE_FORCE`: Whether force option is enabled ("true" or "")
- `$WORKTREE_SUCCESS`: Whether the operation succeeded (post hooks only, "true" or "false")

### Practical Hook Examples

```yaml
hooks:
  # Automatic development environment setup
  post_add:
    commands:
      - "bundle install"              # Install dependencies
      - "yarn install"                # Install JS dependencies
      - "cp .env.example .env"        # Copy environment variables
      - "code ."                      # Open in VS Code
    # Default pwd is the new worktree directory

  # Automatic backup of work
  pre_remove:
    commands:
      - "git add -A"
      - "git stash push -m 'Auto backup: $WORKTREE_BRANCH'"
    stop_on_error: false  # Continue even if nothing to stash

  # Notification system (run in main repository)
  post_add:
    commands:
      - "osascript -e 'display notification \"Workspace ready: $WORKTREE_BRANCH\" with title \"WorktreeManager\"'"
    pwd: "$WORKTREE_MAIN"  # Run notification from main repo

  # CI/CD integration
  post_add:
    commands:
      - "gh pr create --draft --title 'WIP: $WORKTREE_BRANCH' --body 'Auto-created by worktree manager'"
    pwd: "$WORKTREE_ABSOLUTE_PATH"
```

## CLI Command Reference

All commands support help flags (`--help`, `-h`, `-?`, `--usage`) to display usage information.

### `wm version`
Display the current installed version.

### `wm init`
Initialize a `.worktree.yml` configuration file in your repository.

**Options**:
- `-f, --force`: Overwrite existing configuration file

**Requirements**: Must be run from the main Git repository

**Examples**:
```bash
wm init                                  # Create .worktree.yml from example
wm init --force                          # Overwrite existing .worktree.yml
```

### `wm list`
List all worktrees in the current Git repository. Can be run from either the main repository or any worktree.

### `wm add PATH [BRANCH]`
Create a new worktree.

**Arguments**:
- `PATH`: Path where the worktree will be created
- `BRANCH`: Branch to use (optional)

**Options**:
- `-b, --branch BRANCH`: Create a new branch for the worktree
- `-f, --force`: Force creation even if directory exists
- `-v, --verbose`: Enable verbose output for debugging

**Examples**:
```bash
wm add ../feature-api feature/api        # Use existing branch
wm add ../new-feature -b feature/new     # Create new branch
wm add ../override --force               # Force creation
```

### `wm remove PATH`
Remove an existing worktree.

**Arguments**:
- `PATH`: Path of the worktree to remove

**Options**:
- `-f, --force`: Force removal even if worktree has changes
- `-v, --verbose`: Enable verbose output for debugging

**Examples**:
```bash
wm remove ../feature-api                 # Normal removal
wm remove ../old-feature --force         # Force removal
```

### `wm reset`
Reset the current worktree branch to origin/main (or configured main branch).

**Options**:
- `-f, --force`: Force reset even if there are uncommitted changes

**Requirements**: Must be run from a worktree (not from the main repository)

**Configuration**: The target branch can be configured via `main_branch_name` in `.worktree.yml`

**Examples**:
```bash
wm reset                                 # Reset to origin/main
wm reset --force                         # Force reset, discarding changes
```

## Requirements

- Ruby 3.0.0 or higher
- Git 2.5.0 or higher (for worktree support)

## Development

After checking out the repo, run:

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Build gem
gem build worktree_manager.gemspec

# Install locally
gem install worktree_manager-*.gem
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/nacyot/worktree_manager.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request