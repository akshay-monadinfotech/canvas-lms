require 'capistrano-scm-copy'
set :scm, :copy
set :copy_local_tar, "/usr/local/bin/gtar" if `uname` =~ /Darwin/

set :stage, :testing_buildbox
set :app_node_prefix, "canvas-at"
set :canvas_url, 'https://canvas-test.sfu.ca'

role :db,  %w{canvas-mt.tier2.sfu.ca}
set :branch, ENV['branch'] || 'sfu-develop'

namespace :deploy do
  before :started, 'canvas:set_app_nodes'
end

set :default_env, {
  'PATH' => '/usr/pgsql-9.1/bin:$PATH'
}

set :shared_brandable_css_base, "/mnt/data/brandable_css/"
set :shared_brandable_css_path, "#{fetch(:shared_brandable_css_base)}#{release_timestamp}"
