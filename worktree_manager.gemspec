require_relative 'lib/worktree_manager/version'

Gem::Specification.new do |spec|
  spec.name          = 'worktree_manager'
  spec.version       = WorktreeManager::VERSION
  spec.authors       = ['nacyot']
  spec.email         = ['propellerheaven@gmail.com']

  spec.summary       = 'Git worktree management tool'
  spec.description   = 'A Ruby gem for managing git worktrees with ease'
  spec.homepage      = 'https://github.com/nacyot/worktree_manager'
  spec.license       = 'MIT'

  spec.metadata = {
    'source_code_uri' => 'https://github.com/nacyot/worktree_manager',
    'changelog_uri' => 'https://github.com/nacyot/worktree_manager/blob/main/CHANGELOG.md',
    'bug_tracker_uri' => 'https://github.com/nacyot/worktree_manager/issues',
    'rubygems_mfa_required' => 'true'
  }

  spec.files         = Dir.chdir(__dir__) { `git ls-files -z`.split("\x0") }
  spec.bindir        = 'bin'
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 3.1.0'

  spec.add_dependency 'thor', '~> 1.0'
  spec.add_dependency 'tty-prompt', '~> 0.23'

  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
end
