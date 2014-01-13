class Setup
  AWS_LOGIN_URL = 'https://www.amazon.com/ap/signin?openid.assoc_handle=aws&openid.return_to=https%3A%2F%2Fportal.aws.amazon.com%2Fgp%2Faws%2Fdeveloper%2Faccount%2Findex.html%3Fie%3DUTF8%26action%3Dactivity-summary&openid.mode=checkid_setup&openid.ns=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0&openid.identity=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select&openid.claimed_id=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select&action=&disableCorpSignUp=&clientContext=&marketPlaceId=&poolName=&authCookies=&pageId=aws.ssop&siteState=&accountStatusPolicy=&sso=&openid.pape.preferred_auth_policies=MultifactorPhysical&openid.pape.max_auth_age=3600&openid.ns.pape=http%3A%2F%2Fspecs.openid.net%2Fextensions%2Fpape%2F1.0&server=%2Fap%2Fsignin%3Fie%3DUTF8&accountPoolAlias='

  def mech_browser
    # Creating Mechanize object
    browser = Mechanize.new
    browser.verify_mode = OpenSSL::SSL::VERIFY_NONE
    browser.redirect_ok = true
    # Let's give some header here
    browser.request_headers['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_4) AppleWebKit/537.4 (KHTML, like Gecko) Chrome/22.0.1229.94 Safari/537.4'
    browser.request_headers['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    browser.request_headers['application/xml'] = '*/*'
    browser
  end

  def get_page
    begin
      url = AWS_LOGIN_URL
      page = @browser.get(url)
      signed_in = page.link_with(:text => "Sign Out")

      if signed_in.nil? # Since @browser is shared, sometimes we are already logged in.
          form = page.form_with(:name => 'signIn')
          form['email'] = @aws_user
          form['password'] = @aws_pass
          login_page = form.submit

          if login_page.code.to_i != 200
            puts "The login page returned error code #{login_page.code}"
            raise SetupFailed, "   Could not login to AWS Web Console, Amazon may be experiencing issues or the credentials you provided are incorrect. HTTP Code: #{login_page.code}"
          end

        # A Captcha can be present if they failed to login too many times, Lets detect it here.
        captcha_form = login_page.form_with(:id => 'ap_signin_form')
        unless captcha_form.nil?
          captcha_on = captcha_form.field_with(:id => 'ap_captcha_guess')
          unless captcha_on.nil?
            raise SetupFailed, "  Your account currently has a captcha on the login screen, This is most likely due to failed logins. Please login to your account at http://aws.amazon.com/ to stop the Captcha and then retry cloudhealth-setup."
          end
        end

        mfa_form = login_page.form_with(:id => 'ap_signin_form')
        unless mfa_form.nil?
          if @mfa.nil?
            @mfa = ask("Multi-Factor Authentication detected, please enter 6 digit pin: ") do |q|
              q.responses[:not_valid] = "You must enter a 6 digit MFA pin."
              q.responses[:invalid_type] = "You must enter a 6 digit MFA pin."
              q.validate = lambda {|p| p.length == 6 }
            end
          end
          mfa_form['tokenCode'] = @mfa
          mfa_form.submit
        end
      end


      account_id_search = page.search('//span[@class="txtxxsm"]/text()')
      unless account_id_search.nil? || account_id_search.size == 0 || @created_account[:account_id]
        firstw, secondw, account_id_long = account_id_search.first.content.strip.split(" ")
        account_id = account_id_long.gsub("-","")
        puts "    Account ID for this account is: #{account_id.to_s}" if @verbose
        @aws_account_id = account_id
        @created_account.merge!(:account_id => account_id)
      end

      page = @browser.get("https://portal.aws.amazon.com/gp/aws/developer/account?ie=UTF8&action=billing-preferences")

      if page.code.to_i != 200
        raise SetupFailed, "  Could not login to AWS Web Console, Amazon may be experiencing issues or the credentials you provided are incorrect. HTTP Code: #{page.code}"
      end

      page
    rescue => e
      #TODO: Fix when multi input account works
      #raise SetupFailed, e
      puts e
      windows_exit
    end
  end

  def check_web_credentials
    get_page
    get_page # We run this twice, only on the second login do we find our account id on the initial page. This primes the pump so to speak anyway for subsequent usage. TODO: Fix me
    if @aws_account_id.nil? || @aws_account_id.empty?
      if @input_file.nil? || @input_file.empty?
        # Single account mode
        puts "Could not login to your account with the provided Amazon Web Services credentials. Please check your provided email address and password and try again. If issue persists contact support@cloudhealthtech.com."
        windows_exit
      else
        # Multi account mode
        raise SetupFailed, "Could not login to your account with the provided Amazon Web Services credentials. Please check your provided email address and password and try again. If issue persists contact support@cloudhealthtech.com."
      end
    end
  end

  def test_consolidated
    page = @browser.get("https://portal.aws.amazon.com/gp/aws/developer/account?ie=UTF8&action=consolidated-billing")
    consolidated_link = page.link_with(:href => "https://portal.aws.amazon.com/gp/aws/developer/subscription/index.html?ie=UTF8&productCode=AWSCBill")
    if consolidated_link.nil?
      puts "[O] Account is setup on consolidated billing - Optional"
    else
      #We must be on consolidated billing
      puts "[O] Account is not on consolidated billing - Optional"
    end
  end

  def account_consolidated
    page = @browser.get("https://portal.aws.amazon.com/gp/aws/developer/account?ie=UTF8&action=consolidated-billing")
    consolidated_link = page.link_with(:href => "https://portal.aws.amazon.com/gp/aws/developer/subscription/index.html?ie=UTF8&productCode=AWSCBill")
    if consolidated_link.nil?
      @created_account.merge!(:consolidated => true)
      puts "Account is on consolidated billing"
    else
      #We must be on consolidated billing
      @created_account.merge!(:consolidated => false)
      puts "Account is not on consolidated billing"
    end
  end

  def dump_page(page)
      no = rand(500)
      puts "Writing out page as #{no}.html"
      File.open("#{no}.html", 'w') do |file|
          file << page.body
      end
  end

  def test_monthly_report
    begin
      page = get_page
      monthly_report_form = page.form_with(:name => "csvReportOptInForm")
      mrf_enabled = monthly_report_form.field_with(:name => "buttonOption")

      if mrf_enabled.value == "EnableCSVReport"
        puts "[ ] Monthly report -- Disabled"
      elsif mrf_enabled.value == "CancelCSVReport"
        puts "[X] Monthly report -- Enabled"
      end
    rescue => e
      puts "    We were unable to test if monthly report access is enabled."
      puts "    This setting can be checked manually under Billing Preferences from the AWS Account page."
      warning(e)
    end
  end

  def setup_monthly_report
    begin
      puts "Setting up monthly report access... "
      page = get_page
      monthly_report_form = page.form_with(:name => "csvReportOptInForm")
      mrf_enabled = monthly_report_form.field_with(:name => "buttonOption")

      if mrf_enabled.value == "EnableCSVReport"
        puts "    Report not enabled, enabling... "
        monthly_report_form.submit
      elsif mrf_enabled.value == "CancelCSVReport"
        puts "    Report already enabled... "
      end
      puts "    Monthly report access setup complete."
    rescue => e
      puts "    We were unable to setup monthly report access."
      puts "    This setting can be enabled manually under Billing Preferences from the AWS Account page."
      warning(e)
    end
  end

  def test_prog_access
    begin
      page = get_page
      prog_access_form = page.form_with(:name => "paOptInForm")
      paf_enabled = prog_access_form.field_with(:name => "existingS3BucketName")

      if paf_enabled.nil?
        puts "[ ] Programmatic access not setup -- Disabled"
      else
        puts "[X] Programmatic access is setup -- Enabled"
      end
    rescue => e
      puts "    We were unable to test programmatic access to your billing information."
      puts "    You can manually enable/test this by following these instructions: http://docs.aws.amazon.com/awsaccountbilling/latest/about/programaccess.html"
      warning(e)
    end
  end

  def setup_prog_access
    begin
      puts "Setting up programmatic access to billing... "
      page = get_page
      prog_access_form = page.form_with(:name => "paOptInForm")
      paf_enabled = prog_access_form.field_with(:name => "existingS3BucketName")

      if paf_enabled.nil?
        puts "    Enabling access in bucket #{@setup_bucket}... "
        prog_access_form['s3BucketName'] = @setup_bucket
        prog_access_form.submit
      else
        if paf_enabled.value == @setup_bucket
          puts "    Access already enabled on bucket #{@setup_bucket}..."
        else
          puts "    S3 Bucket is currently set to #{paf_enabled.value}, You requested it be set to #{@setup_bucket} -- Changing it."
          prog_access_form['s3BucketName'] = @setup_bucket
          prog_access_form.submit
        end
      end
      puts "    Setup of programmatic access to billing finished"
    rescue => e
      puts "    We were unable to setup programmatic access to your billing information."
      puts "    You can manually enable this by following these instructions: http://docs.aws.amazon.com/awsaccountbilling/latest/about/programaccess.html"
      warning(e)
    end
  end

  def test_detailed_billing
    begin
      page = get_page
      detailed_billing_form = page.form_with(:name=>'hourlyOptInForm')
      bill_enabled = detailed_billing_form.field_with(:name => "buttonOptionHourly")

      detailed_billing_tag_form = page.form_with(:name => 'hourlyWithResourcesAndTagsOptInForm')
      tag_bill_enabled = detailed_billing_tag_form = detailed_billing_tag_form.field_with(:name => "buttonOptionHourlyWithResourcesAndTags")

      if bill_enabled.value == "EnableHourly"
        puts "[ ] Detailed billing report not setup -- Disabled"
      elsif bill_enabled.value == "DisableHourly"
        puts "[X] Detailed billing report setup -- Enabled"
      end

      if tag_bill_enabled.value == "EnableHourlyWithResourcesAndTags"
        puts "[ ] Detailed billing report w/ tags & resources not setup -- Disabled"
      elsif tag_bill_enabled.value == "DisableHourlyWithResourcesAndTags"
        puts "[X] Detailed billing report w/ tags & resources setup -- Enabled"
      end
    rescue => e
      puts "    We were unable to test detailed billing reports."
      puts "    This setting can be enabled/tested manually under Billing Preferences from the AWS account page."
      warning(e)
    end
  end

  def setup_detailed_billing
    begin
      puts "Setting up detailed billing report..."
      page = get_page

      # This is the regular detailed billing report
      detailed_billing_form = page.form_with(:name=>'hourlyOptInForm')
      bill_enabled = detailed_billing_form.field_with(:name => "buttonOptionHourly")

      # This is the detailed billing report with tags and resources
      detailed_billing_tag_form = page.form_with(:name => 'hourlyWithResourcesAndTagsOptInForm')
      tag_bill_enabled = detailed_billing_tag_form.field_with(:name => "buttonOptionHourlyWithResourcesAndTags")

      if bill_enabled.value == "EnableHourly"
        puts "    Enabling detailed billing report... "
        detailed_billing_form.submit
      elsif bill_enabled.value == "DisableHourly"
        puts "    Detailed report already enabled... "
      end

      if tag_bill_enabled.value == "EnableHourlyWithResourcesAndTags"
        puts "    Enabling detailed billing report w/ tags & resources... "
        detailed_billing_tag_form.submit
      elsif tag_bill_enabled.value == "DisableHourlyWithResourcesAndTags"
        puts "    Detailed report w/ resources & tags already enabled... "
      end
      puts "    Report setup finished"

    rescue => e
      puts "    we were unable to enable detailed billing reports."
      puts "    This setting can be enabled manually under Billing Preferences from the AWS account page."
      warning(e)
    end
  end

  def test_cost_alloc
    begin
      page = get_page
      cost_alloc_form = page.form_with(:name=>'carOptInForm')
      car_enabled = cost_alloc_form.field_with(:name => "buttonOptionCAR")

      if car_enabled.value == "EnableCAR"
        puts "[ ] Cost allocation report not setup -- Disabled"
      elsif car_enabled.value == "DisableCAR"
        puts "[X] Cost allocation report setup -- Enabled"
      end
    rescue => e
      puts "    We were unable to test cost allocation reports."
      puts "    This setting can be tested manually under Billing Preferences from the AWS account page."
      warning(e)
    end
  end

  def setup_cost_alloc
    begin
      puts "Setting up cost allocation report... "
      page = get_page
      cost_alloc_form = page.form_with(:name=>'carOptInForm')
      car_enabled = cost_alloc_form.field_with(:name => "buttonOptionCAR")

      if car_enabled.value == "EnableCAR"
        puts "    Enabling cost allocation report... "
        cost_alloc_form.submit
      elsif car_enabled.value == "DisableCAR"
        puts "    Report already enabled... "
      end
      puts "    Report setup finished"
    rescue => e
      puts "    We were unable to enable cost allocation reports."
      puts "    This setting can be enabled manually under Billing Preferences from the AWS account page."
      warning(e)
    end
  end

  def test_checkboxes
    begin
      get_page
      page = @browser.get("https://portal.aws.amazon.com/gp/aws/manageYourAccount")
      checkbox_account_activity_search = page.search('[@id="account_activity_checkbox"]')
      usage_report_search = page.search('[@id="usage_reports_checkbox"]')
      activate_button_search = page.search('[@id="activateIAMUserAccess"]')
      deactivate_button_search = page.search('[@id="deactivateIAMUserAccess"]')

      activate_hidden = begin
                          activate_button_search.first.attributes['style'].value.include?("display:none")
                        rescue
                          false
                        end

      deactivate_hidden = begin
                            deactivate_button_search.first.attributes['style'].value.include?("display:none")
                          rescue
                            false
                          end

      if activate_hidden
        #Activate button is hidden, Deactivate is shown
        if checkbox_account_activity_search.first.attributes['checked'].nil?
          # Not checked
          puts "[ ] IAM access to Account Activity not setup -- Disabled"
        else
          # Checked
          puts "[X] IAM access to Account Activity is setup -- Enabled"
        end
        if usage_report_search.first.attributes['checked'].nil?
          # Not checked
          puts "[ ] IAM access to Usage Reports not setup -- Disabled"
        else
          # Checked
          puts "[X] IAM access to Usage Reports is setup -- Enabled"
        end
      elsif deactivate_hidden
        #Deactivate button is hidden, Activate shown
        if checkbox_account_activity_search.first.attributes['checked'].nil?
          # Not checked
          puts "[X] IAM access to Account Activity is setup -- Enabled"
        else
          # Checked
          puts "[ ] IAM access to Account Activity not setup -- Disabled"
        end
        if usage_report_search.first.attributes['checked'].nil?
          # Not checked
          puts "[X] IAM access to Usage Reports is setup -- Enabled"
        else
          # Checked
          puts "[ ] IAM access to Usage Reports not setup -- Disabled"
        end
      else
        puts "[ ] Could not get status of IAM Usage report & Account activity checkboxes - Unknown"
      end
    rescue => e
      warning(e)
    end
  end

  def setup_checkboxes
    checkbox_setup_error = "    We were unable to enable account activity & usage reports.\n    This setting can be enabled manually under the Manage Your Account from the AWS account page."
    begin
      puts "Enabling account activity & usage reports..."
      page = @browser.get("https://portal.aws.amazon.com/gp/aws/manageYourAccount?action=updateIAMUserAccess&activateaa=1&activateur=1")
      json = JSON.parse(page.body)
      if json["error"] != "0"
        puts checkbox_setup_error
      else
        puts "    Activity & Usage reports enabled."
      end
    rescue => e
      puts checkbox_setup_error
      warning(e)
    end
  end
end
