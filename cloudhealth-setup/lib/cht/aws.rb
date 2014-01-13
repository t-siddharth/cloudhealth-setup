class Setup
  def iam
    begin
      Fog::AWS::IAM.new({:aws_access_key_id => @aws_key, :aws_secret_access_key => @aws_secret})
    rescue => e
      critical_failure("Failed to connect to Amazon AWS IAM: Please ensure your provided credentials are correct and you have internet access. #{e if @verbose}")
    end
  end

  def s3
    begin
      Fog::Storage.new({:provider => 'AWS', :aws_access_key_id => @aws_key, :aws_secret_access_key => @aws_secret})
    rescue => e
      critical_failure("Failed to connect to Amazon AWS S3: Please ensure your provided credentials are correct and you have internet access. #{e if @verbose}")
    end
  end

  def check_iam_credentials
    puts "Please wait, ensuring the provided credentials work."
    begin
      @iam.list_users
    rescue => e
      if @input_file.nil? || @input_file.empty?
        # Single account mode
        puts "Could not login to your account with the provided Amazon Web Services credentials. Please check your AWS Access Key and Secret Access Key and try again. If issue persists contact support@cloudhealthtech.com."
        windows_exit
      else
        # Multi account mode
        raise SetupFailed, "Could not login to your account with the provided Amazon Web Services credentials. Please check your AWS Access Key and Secret Access Key and try again. If issue persists contact support@cloudhealthtech.com."
      end
    end
  end

  def test_ro_user
    begin
      if user_exists
        puts "[X] AWS Read-Only user (#{@aws_ro_name}) is setup -- Exists"
      else
        puts "[ ] AWS Read-Only user (#{@aws_ro_name}) not setup -- No user"
      end
      if user_has_policy
        puts "[X] AWS Read-Only user has a policy -- Exists"
      else
        puts "[ ] AWS Read-Only user has no policy -- No policy"
      end
    rescue => e
      puts "    We were unable to test your read only user."
      puts "    Please contact CloudHealth support at support@cloudhealthtech.com."
      warning(e)
    end
  end

  def uninstall_ro_user
    begin
      print "Delete Cloudhealth Read-only user #{@aws_ro_name},attached policies, profiles (y/n)? "
      k = get_character
      if k.chr == "y"
        puts "Deleting user #{@aws_ro_name} and all associated policies and login profiles..."
        user_policies = @iam.list_user_policies(@aws_ro_name)

        user_policies.body['PolicyNames'].each do |policy|
          puts "    Deleting user policy #{policy} attached to this user."
          @iam.delete_user_policy(@aws_ro_name, policy)
        end

        puts "    Deleting users access keys..."
        access_keys = @iam.list_access_keys('UserName' => @aws_ro_name).body

        access_keys['AccessKeys'].each do |access_key|
          puts "    Deleting access key #{access_key['AccessKeyId']}..."
          @iam.delete_access_key(access_key['AccessKeyId'], 'UserName' => @aws_ro_name)
        end

        begin
          puts "    Deleting login profile..."
          @iam.delete_login_profile(@aws_ro_name)
        rescue => e
          puts "    User does not have a login profile, skipping."
          warning(e)
        end

        puts "    Deleting user...."
        @iam.delete_user(@aws_ro_name)
        puts "    IAM User #{@aws_ro_name} deleted."
      else
        puts "    You did not agree to delete the AWS Read only user #{aws_ro_name}."
      end
    rescue => e
      if defined? e.response
        if e.response.status == 409
          puts "    Could not delete user and/or login profile/policy, subordinate entities exist."
        elsif e.response.status == 404
          puts "    Could not delete user and/or login profile/policy, user/profile/policy does not exist."
        else
          puts "    Could not delete User or Policy/profile, unknown error: #{e.response.inspect}"
        end
      else
        puts "    Could not delete: #{e.message}"
        warning(e) if @verbose
      end
    end
  end

  def setup_ro_user
    user_created = nil
    begin
      puts "Setting up AWS Read only user... "
      if @aws_ro_name.nil?
        puts "    Name not specified -- Skipping."
      else
        if user_exists
          if @ro_user_exists
            puts "    User #{@aws_ro_name} exists... continuing due to --user-exists"
            puts "    Note: CSV Output file will NOT be complete. Since we did not create the aws read only user"
            puts "          You must fill in the blanks of the CSV if you plan on importing the CSV on the website."
            puts "          Consider running update instead."
          else
            #TODO This should not exit() in multi-account import mode, it should be raised up and caught. e.g. SetupFailed
            puts "User #{@aws_ro_name} exists already, If this was your intention please re-run with --user-exists and ensure you update the CSV manually or choose another username via -r <name>. If your intention was to just update, please run the update process on this script instead."
            windows_exit
          end
        else
          puts "    Creating user... "
          user_create = @iam.create_user(@aws_ro_name)
          key_create = @iam.create_access_key('UserName' => @aws_ro_name)
          access_key = key_create.body['AccessKey']['AccessKeyId']
          secret_key = key_create.body['AccessKey']['SecretAccessKey']
          arn = user_create.body['User']['Arn']
          user_pass = create_user_password
          @created_account.merge!(:access_key => access_key, :secret_key => secret_key, :user_pass => user_pass, :user => @aws_ro_name)
          user_created = "    The user #{@aws_ro_name} has been created with password #{user_pass}, access key #{access_key}, and secret key #{secret_key}"
        end
        if user_has_policy
          puts "    User policy already exists..."
        else
          puts "    Creating user policy... "
          @iam.put_user_policy(@aws_ro_name, "CHTRoPolicy", aws_ro_policy)
        end
        puts user_created unless user_created.nil?
        puts "    Setup of AWS Read only user completed"

      end
    rescue => e
      puts "    We were unable to create a read only user."
      puts "    Please contact CloudHealth support at support@cloudhealthtech.com."
      warning(e)
    end
  end

  def test_s3_bucket
    begin
      if @s3.directories.collect{|d| d.key}.include?(@setup_bucket)
        puts "[X] S3 Billing bucket (#{@setup_bucket}) -- Enabled"
      else
        puts "[ ] S3 Billing bucket (#{@setup_bucket}) -- Does not exist"
      end

      if bucket_has_policy
        puts "[X] S3 Billing bucket policy -- Exists"
      else
        puts "[ ] S3 Billing bucket policy -- No Policy"
      end
    rescue => e
      puts "    We were unable to test your S3 billing bucket. You can manually enable this,"
      puts "    by following these instructions: http://docs.aws.amazon.com/awsaccountbilling/latest/about/programaccess.html"
      warning(e)
    end
  end

  def setup_s3_bucket
    begin
      puts "Setting up S3 billing bucket... "
      if @s3.directories.collect{|d| d.key}.include?(@setup_bucket)
        puts "    Bucket exists..."
      else
        puts "    Creating bucket... "
        begin
          @s3.directories.create(:key => @setup_bucket, :public => false)
        rescue => e
          if e.response.status == 409
            puts "    The bucket you are trying to use is already created, but owned by another account. Please use another bucket name."
          else
            raise e
          end
        end
      end

      if bucket_has_policy
        puts "    Bucket already has policy... "
      else
        puts "    Creating bucket policy..."
        @s3.put_bucket_policy(@setup_bucket, bucket_policy)
      end
      @created_account.merge!(:s3_bucket => @setup_bucket)
      puts "    Bucket setup finished"
    rescue => e
      puts "    We were unable to setup an S3 billing bucket. You can manually enable this,"
      puts "    by following these instructions: http://docs.aws.amazon.com/awsaccountbilling/latest/about/programaccess.html"
      warning(e)
    end
  end

  def user_exists
    begin
      @iam.get_user(@aws_ro_name)
      true
    rescue
      false
    end
  end

  def test_account_alias
    begin
      acct_aliases = @iam.list_account_aliases.body['AccountAliases']
      if acct_aliases.empty?
        puts "[ ] AWS Account alias is not setup, Account ID: #{@aws_account_id} used instead -- Not setup"
      else
        puts "[X] AWS Account alias(es) are setup (#{acct_aliases.map{|aa| aa.strip}.join(', ')}), ID: #{@aws_account_id} -- Setup"
      end
    rescue => e
      puts "    We were unable to check for an account alias."
      puts "    Please contact CloudHealth support at support@cloudhealthtech.com"
      warning(e)
    end
  end

  def setup_account_alias
    begin
      if @aws_acct_alias.nil?
        puts "AWS account alias not given, will use account id: #{@created_account[:account_id]} -- Skipping alias setup."
        @created_account.merge!(:account_alias => @created_account[:account_id],
                                :account_url => "https://#{@created_account[:account_id]}.signin.aws.amazon.com/")
      else
        puts "Setting up account alias... "
        begin
          @iam.create_account_alias(@aws_acct_alias)
          puts "    alias set to #{@aws_acct_alias}..."
        rescue => e
          if e.class == Fog::AWS::IAM::EntityAlreadyExists
            puts "    Account alias was already set."
          elsif e.response.status == 409
            puts "    Account alias was already set."
          else
            raise e
          end
        end
        @created_account.merge!(:account_alias => @aws_acct_alias,
                                :account_url => "https://#{@aws_acct_alias}.signin.aws.amazon.com/")
      end
    rescue => e
      puts "    We were unable to create an account alias."
      puts "    Please contact CloudHealth support at support@cloudhealthtech.com"
      warning(e)
    end
  end

  def create_user_password
    puts "    Setting user password"
    pw = SecureRandom.hex
    begin
      @iam.create_login_profile(@aws_ro_name, pw)
    rescue => e
      if e.response.status == 409
        puts "    User already had a password set..."
      else
        raise e
      end
    end
    pw
  end

  def update_ro_user
    ro_username = if user_exists
                    @aws_ro_name
                  else
                    ask("What is your cloudhealth read only username?")
                  end
    iam_user = @iam.get_user(ro_username)
    if iam_user.nil?
      puts "Could not find your cloudhealth ro user, exiting..."
      windows_exit
    end
    @aws_ro_name = ro_username unless @aws_ro_name.nil?
    if user_has_policy
      @iam.delete_user_policy(@aws_ro_name,"CHTRoPolicy")
    end
    @iam.put_user_policy(@aws_ro_name, "CHTRoPolicy", aws_ro_policy)
    puts "Cloudhealth RO user #{@aws_ro_name} policy updated"
  end

  def update_s3_bucket
    unless @s3.directories.collect{|d| d.key}.include?(@setup_bucket)
      puts "Could not find S3 bucket #{@setup_bucket}, Please retry after verifying bucket exists"
    end
    if bucket_has_policy
      @s3.delete_bucket_policy(@setup_bucket)
    end
    @s3.put_bucket_policy(@setup_bucket, bucket_policy)
    puts "Cloudhealth billing bucket #{@setup_bucket} policy updated"
  end
end
