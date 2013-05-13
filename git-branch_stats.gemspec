# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'git-branch_stats/version'

Gem::Specification.new do |gem|
  gem.name          = "git-branch_stats"
  gem.version       = Git::BranchStats::VERSION
  gem.authors       = ["François-Pierre Bouchard"]
  gem.email         = ["fpbouchard@petalmd.com"]
  gem.description   = %q{Analyzes commits and diffs that are only present on the given branch}
  gem.summary       = %q{Git branch statistics}
  gem.homepage      = ""

  gem.add_dependency 'github-linguist'

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]
end
