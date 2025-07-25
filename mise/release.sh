#!/bin/bash

set -e

# Set default version increment if not provided
VERSION_INCREMENT="${1:-0.0.1}"

# Validate version increment format
if [[ ! "$VERSION_INCREMENT" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Version increment must be in format X.Y.Z (e.g., 0.0.1)"
    exit 1
fi

# Change to the project root directory
cd "$(dirname "$0")/.."

# Check if git repository is clean
if [ -n "$(git status --porcelain)" ]; then
    echo "Error: Git repository is not clean. Please commit or stash your changes."
    git status --short
    exit 1
fi

# Clean up old gem files
echo "Cleaning up old gem files..."
rm -f worktree_manager-*.gem

# Read current version from .version file
if [ ! -f .version ]; then
    echo "Error: .version file not found"
    exit 1
fi

CURRENT_VERSION=$(cat .version)
echo "Current version: $CURRENT_VERSION"

# Parse version components
IFS='.' read -ra CURRENT_PARTS <<< "$CURRENT_VERSION"
IFS='.' read -ra INCREMENT_PARTS <<< "$VERSION_INCREMENT"

# Validate current version format
if [ ${#CURRENT_PARTS[@]} -ne 3 ]; then
    echo "Error: Current version must be in format X.Y.Z"
    exit 1
fi

# Calculate new version
MAJOR=$((CURRENT_PARTS[0] + INCREMENT_PARTS[0]))
MINOR=$((CURRENT_PARTS[1] + INCREMENT_PARTS[1]))
PATCH=$((CURRENT_PARTS[2] + INCREMENT_PARTS[2]))

# Handle carry-over
if [ $PATCH -ge 10 ]; then
    MINOR=$((MINOR + PATCH / 10))
    PATCH=$((PATCH % 10))
fi

if [ $MINOR -ge 10 ]; then
    MAJOR=$((MAJOR + MINOR / 10))
    MINOR=$((MINOR % 10))
fi

NEW_VERSION="$MAJOR.$MINOR.$PATCH"
echo "New version: $NEW_VERSION"

# Update .version file FIRST
echo "$NEW_VERSION" > .version

# Update Gemfile.lock with new version
echo "Updating Gemfile.lock..."
bundle install

# Build the gem with new version
echo "Building gem with version $NEW_VERSION..."
if gem build worktree_manager.gemspec; then
    echo "Gem built successfully: worktree_manager-$NEW_VERSION.gem"
    
    # Git operations
    echo "Committing version bump..."
    git add .version Gemfile.lock
    git commit -m "Bump version to $NEW_VERSION"
    
    echo "Creating git tag..."
    git tag -a "v$NEW_VERSION" -m "Release version $NEW_VERSION"
    
    echo "Pushing to remote..."
    git push origin
    git push origin "v$NEW_VERSION"
    
    # Ask about publishing to RubyGems.org
    echo ""
    read -p "Publish to RubyGems.org? (y/N): " publish_confirm
    
    if [[ "$publish_confirm" =~ ^[Yy]$ ]]; then
        echo "Publishing to RubyGems.org..."
        if gem push worktree_manager-$NEW_VERSION.gem; then
            echo "✓ Gem published successfully to RubyGems.org"
            echo ""
            echo "View your gem at: https://rubygems.org/gems/worktree_manager"
        else
            echo "Error: RubyGems.org push failed"
            echo "You can manually publish with:"
            echo "  gem push worktree_manager-$NEW_VERSION.gem"
            exit 1
        fi
    else
        echo "Skipping RubyGems.org publishing."
        echo "You can manually publish later with:"
        echo "  gem push worktree_manager-$NEW_VERSION.gem"
    fi
    
    echo "Release complete!"
    echo "Version $NEW_VERSION has been released."
else
    echo "Error: Gem build failed with new version"
    # Revert version change
    echo "$CURRENT_VERSION" > .version
    bundle install  # Revert Gemfile.lock
    exit 1
fi
