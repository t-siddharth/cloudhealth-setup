class SetupFailed < StandardError
end

class ReSetup < StandardError
end

class RealExit < StandardError
end

class Setup
  def self.immediate_exit
    # We should actually detect windows here then wait much longer
    puts "Cloudhealth setup finished"
    if ENV["OCRA_EXECUTABLE"]
      sleep 2
      raise RealExit
    end
    exit
  end

  def windows_exit
    # We should actually detect windows here then wait much longer
    puts "Cloudhealth setup finished"
    if ENV["OCRA_EXECUTABLE"]
      sleep
    end
    exit
  end

  def self.rerun
    raise ReSetup
  end

  def critical_failure(message)
    puts message
    #raise SetupFailed, message
  end

  def warning(e)
    if @verbose || ENV["OCRA_EXECUTABLE"]
      puts e
      puts e.backtrace
    end
  end
end
