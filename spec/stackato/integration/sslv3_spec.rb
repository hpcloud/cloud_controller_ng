# Copyright (c) ActiveState 2014 - ALL RIGHTS RESERVED.
#
# To test:
# In cc_ng
# Remove 'test:' from ~/.bundle/config
# $ bundle install
# $ export DB_CONNECTION="postgres://postgres:`kato config get stackato_rest db/database/password`@localhost:5432"
# make a test database:
# Create the cc_test database
# $ kato config get stackato_rest db/database/password
# $ psql -U postgres -W -h localhost -p 5432
# $ postgres=# create database cc_test;
# ^D
# $ bundle exec rspec spec/stackato/integration/sslv3_spec.rb

require 'spec_helper'

def restart_router
  system('kato restart router')
  while true
    sleep 1.0
    status = `kato status | grep router | cat -A`
    if status['^[[32mnone^[[0m$']
      break
    end
    $stderr.puts("Sleep and retry the router status (#{status})")
  end
end

def set_ssl_if_needed
  status = `kato config get router2g ssl/secure_options`
  if status != 'SSL_OP_NO_SSLv3'
    system("kato config set router2g ssl/secure_options SSL_OP_NO_SSLv3")
    restart_router
  end
end    

def run_openssl(ssl_arg=nil)
  args = "openssl s_client -connect 127.0.0.1:443 #{ssl_arg || ''} 2>&1"
  pipe = IO.popen(args, "r+")
  begin
    pipe.close_write
  rescue
  end
  return pipe.read
end

describe 'Testing ssl and the router' do
  orig_setting = nil
  before(:all) do
    data = JSON.parse(`kato config get router2g ssl --json`)
    orig_setting = data.fetch('secure_options', nil)
  end
  after(:all) do
    if orig_setting
      system("kato config set router2g ssl/secure_options #{orig_setting}")
    else
      system("kato config del router2g ssl/secure_options")
    end
  end

  it 'should connect with no router setting, with or without -ssl3' do
    system("kato config del router2g ssl/secure_options")
    restart_router
    s = run_openssl('') # The control
    expect(s).not_to match(/handshake failure/)
    expect(s).to match(/Secure Renegotiation IS supported/)
    s = run_openssl('-ssl3')
    expect(s).not_to match(/handshake failure/)
    expect(s).to match(/Secure Renegotiation IS supported/)
  end
  it 'should fail to connect with -ssl3' do
    set_ssl_if_needed
    s = run_openssl('-ssl3')
    expect(s).to match(/handshake failure/)
    expect(s).to match(/Secure Renegotiation IS NOT supported/)
  end
  it 'should connect with no -ssl3 and secure_option' do
    set_ssl_if_needed
    s = run_openssl()
    expect(s).not_to match(/handshake failure/)
    expect(s).to match(/Secure Renegotiation IS supported/)
  end
end
