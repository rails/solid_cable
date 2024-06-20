# frozen_string_literal: true

require_relative "lib/solid_cable/version"

Gem::Specification.new do |spec|
  spec.name        = "solid_cable"
  spec.version     = SolidCable::VERSION
  spec.authors     = ["Nick Pezza"]
  spec.email       = ["pezza@hey.com"]
  spec.homepage    = "http://github.com/npezza93/solid_cable"
  spec.summary     = "Database-backed Action Cable backend."
  spec.description = "Database-backed Action Cable backend."
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "http://github.com/npezza93/solid_cable"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", "< 9"
end
