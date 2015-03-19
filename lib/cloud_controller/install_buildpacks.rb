require 'uri'

module VCAP::CloudController
  class InstallBuildpacks

    BUILDPACK_DIR = "/tmp/packages"

    attr_reader :config

    def initialize(config)
      @config = config
    end

    def install(buildpacks)
      return unless buildpacks

      buildpacks.each do |bpack|
        FileUtils.mkdir_p(BUILDPACK_DIR)

        buildpack = VCAP.symbolize_keys(bpack)

        buildpack_name = buildpack.delete(:name)
        if buildpack_name.nil?
          logger.error "A name must be specified for the buildpack: #{buildpack}"
          next
        end

        url = buildpack.delete(:url)
        if url.nil?
          package = buildpack.delete(:package)
          buildpack_file = buildpack.delete(:file)
          if package.nil? && buildpack_file.nil?
            logger.error "A package or file must be specified for the buildpack: #{bpack}"
            next
          end

          buildpack_file = buildpack_zip(package, buildpack_file)
          if buildpack_file.nil?
            logger.error "No file found for the buildpack: #{bpack}"
            next
          elsif !File.file?(buildpack_file)
            logger.error "File not found: #{buildpack_file}, for the buildpack: #{bpack}"
            next
          end

        else # url not nil
          uri = URI(url)
          branch = uri.fragment
          uri.fragment = nil

          if uri.path.end_with? ".git"
            basename = File.basename(uri.path, ".git")
            dirname = "#{BUILDPACK_DIR}/#{basename}"
            ok = system("git clone #{uri} #{dirname}")
            unless ok
              logger.error "git failed to clone #{uri} for buildpack #{bpack}"
              next
            end
            if branch
              ok = system("cd #{dirname} && git checkout #{branch}")
              unless ok
                logger.error "git failed to checkout #{branch} from #{uri} for buildpack #{bpack}"
                next
              end
            end

            buildpack_file = "#{dirname}.zip"
            ok = system("cd #{dirname} && zip -roq9 #{buildpack_file} *")
            unless ok
              logger.error "zip of #{dirname} failed for buildpack #{bpack}"
              next
            end

          elsif uri.path.end_with? ".zip"
            basename = File.basename(uri.path)
            buildpack_file = "#{BUILDPACK_DIR}/#{basename}"
            ok = system("wget #{uri} -O #{buildpack_file}")
            unless ok
              logger.error "wget failed to fetch #{uri} for buildpack #{bpack}"
              next
            end
          else
            logger.error "Url #{uri} for buildpack #{bpack} doesn't end with either .git or .zip"
            next
          end

          unless File.file?(buildpack_file)
            logger.error "Buildpack file #{buildpack_file} not found, for the buildpack: #{bpack} from #{url}"
            next
          end

        end

        buildpack_job = VCAP::CloudController::Jobs::Runtime::BuildpackInstaller.new(buildpack_name, buildpack_file, buildpack)
        # job = VCAP::CloudController::Jobs::Enqueuer.new(buildpack_job, queue: LocalQueue.new(config)).enqueue()
        # run job synchronously so that we can safely remove the downloaded bits again
        buildpack_job.perform
        FileUtils.rm_rf(BUILDPACK_DIR)
      end
    end

    def logger
      @logger ||= Steno.logger("cc.install_buildpacks")
    end

    private

    def buildpack_zip(package, zipfile)
      return zipfile if zipfile
      job_dir = File.join('/var/vcap/packages', package, '*.zip')
      Dir[job_dir].first
    end

  end
end
