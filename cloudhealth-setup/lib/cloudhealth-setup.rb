gem "fog", "1.15.0"
gem "multi_json", "1.7.7"
gem "excon", "0.25.3"
gem "mixlib-cli", "1.3.0"
gem "mechanize", "2.5.1"
gem "highline", "1.6.19"
gem "nokogiri", "1.5.8"
gem "json_pure", "1.8.1"

require "fog"
require "mixlib/cli"
require "multi_json"
require "json/pure"
require "mechanize"
require "excon"
require "highline/import"
require "securerandom"
require "csv"
require "highline/system_extensions"

include HighLine::SystemExtensions

# Ruby 1.8.7 hack for compatability
unless Kernel.respond_to?(:require_relative)
  module Kernel
    def require_relative(path)
      require File.join(File.dirname(caller[0]), path.to_str)
    end
  end
end

require_relative "cht/aws"
require_relative "cht/mechanize"
require_relative "cht/policy"
require_relative "cht/error_handling"
require_relative "cht/output"

class MyCLI
  include Mixlib::CLI

  option :output_file,
    :short => "-o OUTFILE",
    :long => "--output-file OUTFILE",
    :description => "Output CSV"

  option :overwrite_file,
    :long => "--overwrite",
    :boolean => true,
    :description => "Overwrite output file if it exists."

  option :input_file,
    :short => "-i INPUT",
    :long => "--input-file INPUT",
    :description => "INPUT CSV File"

  option :aws_acct_alias,
    :long => "--account-alias ALIAS",
    :description => "Set an AWS Account alias"

  option :aws_user,
    :short => "-u USER",
    :long => "--aws-user USER",
    :description => "AWS Username"

  option :aws_pass,
    :short => "-p PASS",
    :long => "--aws-pass PASS",
    :description => "AWS Password"

  option :aws_key,
    :short => "-k KEY",
    :long => "--aws-key KEY",
    :description => "AWS Key"

  option :aws_secret,
    :short => "-s SECRET",
    :long => "--aws-secret SECRET",
    :description => "AWS Secret"

  option :multi_factor_code,
    :short => "-m CODE",
    :long => "--multi-factor CODE",
    :description => "Multi-Factor Authentication Token / Code"

  option :setup_bucket,
    :short => "-b BUCKET",
    :long => "--setup-billing-bucket BUCKET",
    :description => "Name of billing bucket to create/use."

  option :aws_ro_name,
    :short => "-r READONLY",
    :long => "--aws-ro-name READONLY",
    :default => "cloudhealth",
    :description => "Name of the Read only account to create in AWS"

  option :ro_user_exists,
    :long => "--user-exists",
    :boolean => true,
    :description => "AWS Read-only user exists, Perform other setup anyway (CSV will not be complete)"

  option :verbose,
    :short => "-v",
    :long => "--verbose",
    :description => "Enable verbose output / stack trace errors",
    :boolean => true

  option :help,
    :short => "-h",
    :long => "--help",
    :description => "Help",
    :on => :tail,
    :boolean => true,
    :show_options => true,
    :exit => 0

end


class CsvImport
  def initialize(filename)
    @filename = filename
  end

  def import_file # Make me work!
  end
end

