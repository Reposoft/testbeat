Gem::Specification.new do |s|
  s.name        = 'testbeat'
  s.version     = '0.5.1'
  s.date        = '2015-10-14'
  s.summary     = 'REST acceptance testing framework'
  s.description = 'Rspec spec_helper and Vagrant integration for HTTP level testing, on a box from the outside'
  s.authors     = ['Staffan Olsson']
  s.email       = 'solsson@gmail.com'
  s.files       = [
    'lib/testbeat.rb',
    'lib/rspec/spec_helper.rb',
    'lib/vagrant/noderunner.rb',
    'lib/vagrant/cookbook_decompiler.rb'
  ]
  s.homepage    = 'https://github.com/Reposoft/testbeat'
  s.license     = 'MIT'

  s.required_ruby_version = '~> 2.0'

  s.add_development_dependency "rspec", "~> 3.3"
  s.add_development_dependency "hashie"

  # only used during development
  s.add_development_dependency "awesome_print"
end
