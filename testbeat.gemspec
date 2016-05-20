Gem::Specification.new do |s|
  s.name        = 'testbeat'
  s.version     = '0.6.0.pr9'
  s.date        = '2016-03-26'
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

  s.add_dependency "rspec", "~> 3.3"
  s.add_dependency "hashie", '~> 0'

  # used during development for debugging rspec contexts, but may not be completely cleaned out
  #s.add_development_dependency "awesome_print", '~> 0'
  s.add_dependency "awesome_print", '~> 0'
end
