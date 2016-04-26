lock '~> 3.4'

set :application,   'canvas'
set :repo_url,      ENV['repo'] || 'https://github.com/sfu/canvas-lms.git'
set :scm,           'git'
set :branch,        ENV['branch'] || 'sfu-deploy'
set :user,          'canvasuser'
set :deploy_to,     '/var/rails/canvas'
set :stats_server,  'stats.tier2.sfu.ca'
set :rails_env,     'production'
set :linked_dirs,   %w{log tmp/pids public/system}
set :log_level,     ENV['log_level'] || :info
set :pty,           true

set :bundle_path, "vendor/bundle"
set :bundle_without, nil
set :bundle_flags,  ""

set :local_brandable_css_path, lambda { "#{release_path}/public/dist/brandable_css" }

# resets Account.name and Account.lti_guid according to values in sfu.yml
# don't do this on production
set :reset_account_settings, true

set :ssh_options, {
  forward_agent: true,
  keys: [File.join(ENV["HOME"], ".ssh", "id_rsa_canvas")],
  user: 'canvasuser'
}
if (ENV.has_key?('gateway') && ENV['gateway'].downcase == "true")
  require 'net/ssh/proxy/command'
  gateway_user =  ENV['gateway_user'] || ENV['USER']

  set :ssh_options, {
    proxy: Net::SSH::Proxy::Command.new("ssh #{gateway_user}@hatzic.sfu.ca -W %h:%p"),
    forward_agent: true,
    keys: [File.join(ENV["HOME"], ".ssh", "id_rsa_canvas")],
    user: 'canvasuser'
  }
  set :stats_server, "stats.its.sfu.ca"
end

namespace :deploy do

  # before :started,  'canvas:meta_tasks:before_started'
  before :updated,  'canvas:meta_tasks:before_updated'
  after :updated,   'canvas:meta_tasks:after_updated'
  after :published, 'canvas:meta_tasks:after_published'

end
