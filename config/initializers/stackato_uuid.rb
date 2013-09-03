

module CCInitializers
  def self.stackato_uuid(cc_config)
    uuid = File.read('/s/etc/uuid').strip rescue nil
    Kernel.const_set('STACKATO_UUID', uuid)
  end
end
