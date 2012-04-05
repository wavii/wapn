guard "bundler" do
  watch("Gemfile")
  watch(/^.+\.gemspec/)
end

guard "spork" do
  watch("Gemfile")
  watch("Gemfile.lock")
  watch(".rspec")              { :rspec }
  watch("spec/spec_helper.rb") { :rspec }
end

guard "rspec", cli: '--drb' do
  watch(%r{^spec/.+_spec\.rb$})
  watch(%r{^lib/wapn/(.+)\.rb$}) { |m| "spec/#{m[1]}_spec.rb" }

  watch(%r{^fixtures/*}) { "spec" }
end
