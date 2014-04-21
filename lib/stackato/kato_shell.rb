require 'fileutils'
require 'stackato/shell_out'

# TODO: obviate shell_out.rb and kato_shell.rb in favour of moving long-
# running tasks to kato-daemon (targetting Iggy)

class KatoShell
  # todo: Correct paths.
  #FILESERVE = '/home/stackato/fileserve/files'
  FILESERVE = '/home/stackato/tmp'
  EXPORT_FILENAME = 'stackato-export.tgz'
  EXPORT_FILEPATH = FILESERVE + '/' + EXPORT_FILENAME

  REPORT_FILENAME = 'stackato-report.zip'
  REPORT_FILEPATH = FILESERVE + '/' + REPORT_FILENAME

  def self.run(command)
    script = ENV["KATO_SHELL"] || "/home/stackato/bin/kato"
    ShellOut.run([script] + command)
  end

  def self.report
    run(["report"])
    FileUtils.mkdir_p(FILESERVE)
    ShellOut.run(['mv', '/tmp/stackato-report.tgz', REPORT_FILEPATH])
    return REPORT_FILEPATH
  end

  def self.export(regen=false)
    if regen || !export_exists?
      if export_in_progress?
        raise CloudError.new(CloudError::CONSOLE_BAD_REQUEST, "An export is already in progress.")
      end
      # there could be a race condition here but I'm not too worried about it. We can use
      # a lockfile if it comes to that.
      FileUtils.mkdir_p(FILESERVE)
      run(%W{data export --only-this-node #{EXPORT_FILEPATH}})
    end
    return EXPORT_FILEPATH
  end

  def self.patch_status
    run(%W{patch status})
  end
  
  def self.patch_status_json
    run(%W{patch status --json --quiet})
  end
  
  def self.export_in_progress?
    return `ps --no-headers -C kato -f | grep export | wc -l`.strip.to_i > 0
  end
  
  # returns false if no export file exists, returns the file creation time if it does exist
  def self.export_exists?
    return File.exist?(EXPORT_FILEPATH) && File.ctime(EXPORT_FILEPATH)
  end

end

