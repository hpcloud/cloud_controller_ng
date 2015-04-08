
            # We need this sometimes to correct the yaml serialization
            module Delayed::Backend::Sequel
              class Job
                def payload_object=(object)
                  @payload_object = object
                  self.handler = object.to_yaml.gsub('!ruby/Sequel:VCAP::CloudController',
                                                     '!ruby/object:VCAP::CloudController')
                end
              end
            end
