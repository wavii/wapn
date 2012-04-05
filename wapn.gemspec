# -*- encoding: utf-8 -*-
require File.expand_path("../lib/wapn/version", __FILE__)

Gem::Specification.new do |gem|
  gem.name        =  "wapn"
  gem.description =  "A robust abstraction for the Apple Push Notification service"
  gem.summary     =  "A robust abstraction for the Apple Push Notification service"
  gem.authors     = ["Wavii, Inc."]
  gem.email       = ["info@wavii.com"]
  gem.homepage    =  "http://wavii.com/"

  gem.version  = WAPN::VERSION
  gem.platform = Gem::Platform::RUBY

  gem.files      = `git ls-files`.split("\n")
  gem.test_files = `git ls-files -- {spec}/*`.split("\n")

  gem.require_paths = ["lib"]
end
