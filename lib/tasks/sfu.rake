require 'yaml'
require 'httparty'
require 'ruby-progressbar'

namespace :sfu do
  desc 'Reset the default Account name and lti_guid. These values need to be reset after a clone from production.'
  task :account_settings, [:stage] => :environment do |t, args|
    stage = args[:stage]
    raise "You must specify a Canvas Capistrano stage (e.g. testing, staging, etc). `rake sfu:account_settings[stage_name]`" if stage.nil?
    sfu = YAML.load_file './config/sfu.yml'
    raise "sfu.yml does not contain a `account_settings` block." if sfu['account_settings'].nil?
    raise "You specified `#{stage}` as the stage, but no such stage is defined in sfu.yml." unless sfu['account_settings'].include? stage

    account_settings = sfu['account_settings'][stage]
    a = Account.default
    puts "Current Account settings:"
    puts "  name: #{a.name}"
    puts "  lti_guid: #{a.lti_guid}"

    puts "Resetting account settings:"
    puts "  name: #{account_settings['name']}"
    puts "  lti_guid: #{account_settings['lti_guid']}"

    Account.transaction do
      a.name = account_settings['name']
      a.lti_guid = account_settings['lti_guid']
      a.save!
    end
  end

  namespace :docker do
    desc 'Add SFU terms from the production environment to the default account'
    task :import_enrollment_terms  => :environment do
      terms_url = 'https://canvas.sfu.ca/sfu/api/v1/terms/'
      response = HTTParty.get(terms_url)
      terms = response.parsed_response
      terms.map! { |t| t['enrollment_term'] }
      terms.delete_if { |t| t['name'] == 'Default Term' }
      account = Account.default
      progress = ProgressBar.create(:title => 'Creating Terms', :total => terms.count)
      terms.each do |t|
        account.enrollment_terms.create({
          :name => t['name'],
          :sis_source_id => t['sis_source_id'],
          :start_at => t['start_at'],
          :end_at => t['end_at'],
          :workflow_state => 'active'
        }) unless EnrollmentTerm.exists?(:sis_source_id => t['sis_source_id'])
        progress.increment
      end
    end
  end
end
