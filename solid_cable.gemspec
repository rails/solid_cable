# frozen_string_literal: true

require_relative "lib/solid_cable/version"

Gem::Specification.new do |spec|
  spec.name        = "solid_cable"
  spec.version     = SolidCable::VERSION
  spec.authors     = [ "Nick Pezza" ]
  spec.email       = [ "pezza@hey.com" ]
  spec.homepage    = "http://github.com/npezza93/solid_cable"
  spec.summary     = "Database-backed Action Cable backend."
  spec.description = "Database-backed Action Cable backend."
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "http://github.com/rails/solid_cable"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  rails_version = ">= 7.2"
  spec.required_ruby_version = ">= 3.1.0"
  spec.add_dependency "activerecord", rails_version
  spec.add_dependency "activejob", rails_version
  spec.add_dependency "actioncable", rails_version
  spec.add_dependency "railties", rails_version
end
