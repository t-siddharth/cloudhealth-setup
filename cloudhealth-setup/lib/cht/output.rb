class Setup
  def self.write_csv(accounts, filename)
    if filename.nil?
      if ENV["OCRA_EXECUTABLE"]
        # We are on windows, in OCRA
        win_desktop = ENV['HOME'] + '/Desktop'
        win_filename = win_desktop + "/cloudhealth-accounts.csv"
        filename = ask("Please give me full path to save output csv to (Hit enter for default: #{win_filename} ): ")
        if filename.empty?
          filename = win_filename
        end
      else
        filename = ask("Please give me the full path to the save output csv to: (Hit enter for default: ./cloudhealth-setup.csv): ")
        if filename.empty?
          filename = "./cloudhealth-setup.csv"
        end
      end
    end
    file_exists = File.exists?(filename)
    mode = if file_exists
             if @overwrite_file
               puts "CSV Output file #{filename} exists! Overwriting the file per --overwrite."
               "wb"
             else
               puts "CSV Output file #{filename} exists! Appending to existing file."
               "ab"
             end
           else
             "wb"
           end

    count = 0
    CSV.open(File.expand_path(filename), mode) do |csv|
      unless mode == "ab"
        csv << ["Account ID", "Console URL", "IAM Username", "IAM Password", "AWS Access Key", "AWS Access Secret", "S3 Bucket", "Is Consolidated?"]
      end
      accounts.each do |account|
        count += 1
        csv << [account[:account_id], account[:account_url], account[:user], account[:user_pass], account[:access_key], account[:secret_key], account[:s3_bucket], account[:consolidated]]
      end
    end
    puts "Finished setting up #{count} account(s). CSV File path: #{filename}"
  end

  def response
    @created_account
  end
end
