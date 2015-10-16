
# Testbeat

`gem install testbeat`

## Use with Rspec

Your `spec_helper.rb` may contain
```
require 'rubygems'
require 'testbeat'
```

Or specs can simply
```
describe "My REST API" do
  require 'testbeat'

  describe "GET /" do
    ...
```

On the assertion side `@response` can be used with for example https://github.com/c42/rspec-http

## rake + vagrant + rspec

There's no clever loading of noderunner yet so callers can replace their old require('lib/noderunner.rb') with:
```
require 'testbeat'; load "vagrant/noderunner.rb"
```
