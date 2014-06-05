# TODO: obviate shell_out.rb and kato_shell.rb in favour of moving long-
# running tasks to kato-daemon (targetting Iggy)

Errors = VCAP::Errors

class ShellOut

  def self.logger
    @logger ||= Steno.logger("cc.shell_out")
  end

  def self.run(command, env={}, errmsg="failed to run", &on_data)
    raise "ShellOut must be called with an array command (to prevent shell injection)." unless command.kind_of?(Array)
    logger.info "Running: #{command}"
    #fiber = Fiber.current

    output = []
    exit_status = nil
    success = nil

    # Prevent bundler's env manipulations from screwing us,
    # e.g., when we try to shell out to kato
    Bundler.with_clean_env do
      old_env = ENV.clone
      ENV.replace(ENV.to_hash.merge!(env)) # ENV isn't a true hash
      IO.popen(command) do |io|
        while data = io.gets
          output.push(data)
          #ActiveRecord::Base.connection_pool.with_connection do
            # This call will exhaust the connection pool without the
            # with_connection block
            on_data.call(data) if on_data
          #end
        end
        pid, status = Process.waitpid2(io.pid)
        exit_status = status.exitstatus
      end
      success = exit_status == 0
      ENV.replace(old_env)
    end

    retval = output.join('')
    unless success
      logger.error "#{command} : #{retval}"
      raise Errors::ApiError.new_from_details("ShellOutFailure", errmsg)
    end
    retval
  end

end

