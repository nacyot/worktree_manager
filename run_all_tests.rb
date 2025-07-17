#!/usr/bin/env ruby

# Script to explicitly run all spec files
spec_files = [
  "spec/worktree_manager_spec.rb",
  "spec/worktree_manager/manager_spec.rb", 
  "spec/worktree_manager/worktree_spec.rb",
  "spec/worktree_manager/cli_spec.rb",
  "spec/worktree_manager/hook_manager_spec.rb",
  "spec/worktree_manager/config_manager_spec.rb",
  "spec/integration/worktree_integration_spec.rb"
]

command = "bundle exec rspec #{spec_files.join(' ')}"
puts "Running: #{command}"
system(command)