require 'yaml'
require 'httparty'

def sfu_config
  YAML.load_file './config/sfu.yml'
end


namespace :sfu do
  desc 'Reset the default Account name and lti_guid. These values need to be reset after a clone from production.'
  task :account_settings, [:stage] => :environment do |t, args|
    stage = args[:stage]
    raise "You must specify a Canvas Capistrano stage (e.g. testing, staging, etc). `rake sfu:account_settings[stage_name]`" if stage.nil?
    sfu = sfu_config
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
      puts "Creating terms based on #{terms_url}"
      
      response = HTTParty.get(terms_url)
      terms = response.parsed_response
      terms.map! { |t| t['enrollment_term'] }
      terms.delete_if { |t| t['name'] == 'Default Term' }
      account = Account.default

      terms.each do |t|
        exists = EnrollmentTerm.where(:sis_source_id => t['sis_source_id']).exists?
        if exists
          puts "Term #{t['name']} (#{t['sis_source_id']}) already exists; skipping"
        else
          account.enrollment_terms.create({
            :name => t['name'],
            :sis_source_id => t['sis_source_id'],
            :start_at => t['start_at'],
            :end_at => t['end_at'],
            :workflow_state => 'active'
          })
          puts "Created term #{t['name']} (#{t['sis_source_id']})"
        end
      end
    end

    desc 'Add account authorization config for SFU CAS and make it the default'
    task :cas_setup => :environment do
      puts 'Setting up SFU CAS as the default authentication provider'
      account = Account.default
      raise 'CAS is already configured!' if account.authentication_providers.active.where(auth_type: 'cas').exists?
      cas_hash = { 
        'auth_type' => 'cas',
        'auth_base' => 'https://cas.sfu.ca/cas/',
        'jit_provisioning' => false
      }
      account_config = account.authentication_providers.build(cas_hash)
      account_config.save!
      account_config.insert_at(1)
      puts 'Done!'
    end

    desc 'Disable the terms of service prompt'
    task :disable_tos => :environment do
      puts 'Disabling the Canvas terms of service prompt'
      puts 'Done!' if Setting.set('terms_required', 'false')
    end
  end
end
