# Configure Simplecov and Coveralls
unless ENV['NO_SIMPLECOV']
  require 'simplecov'
  require 'coveralls'

  SimpleCov.start { add_filter '/spec/' }
  Coveralls.wear! if ENV['COVERALLS_REPO_TOKEN']
end

require 'resque/rate_limited'

RSpec.configure do |_config|
  RedisClassy.redis = Redis.new(db: 15) # Use database 15 for testing so we don't accidentally step on your real data.
  abort 'Redis database 15 not empty! If you are sure, run "rake flushdb" beforehand.' unless RedisClassy.keys.empty?
end
