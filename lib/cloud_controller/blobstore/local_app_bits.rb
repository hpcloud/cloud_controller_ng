require "cloud_controller/safe_zipper"
require "ext/file"
require 'zip'
require 'kato/config'

module CloudController
  module Blobstore
    class LocalAppBits
      PACKAGE_NAME = "package.zip".freeze
      UNCOMPRESSED_DIR = "uncompressed"

      def self.from_compressed_bits(compressed_bits_path, tmp_dir, &block)
        if compressed_bits_path
          check_compressed_bits(compressed_bits_path)
        end
        Dir.mktmpdir("safezipper", tmp_dir) do |root_path|
          unzip_path = File.join(root_path, UNCOMPRESSED_DIR)
          FileUtils.mkdir(unzip_path)
          storage_size = 0
          if compressed_bits_path && File.exists?(compressed_bits_path)
            storage_size = SafeZipper.unzip(compressed_bits_path, unzip_path)
          end
          block.yield new(root_path, storage_size)
        end
      end

      attr_reader :uncompressed_path, :storage_size

      def initialize(root_path, storage_size)
        @root_path = root_path
        @uncompressed_path = File.join(root_path, UNCOMPRESSED_DIR)
        @storage_size = storage_size
      end

      def create_package
        destination = File.join(@root_path, PACKAGE_NAME)
        SafeZipper.zip(uncompressed_path, destination)
        File.new(destination)
      end
      
      def self.logger
        @logger || Steno.logger("cc.local_app_bits")
      end
  
      def self.get_disk_limit
        disk_limit_mb = Kato::Config.get("dea_ng", "staging/disk_limit_mb")
        disk_limit = (disk_limit_mb.to_i rescue 0) * 1024 * 1024
        raise VCAP::CloudController::Errors::StackatoNoConfigForComponent.new("dea_ng::/staging/disk_limit_mb") if disk_limit == 0
        disk_limit
      end
      
      def self.get_check_zipfile_actual_contents_size
        Kato::Config.get("cloud_controller", "staging/check_zipfile_actual_contents_size") || true
      end
  
      def self.check_compressed_bits(compressed_bits_path)
        begin
          zf = Zip::File.new(compressed_bits_path)
        rescue
          logger.debug("Failed to open zipfile on #{compressed_bits_path}: #{$!}")
          return
        end
        # Stackato bug https://bugs.activestate.com/show_bug.cgi?id=102802
        # The reported sizes of large files in zip files built without the Zip64 extension
        # are truncated to the lowest 32 bits
        #
        # So actually open the file, and count the # of bytes in each file entry,
        # complaining if we pass the limit.  It means reading the zipfile twice, but
        # avoids writing large bits of data to disk.
        check_zipfile_actual_contents_size = get_check_zipfile_actual_contents_size
        disk_limit = get_disk_limit
        read_block_size = 8 * 1024 * 1024
        total_size = 0
        zf.each do |entry|
          if entry.file? && !entry.symlink?
            size = entry.size # reported size (or actual size % 4GB)
            if total_size + size > disk_limit
              raise VCAP::Errors::AppPackageInvalid, "Package may not be larger than #{disk_limit} bytes"
            end
            if check_zipfile_actual_contents_size
              actual_size = 0
              entry.get_input_stream do |fd|
                while data = fd.read(read_block_size)
                  actual_size += data.size
                  if total_size + actual_size > disk_limit
                    raise VCAP::Errors::AppPackageInvalid, "Package may not be larger than #{disk_limit} bytes"
                  end
                end
              end
              size = actual_size
            end
            total_size += size
            # assert total_size <= disk_limit
          end
        end
      end

    end
  end
end
