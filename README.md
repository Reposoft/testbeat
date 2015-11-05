
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

## How to write tests

See spec/unit/spec_helper_spec.rb for examples. Note the optional arguments `form`, `body`, `headers`.

All HTTP verbs in http://ruby-doc.org/stdlib-2.2.3/libdoc/net/http/rdoc/Net/HTTP.html are supported.

## rake + vagrant + rspec

There's no clever loading of noderunner yet so callers can replace their old require('lib/noderunner.rb') with:
```
require 'testbeat'; load "vagrant/noderunner.rb"
```