class Setup
  attr_accessor :aws_key, :aws_secret, :aws_user, :aws_pass, :output_file, :input_file, :aws_url, :setup_bucket, :aws_ro_name, :aws_acct_alias, :account_name, :aws_account_id

  def initialize(options)
    manual_input = ensure_options(options) unless defined?(Ocra)
    options.merge!(manual_input)
    @aws_key = options[:aws_key]
    @aws_secret = options[:aws_secret]
    @output_file = options[:output_file]
    @input_file = options[:input_file]
    @aws_user = options[:aws_user]
    @aws_pass = options[:aws_pass]
    @setup_bucket = options[:setup_bucket]
    @aws_ro_name = options[:aws_ro_name]
    @aws_acct_alias = options[:aws_acct_alias]
    @aws_account_id = nil
    @verbose = options[:verbose]
    @overwrite_file = options[:overwrite_file]
    @ro_user_exists = options[:ro_user_exists]
    @mfa = options[:multi_factor_code] || nil
    @created_account = {}
    @iam = iam
    @simple = options[:simple] || false
    @s3 = s3
    @browser = mech_browser
    @mode = ARGV[0]
  end

  def ensure_options(input)
    # If things dont exist in the options that are required, or required in a combination.
    output_opts = {}

    if input[:aws_key].nil?
      output_opts[:aws_key] = ask("Input AWS Key: ") do |q|
        q.responses[:not_valid] = "You must enter a 20 char AWS Access Key ID"
        q.responses[:invalid_type] = "You must enter a 20 char AWS Access Key ID"
        q.validate = lambda {|p| p.length == 20 }
      end
    end

    if input[:aws_secret].nil?
      output_opts[:aws_secret] = ask("Input AWS Secret: ") do |q|
        q.responses[:not_valid] = "You must enter a 40 char AWS Access Secret Key"
        q.responses[:invalid_type] = "You must enter a 40 char AWS Access Secret Key"
        q.validate = lambda {|p| p.length == 40 }
      end
    end

    if input[:aws_user].nil?
      output_opts[:aws_user] = ask("Input AWS Email/Username: ") do |q|
        q.responses[:not_valid] = "You must enter a valid Email/Username"
        q.responses[:invalid_type] = "You must enter a valid Email/Username"
        q.validate = lambda {|p| p.length > 5 }
      end
    end

    if input[:aws_pass].nil?
      output_opts[:aws_pass] = ask("Input AWS Password: ") do |q|
        q.responses[:not_valid] = "You must enter a valid password"
        q.responses[:invalid_type] = "You must enter a valid password"
        q.validate = lambda {|p| p.length > 4 }
      end
    end

    if input[:setup_bucket].nil?
      output_opts[:setup_bucket] = ask("Input S3 Bucket name for billing: ")
    end

    if input[:aws_acct_alias].nil?
      if input[:setup_mode] == "install"
        output_opts[:aws_acct_alias] = ask("Alias you would like to setup for your AWS Account (Optional, only for initial install, hit enter otherwise): ")
        output_opts.delete(:aws_acct_alias) if output_opts[:aws_acct_alias].empty? #Catch enter/no input
      end
    end

    output_opts

  end

  def self.run
    cli = MyCLI.new
    setup_modes = ["test", "install", "uninstall", "update", "help"]
    cli.banner = "Usage: cloudhealth-setup #{setup_modes.join('|')} (options)"
    cli.parse_options
    accounts_to_setup = []
    accounts_processed = []
    setup_mode = if setup_modes.include?(ARGV[0])
                  ARGV[0]
                 else
                   # ARGV[0] is a cli option, not a mode
                   nil
                 end

    setup_mode = "install" if defined?(Ocra)

    if setup_mode.nil?
      puts ""
      puts "CloudHealth Setup"
      puts ""
      choose do |menu|
        menu.prompt = "Please choose what you want to do:"
        menu.choice(:install) { setup_mode = "install" }
        menu.choice(:uninstall) { setup_mode = "uninstall" }
        menu.choice(:test) { setup_mode = "test" }
        menu.choice(:update) { setup_mode = "update"}
        menu.choice(:help) {
          puts cli.opt_parser
          Setup.run
        }
        menu.choice(:quit) {
          setup_mode = "quit"
          Setup.immediate_exit
        }
      end
      cli.config[:simple] = true
      cli.config[:setup_mode] = setup_mode
      puts "Continuing with #{setup_mode}..."
    end

    if cli.config[:input_file]
      puts "Starting CloudHealth setup in multi-account setup mode, using input file #{cli.config[:input_file]}"
      accounts_to_setup << CsvImport.import_file(cli.config[:input_file])
    else
      puts "Starting CloudHealth setup in single account mode."
      accounts_to_setup << cli.config
    end

    accounts_to_setup.each do |account_options|
      new_account = Setup.new(account_options)

      new_account.check_iam_credentials
      new_account.check_web_credentials
      case setup_mode
      when "install"
        new_account.setup_monthly_report
        new_account.setup_s3_bucket
        new_account.setup_prog_access
        new_account.setup_detailed_billing
        new_account.setup_cost_alloc
        new_account.setup_checkboxes
        new_account.setup_ro_user
        new_account.setup_account_alias
        new_account.account_consolidated
        accounts_processed << new_account.response
      when "test"
        new_account.test_monthly_report
        new_account.test_s3_bucket
        new_account.test_prog_access
        new_account.test_detailed_billing
        new_account.test_cost_alloc
        new_account.test_checkboxes
        new_account.test_ro_user
        new_account.test_account_alias
        new_account.test_consolidated
      when "uninstall"
        new_account.uninstall_ro_user
      when "update"
        new_account.update_s3_bucket
        new_account.update_ro_user
      else
        puts cli.opt_parser
      end
    end
    Setup.write_csv(accounts_processed, cli.config[:output_file]) if setup_mode == "install"
    if ENV['OCRA_EXECUTABLE']
      Setup.run
    end
  end
end

begin
Setup.run
rescue RealExit
  exit
rescue SystemExit
  unless ENV['OCRA_EXECUTABLE']
    exit
  end
rescue Exception => e
  puts "Ran into a problem, Please contact Cloudhealth Support with this error: #{e}"
  if ENV['OCRA_EXECUTABLE']
    Setup.run
  end
end
