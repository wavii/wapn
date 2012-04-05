require "rubygems"
require "spork"
require "spork/ext/ruby-debug"

Spork.prefork do
  require "rspec"

  # common dependencies that won't change
  require "json"
  require "logger"
  require "openssl"
  require "socket"

  RSpec.configure do |config|
    config.treat_symbols_as_metadata_keys_with_true_values = true
  end

  # Pathing helpers
  ROOT_PATH = File.expand_path("../..", __FILE__)
  FIXTURES  = File.join(ROOT_PATH, "fixtures")
end

Spork.each_run do
  # The rspec test runner executes the specs in a separate process; plus it's nice to have this
  # generic flag for cases where you want coverage running with guard.
  if ENV["COVERAGE"]
    require "simplecov" # This executes .simplecov
  end
end
