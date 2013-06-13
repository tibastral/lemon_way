require "bundler/gem_tasks"
require 'rspec/core/rake_task'
require 'yard'

RSpec::Core::RakeTask.new('spec')

# If you want to make this the default task
task :default => :spec


YARD::Rake::YardocTask.new do |t|
  t.files   = ['lib/**/*.rb', "README", "LICENCE"]   # optional
  #t.options = ['--any', '--extra', '--opts'] # optional
end