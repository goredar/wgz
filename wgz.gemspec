# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'wgz/version'

Gem::Specification.new do |spec|
  spec.name          = "wgz"
  spec.version       = Wgz::VERSION
  spec.authors       = ["goredar"]
  spec.email         = ["goredar@gmail.com"]

  spec.summary       = %q{wgz - zabbix polling utility}
  spec.description   = %q{wgz is a part of L1 suite. It's a console utility that prints actual zabbix triggers and could pipe them to another app.}
  spec.homepage      = "https://goredar.it"

  # Prevent pushing this gem to RubyGems.org by setting 'allowed_push_host', or
  # delete this section to allow pushing this gem to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "goredar", "~> 0"
  spec.add_runtime_dependency "oj", "~> 2"
  spec.add_runtime_dependency "curb", "~> 0"
  spec.add_runtime_dependency "terminal-table", "~> 1"
  spec.add_runtime_dependency "colorize", "~> 0"
  spec.add_runtime_dependency "psych", "= 2.0.8"
  spec.add_runtime_dependency "bundler", "~> 1"

  spec.add_development_dependency "test-unit", "~> 3"
  spec.add_development_dependency "rake", "~> 10"
end
