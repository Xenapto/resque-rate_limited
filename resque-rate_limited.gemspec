# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'resque-rate_limited/version'

Gem::Specification.new do |spec|
  spec.name          = 'resque-rate_limited'
  spec.version       = RateLimited::VERSION
  spec.authors       = ['Greg Dowling']
  spec.email         = ['mail@greddowling.com']
  spec.summary     = 'A Resque plugin to help manage jobs that use rate limited apis, pausing when you hit the limits and restarting later.'
  spec.description = 'A Resque plugin which allows you to create dedicated queues for jobs that use rate limited apis.
These queues will pause when one of the jobs hits a rate limit, and unpause after a suitable time period.
The rate_limited can be used directly, and just requires catching the rate limit exception and pausing the
queue. There are also additional queues provided that already include the pause/rety logic for twitter, angelist
and evernote; these allow you to support rate limited apis with minimal changes.'

  spec.homepage      = 'http://github.com/Xenapto/resque-rate_limited'
  spec.license       = 'MIT'

  spec.files = `git ls-files`.split($INPUT_RECORD_SEPARATOR).reject { |f| f =~ %r{^spec/} }
  spec.executables = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files = spec.files.grep(%r{^(test|spec|features|coverage|script)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'resque', '~> 1.9', '>= 1.9.10'
  spec.add_dependency 'redis-mutex', '~> 4.0', '>= 4.0.0'
  spec.add_dependency 'angellist_api', '~> 1.0', '>= 1.0.7'
  spec.add_dependency 'evernote-thrift', '~> 1.25', '>= 1.25.1'
  spec.add_dependency 'twitter', '~> 5.11', '>= 5.11.0'
end
