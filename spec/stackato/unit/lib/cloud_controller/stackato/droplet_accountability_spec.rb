require 'spec_helper'
require 'stackato/spec_helper'
require 'cloud_controller/stackato/droplet_accountability'

module VCAP::CloudController
  describe StackatoDropletAccountability do
    let(:redis) { instance_double(Redis) }
    let(:message_bus) { instance_double(CfMessageBus::MessageBus) }

    before do
      allow(StackatoDropletAccountability).to receive(:redis) do |&block|
        block.call(redis)
      end
      allow(StackatoDropletAccountability).to receive(:message_bus)
        .and_return(message_bus)
    end

    # Delete once we upgrade ActiveSupport
    def deep_symbolize_keys!(obj)
      obj.symbolize_keys! if obj.respond_to? :symbolize_keys!
      if obj.respond_to? :each_value
        obj.each_value {|v| deep_symbolize_keys!(v)}
      elsif obj.respond_to? :each
        obj.each {|v| deep_symbolize_keys!(v)}
      end
      obj
    end

    def deep_stringify_keys!(obj)
      obj.stringify_keys! if obj.respond_to? :stringify_keys!
      if obj.respond_to? :each_value
        obj.each_value {|v| deep_stringify_keys!(v)}
      elsif obj.respond_to? :each
        obj.each {|v| deep_stringify_keys!(v)}
      end
      obj
    end

    describe '.get_all_dea_stats' do
      it "should get dea statistics" do
        dea_stats = [
          {
            dea_id: "dea_0",
            dea_ip: "192.0.2.1",
            available_memory: 2457,
            physical_memory: 3072,
          },
          {
            dea_id: "dea_1",
            dea_ip: "192.0.2.2",
            available_memory: 3276,
            physical_memory: 4096,
          },
        ]
        usage_stats = {
          "dea_0" => { total_used: 123, total_allocated: 456 },
          "dea_1" => { total_used: 1234, total_allocated: 5678 },
        }
        active_deas = dea_stats.map do |stat|
          instance_double(Dea::NatsMessages::DeaAdvertisement, stat)
        end
        expect(Dea::Client).to receive(:active_deas).and_return(active_deas)
        expect(described_class)
          .to receive(:get_dea_stats)
          .at_least(1).times do |dea_id|
            expect(usage_stats).to include(dea_id)
            usage_stats[dea_id]
          end
        expect(described_class.get_all_dea_stats)
          .to eq(usage_stats.each_with_index.map do |(_, usage), index|
                   dea = dea_stats[index]
                   usage.merge(dea_id: dea[:dea_id],
                               dea_ip: dea[:dea_ip],
                               total_available: dea[:available_memory],
                               total_physical: dea[:physical_memory])
                 end)
      end
    end

    describe '.get_dea_stats' do
      dea_id = "dea_0"
      mb = 1024 * 1024

      it "should return total allocated and used" do
        allow(redis).to receive(:keys)
          .with("dea:#{dea_id}:instances:*")
          .and_return(["instance:1", "instance:2"])
        allow(redis).to receive(:mget)
          .with(match_array(["instance:1", "instance:2"]))
          .and_return([[123, 456], [1234, 5678]].map{|x, y| "#{x * mb}:#{y * mb}"})
        expect(described_class.get_dea_stats(dea_id))
          .to eq({
            total_allocated: 456 + 5678,
            total_used: 123 + 1234,
          })
      end

      it "should accept nil keys" do
        expect(redis).to receive(:keys).and_return(nil)
        expect(described_class.get_dea_stats(dea_id))
          .to eq(total_allocated: 0, total_used: 0)
      end

      it "should ignore connection errors" do
        expect(redis).to receive(:keys).and_raise Redis::BaseConnectionError
        expect {
          described_class.get_dea_stats(dea_id)
        }.not_to raise_error
      end

      it "should ignore command errors" do
        expect(redis).to receive(:keys).and_raise Redis::CommandError
        expect {
          described_class.get_dea_stats(dea_id)
        }.not_to raise_error
      end
    end

    describe '.get_app_stats' do
      let (:app) do
        instance_double(App,
                        guid: "guid",
                        :started? => true,
                        instances: 2).tap do |app|
            allow(app).to receive(:name).and_return("dummy_app")
          end
        end
      it "should ignore stopped apps" do
        expect(app).to receive(:started?).and_return(false)
        expect(described_class.get_app_stats(app))
          .to eq({})
      end

      it "should ignore connection errors when getting instances" do
        expect(redis).to receive(:keys)
          .with("droplet:guid:instance:*")
          .and_raise Redis::BaseConnectionError
        expect(described_class.get_app_stats(app)).to eq({
          0 => {"state" => "DOWN"},
          1 => {"state" => "DOWN"}
        })
      end

      it "should ignore connection errors when getting values" do
        expect(redis).to receive(:keys)
          .with("droplet:guid:instance:*")
          .and_return(["droplet:guid:instance:one"])
        expect(redis).to receive(:hmget)
          .and_raise Redis::BaseConnectionError
        expect(described_class.get_app_stats(app))
          .to eq({
            0 => {"state" => "DOWN"},
            1 => {"state" => "DOWN"},
          })
      end

      it "should return expected values" do
        instances = {
          "droplet:guid:instances:one" => {
            index: 0, uptime: 1, disk: 2, mem: 3, cpu: 4, state: "RUNNING", stats: {
              stat_value_one: "one"
            }.to_json
          },
          "droplet:guid:instances:two" => {
            index: 1, uptime: 5, disk: 6, mem: 7, cpu: 8, state: "STOPPED", stats: {
              stat_value_two: "two"
            }.to_json
          }
        }
        expect(redis).to receive(:keys)
          .with("droplet:guid:instance:*")
          .and_return(instances.keys)
        expect(redis).to receive(:hmget).exactly(2).times do |instance_id, *args|
          expect(instances).to include(instance_id)
          result = []
          args.map(&:to_sym).each do |arg|
            expect(instances[instance_id]).to include(arg)
            result << instances[instance_id][arg].to_s
          end
          result
        end
        result = described_class.get_app_stats(app)
        expect(result).to eq({
          0 => deep_stringify_keys!({
            state: "RUNNING",
            stats: {
              stat_value_one: "one",
              uptime: "1",
              usage: { disk: "2", mem: "3", cpu: "4" }
            }
          }),
          1 => deep_stringify_keys!({
            state: "STOPPED",
            stats: {
              stat_value_two: "two",
              uptime: "5",
              usage: { disk: "6", mem: "7", cpu: "8" }
            }
          }),
        })
      end

      it "should ignore invalid indices" do
        instances = {
          "droplet:guid:instances:one"   => { index: 0, stats: "{}" },
          "droplet:guid:instances:two"   => { index: 1, stats: "{}" },
        }
        expect(app).to receive(:instances).at_least(:once).and_return(1)
        expect(redis).to receive(:keys)
          .with("droplet:guid:instance:*")
          .and_return(instances.keys)
        expect(redis).to receive(:hmget).exactly(2).times do |instance_id, *args|
          expect(instances).to include(instance_id)
          result = []
          args.map(&:to_sym).each do |arg|
            result << instances[instance_id][arg].to_s
          end
          result
        end
        expect(described_class.get_app_stats(app).keys)
          .to match_array([0])
      end
    end

    describe ".update_stats_for_all_droplets" do
      it "should group instaces by droplet ids" do
        expect(redis)
          .to receive(:keys)
          .with("droplet:*:instance:*")
          .and_return(["droplet:1:instance:1",
                       "droplet:2:instance:1",
                       "droplet:1:instance:2",
                       "droplet:2:instance:2"])
        expected_arguments = { "1" => ["1", "2"], "2" => ["1", "2"] }
        expect(described_class)
          .to receive(:update_stats_for_droplet)
          .exactly(:twice) do |droplet_id, instance_ids|
            expect(expected_arguments).to include(droplet_id)
            expect(instance_ids).to match_array(expected_arguments.delete(droplet_id))
          end
        described_class.update_stats_for_all_droplets
        expect(expected_arguments).to be_empty
      end
    end

    describe ".update_stats_for_droplet" do
      it "should update stats for each instance" do
        response = { response: "response" }
        expect(message_bus)
          .to receive(:request)
          .twice do |subject, request, options, &block|
            expect(subject).to eq("dea.find.droplet")
            expect(request).to include(droplet: "droplet", include_stats: true)
            expect([["one"], ["two"]]).to include(request[:instances])
            expect(options[:timeout]).to be_a(Numeric)
            expect(options[:result_count]).to eq(1)
            block.call response
          end
        expect(described_class)
          .to receive(:update_stats_for_droplet_instance)
          .with(response)
          .exactly(:twice)
        described_class.update_stats_for_droplet "droplet", ["one", "two"]
      end

      it "should handle nats time outs" do
        expect(message_bus)
          .to receive(:request)
          .with("dea.find.droplet", kind_of(Hash), kind_of(Hash))
          .and_yield(timeout: true)
        expect(described_class)
          .not_to receive(:update_stats_for_droplet_instance)
        described_class.update_stats_for_droplet "droplet", ["one"]
      end
    end

    describe ".handle_dea_heartbeat" do
      it "should handle new empty DEAs" do
        expect(redis).to receive(:exists).with("dea:dea_0").and_return(false)
        expect(message_bus).to receive(:request)
          .with("dea.status", nil, anything).and_yield(response: "response")
        expect(StackatoDropletAccountability).to receive(:handle_dea_status)
          .with(response: "response")
        StackatoDropletAccountability
          .handle_dea_heartbeat(deep_stringify_keys!(dea: "dea_0", droplets: []))
      end

      it "should ignore redis connection errors" do
        expect(redis).to receive(:exists).and_raise Redis::BaseConnectionError
        described_class
          .handle_dea_heartbeat(deep_stringify_keys!(dea: "dea_0", droplets: []))
      end

      it "should ignore redis connection errors when updating existing dea instances" do
        expect(redis).to receive(:exists).with("dea:dea_0").and_return(true)
        expect(redis)
          .to receive(:expire)
          .with("dea:dea_0", kind_of(Numeric))
          .and_raise Redis::BaseConnectionError
        described_class
          .handle_dea_heartbeat(deep_stringify_keys!(dea: "dea_0", droplets: []))
      end

      context "when successfully updating existin deas" do
        before do
          expect(redis).to receive(:exists).with("dea:dea_0").and_return(true)
          expect(redis).to receive(:expire).with("dea:dea_0", kind_of(Numeric))
        end

        it "should update existing dea instances" do
          described_class
            .handle_dea_heartbeat(deep_stringify_keys!(dea: "dea_0", droplets: []))
        end

        it "should handle droplets" do
          instances = {
            "drop-1" => {
              "inst-1" => { state: "RUNNING",  index: 0, version: "v0" },
              "inst-2" => { state: "DOWN",     index: 1, version: "v1" },
            },
            "drop-2" => {
              "inst-1" => { state: "FLAPPING", index: 0, version: " " },
              "inst-2" => { state: "DOWN",     index: 1, version: "!" },
            }
          }
          droplets = []
          instances.each_key do |droplet_id|
            instances[droplet_id].each_pair do |instance_id, instance_data|
              droplets << instance_data.merge({
                droplet: droplet_id,
                instance: instance_id,
              })
            end
          end

          active_keys = []
          expect(redis)
            .to receive(:multi)
            .exactly(droplets.length).times do |&block|
              block.call
              active_keys.shift
              expect(active_keys).to be_empty
            end
          expect(redis)
            .to receive(:hmset)
            .exactly(droplets.length).times do |key, args|
            _, droplet_id, _, instance_id = key.split(":")
            expect(instances).to include(droplet_id)
            expect(instances[droplet_id]).to include(instance_id)
            instance_data = instances[droplet_id].delete(instance_id)
            instance_data[:dea] = "dea_0"
            expect(Hash[*args]).to eq(instance_data.stringify_keys)
            active_keys << key
          end
          expect(redis)
            .to receive(:expire)
            .exactly(droplets.length).times do |key, expiry|
              expect(key).to eq(active_keys.first)
            end
          described_class
            .handle_dea_heartbeat(deep_stringify_keys!(
              dea: "dea_0", droplets: droplets))
          instances.delete_if { |_, v| v.empty? }
          expect(instances).to be_empty
        end
      end
    end

    describe ".handle_dea_status" do
      it "should ignore invalid messages" do
        expect(redis).not_to receive(:hmset)
        expect(redis).not_to receive(:expire)
        described_class.handle_dea_status(timeout: true)
      end

      it "should update status" do
        allow(redis).to receive(:multi).and_yield
        expect(redis).to receive(:hmset).with(
          "dea:dea_0", "ip", "192.0.2.1", "version", "0.1")
        expect(redis).to receive(:expire).with("dea:dea_0", kind_of(Numeric))
        StackatoDropletAccountability.handle_dea_status({
          id: "dea_0", ip: "192.0.2.1", version: "0.1"}.stringify_keys)
      end

      it "should ignore redis connection errors" do
        expect(redis).to receive(:multi).and_yield
        expect(redis).to receive(:hmset).and_raise Redis::BaseConnectionError
        expect {
          StackatoDropletAccountability.handle_dea_status({
            id: "dea_0", ip: "192.0.2.1", version: "0.1"}.stringify_keys)
        }.not_to raise_error
      end
    end

    describe ".update_stats_for_droplet_instance" do
      let (:droplet_data) do
        { dea: "dea_0", droplet: "droplet_0", instance: "0" }
      end

      let (:stats) do
        { uptime: 10, mem_quota: 20 }
      end

      let (:usage) do
        { mem: 11, disk: 12, cpu: 57 }
      end

      subject do
        StackatoDropletAccountability.method(:update_stats_for_droplet_instance)
      end

      it "should ignore instances with no stats" do
        expect(redis).not_to receive(:set)
        expect(redis).not_to receive(:hmset)
        expect(redis).not_to receive(:expire)
        subject.call(deep_stringify_keys!(droplet_data.dup))
      end

      it "should ignore instances with no usage" do
        expect(redis).not_to receive(:set)
        expect(redis).not_to receive(:hmset)
        expect(redis).not_to receive(:expire)
        subject.call(deep_stringify_keys!(droplet_data.merge(stats: stats)))
      end

      it "should update instance information" do
        data = droplet_data.merge(stats: stats.merge(usage: usage)).deep_dup
        expect(redis).to receive(:multi).at_least(:once).and_yield
        expect(redis).to receive(:set) do |key, value|
          expect(key).to eq("dea:dea_0:instances:0")
          expect(value).to eq("11:20")
        end
        expect(redis).to receive(:expire)
          .with("dea:dea_0:instances:0", kind_of(Numeric))
          .ordered
        expect(redis).to receive(:hmset) do |key, *args|
          expect(key).to eq("droplet:droplet_0:instance:0")
          expect(Hash[*args].symbolize_keys).to eq(
            stats: stats.reject{|k| [:uptime, :usage].include?(k)}.to_json,
            uptime: stats[:uptime],
            mem: usage[:mem],
            disk: usage[:disk],
            cpu: usage[:cpu],
            dea: "dea_0")
        end
        expect(redis).to receive(:expire)
          .with("droplet:droplet_0:instance:0", kind_of(Numeric))
          .ordered
        subject.call(deep_stringify_keys!(data))
      end
    end
  end
end
