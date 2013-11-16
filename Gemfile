source (ENV['RUBYGEMS_MIRROR'] or "https://rubygems.org")

gem "builder", "~> 3.0.0"
gem "activesupport", "~> 3.2"
gem "rake"
gem "bcrypt-ruby"
gem "eventmachine", "~> 1.0.3"
gem "fog"
gem "rfc822"
gem "sequel", "~> 3.48"
gem "sinatra", "~> 1.4"
gem "sinatra-contrib"
gem "yajl-ruby"
gem "membrane", "~> 0.0.2"
gem 'errand', '0.7.3'
gem 'librrd', '1.0.3'
gem "httpclient"
gem "steno"
gem "cloudfront-signer"
gem "vcap-concurrency", :git => "https://github.com/cloudfoundry/vcap-concurrency.git", :ref => "2a5b0179"
gem "cf-uaa-lib", "~> 2.0.0", :git => "https://github.com/aocole/cf-uaa-lib.git", :ref => "3026895da933a7b1102735db96568c007b4c9148"
gem "stager-client", "~> 0.0.02", :git => "https://github.com/cloudfoundry/stager-client.git", :ref => "04c2aee9"
gem "cf-message-bus", :git => "https://github.com/ActiveState/cf-message-bus.git"
gem 'vcap_common', :path => '../common'
gem "allowy"
gem "delayed_job_active_record", "~> 4.0"
gem "loggregator_emitter", "~> 0.0.11.pre"
gem "loggregator_messages", "~> 0.0.4.pre"

# These are outside the test group in order to run rake tasks
gem "rspec"
gem "ci_reporter"

group :db do
  gem "mysql2"
  gem "pg"
  gem "sqlite3"
end

group :development do
  gem "debugger"
  gem "pry"
end

group :test do
  gem "simplecov"
  gem "simplecov-rcov"
  gem "machinist", "~> 1.0.6"
  gem "webmock"
  gem "guard-rspec"
  gem "timecop"
  gem "rack-test"
  gem "parallel_tests"
  gem "fakefs", :require => "fakefs/safe"
end

gem "steno-codec-text", :path => "../steno-codec-text"
if ENV["KATO_DEV"] and File.directory? '../kato'
  gem 'stackato-kato', :path => '../kato'
else
  gem 'stackato-kato', '~> 3.0.0'
end
gem 'redis', '~> 3.0.4'

