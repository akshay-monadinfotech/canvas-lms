require 'yaml'
require 'httparty'

def sfu_config
  YAML.load_file './config/sfu.yml'
end

CSV_USERS_HEADER = "user_id,login_id,first_name,last_name,short_name,email,status"

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

    desc 'Create SFU user'
    task :create_sfu_user, [:username] => :environment do |task, args|

      username = args.username
      if (username.nil?)
        require 'highline/import'
        while true do
          username = ask("SFU Computing ID of the user to create: ") { |q| q.echo = true }
          break if !username.empty? && username.length <= 8
        end
      end
      
      # check if user already exists in Canvas
      throw "User #{username} already exists in Canvas" if Pseudonym.active.where(unique_id: username).exists?

      sfu = sfu_config
      throw "config/sfu.yml does not contain a `sfu_rest_token`" if sfu['sfu_rest_token'].nil?

      response = HTTParty.get("https://rest.its.sfu.ca/cgi-bin/WebObjects/AOBRestServer.woa/rest/datastore2/global/accountInfo.js?username=#{username}&art=#{sfu['sfu_rest_token']}")
      throw "No such SFU user: #{username}" if response.code == 404
      user_bio = response.parsed_response

      # ok now we make the CSV datazzzzz
      csv_data = "\"#{user_bio['sfuid']}\",\"#{user_bio['username']}\",\"#{user_bio['firstnames']}\",\"#{user_bio['lastname']}\",\"#{user_bio['commonname']}\",\"#{user_bio['username']}@sfu.ca\",\"active\""

      # make ze temp file
      tmp = Tempfile.new(['user', '.csv'])
      tmp.write("#{CSV_USERS_HEADER}\n#{csv_data}")
      tmp.close

      # arrrgh attachment.rb
      def tmp.original_filename; File.basename(self); end
      
      # create batch
      batch = SisBatch.create_with_attachment(Account.default, 'instructure_csv', tmp, User.find(1))
      batch.process_without_send_later

      # check that the user got created...
      puts "Created user #{username}" if Pseudonym.active.where(unique_id: username).exists? # else throw "Something went wrong creating user #{username}"
    end

    desc 'Create SFU users based on membership in a maillist'
    task :create_sfu_users_from_maillist, [:maillist] => :environment do |task, args|
      maillist = args.maillist
      force = maillist.nil? ? false : true
      if (maillist.nil?)
        require 'highline/import'
        while true do
          maillist = ask("SFU Maillist contatining users to create: ") { |q| q.echo = true }
          break if !maillist.empty?
        end
      end

      # check if maillist is valid and has users
      sfu = sfu_config
      throw "config/sfu.yml does not contain a `sfu_rest_token`" if sfu['sfu_rest_token'].nil?

      mlresponse = HTTParty.get("https://rest.its.sfu.ca/cgi-bin/WebObjects/AOBRestServer.woa/rest/maillist/members.js?listname=#{maillist}&art=#{sfu['sfu_rest_token']}")
      members = mlresponse.parsed_response
      throw "Maillist '#{maillist}' is either invalid or has no members. Please check your list name and try again." if members.empty?

      # filter out non-SFU members (e.g. any member containing `@`)
      members.select! { |e| !e.include? '@' }

      throw "Maillist '#{maillist}' contains no SFU members. Please try again with a maillist containing SFU members." if members.empty?

      # check if members already exist in canvas
      existing = members.map do |member|
        member if Pseudonym.active.where(unique_id: member).exists?
      end
      existing.select! { |e| !e.nil? }

      to_create = members - existing
      throw "All members of maillist '#{maillist}' already exist in Canvas" if to_create.empty?

      prompt = "The following users will be created in Canvas: #{to_create.join(', ')}"
      prompt += "\nThe following users already exist in Cavnas: #{existing.join(', ')}" if !existing.empty? 
      puts prompt
      if !force
        while true do
          continue = agree("Continue? ") { |q| q.default = 'y' }
          puts continue
          throw "OK, bye!" if !continue
          break if continue
        end
      end

      # for each member of list, get user bio and add to csv
      puts "Getting user information for maillist members..."
      csv_data = to_create.map do |username|
        response = HTTParty.get("https://rest.its.sfu.ca/cgi-bin/WebObjects/AOBRestServer.woa/rest/datastore2/global/accountInfo.js?username=#{username}&art=#{sfu['sfu_rest_token']}")
        throw "No such SFU user: #{username}" if response.code == 404
        user_bio = response.parsed_response
        "\"#{user_bio['sfuid']}\",\"#{user_bio['username']}\",\"#{user_bio['firstnames']}\",\"#{user_bio['lastname']}\",\"#{user_bio['commonname']}\",\"#{user_bio['username']}@sfu.ca\",\"active\""
      end

      puts "Building CSV..."
      csv_data = csv_data.join("\n"
      )
      # make ze temp file
      tmp = Tempfile.new(['user', '.csv'])
      tmp.write("#{CSV_USERS_HEADER}\n#{csv_data}")
      tmp.close

      # arrrgh attachment.rb
      def tmp.original_filename; File.basename(self); end
      
      puts "Submitting SIS Import..."
      # create batch
      batch = SisBatch.create_with_attachment(Account.default, 'instructure_csv', tmp, User.find(1))
      batch.process_without_send_later

      to_create.each do |user|
        if Pseudonym.active.where(unique_id: user).exists?
          puts "Created user #{user}"
        else
          puts "WARNING: User #{user} not created!"
        end
      end
    end

    desc 'Delete all users except the canvas@docker admin'
    task :delete_all_users, [:force] => :environment do |task, args|
      args.with_defaults(force: false)
      if (!args.force)
        require 'highline/import'
        continue = agree("Are you sure you want to delete all users except user with ID 1 from this Canvas installation? [yes/no] ")
        if !continue
          puts "OK, bye!"
          next
        end
      end
      puts "Deleting all users except user with ID 1"
      User.active.where.not(id: 1).destroy_all
    end
  end
end

