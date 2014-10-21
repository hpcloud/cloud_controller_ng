require 'stackato/spec_helper'
require 'spec_helper'
require 'cloud_controller/stackato/monitor'
require 'stringio'

module VCAP::CloudController::Stackato
  describe Monitor do
    let(:logger) { double(Steno::Logger) }

    subject(:monitor) { Monitor.new }

    before do
      allow(Steno).to receive(:logger).and_return(logger)
    end

    describe '#start' do

      before do
        allow(Clockwork).to receive(:every).and_yield('dummy.scheduled.job')
        allow(Clockwork).to receive(:run)
        allow(monitor).to receive(:check_cc_memory_usage).and_return(nil)
        allow(logger).to receive(:info) # started monitoring message
        monitor.start
      end

      it 'runs Clockwork' do
        expect(Clockwork).to have_received(:run)
      end

      it 'schedules a monitoring job' do
        expect(Clockwork).to have_received(:every).with(1.hour, 'cc.monitor.job')
      end
    end

    describe '#vmsize_limit' do
      it 'should have a default value' do
        expect(Kato::Config).to receive(:get).with('cloud_controller_ng', 'resource_monitoring/max_vm_size').and_return(nil)
        expect(monitor.vmsize_limit).to be_a Integer
      end

      it 'should be configurable' do
        expect(Kato::Config).to receive(:get).with('cloud_controller_ng', 'resource_monitoring/max_vm_size').and_return(1000)
        expect(monitor.vmsize_limit).to be 1000
      end
    end

    describe '#rss_limit' do
      it 'should have a default value' do
        expect(Kato::Config).to receive(:get).with('cloud_controller_ng', 'resource_monitoring/max_rss_size').and_return(nil)
        expect(monitor.rss_limit).to be_a Integer
      end

      it 'should be configurable' do
        expect(Kato::Config).to receive(:get).with('cloud_controller_ng', 'resource_monitoring/max_rss_size').and_return(1000)
        expect(monitor.rss_limit).to be 1000
      end
    end

    describe '#get_threshold_ratio' do
      it 'should have a default value' do
        expect(Kato::Config).to receive(:get).with('cloud_controller_ng', 'resource_monitoring/threshold_ratio').and_return(nil)
        expect(monitor.get_threshold_ratio).to be_between(0.0, 1.0).inclusive
      end

      it 'should be configurable' do
        expect(Kato::Config).to receive(:get).with('cloud_controller_ng', 'resource_monitoring/threshold_ratio').and_return(0.5)
        expect(monitor.get_threshold_ratio).to eq 0.5
      end

      it 'should fall back to default values when set too large' do
        expect(Kato::Config).to receive(:get).with('cloud_controller_ng', 'resource_monitoring/threshold_ratio').and_return(1000)
        expect(Kato::Config).to receive(:set).with('cloud_controller_ng', 'resource_monitoring/threshold_ratio', instance_of(Float))
        expect(logger).to receive(:warn)
        expect(monitor.get_threshold_ratio).to be_between(0.0, 1.0).inclusive
      end


      it 'should fall back to default values when set too small' do
        expect(Kato::Config).to receive(:get).with('cloud_controller_ng', 'resource_monitoring/threshold_ratio').and_return(-1000)
        expect(Kato::Config).to receive(:set).with('cloud_controller_ng', 'resource_monitoring/threshold_ratio', instance_of(Float))
        expect(logger).to receive(:warn)
        expect(monitor.get_threshold_ratio).to be_between(0.0, 1.0).inclusive
      end
    end

    describe '#check_cc_memory_usage' do
      let(:process_controller) { double(Kato::NodeProcessController.new('0')) }

      before do
        expect(Kato::Local::Node).to receive(:get_local_node_id).and_return('0')
        expect(Kato::NodeProcessController).to receive(:new).and_return(process_controller)
      end

      it 'should do nothing if the process controller is not running' do
        expect(process_controller).to receive(:controller_running?).and_return(false)
        expect(process_controller).not_to receive(:process_pid)
        monitor.check_cc_memory_usage
      end

      it 'should do nothing if the process is not running' do
        expect(process_controller).to receive(:controller_running?).and_return(true)
        expect(process_controller).to receive(:process_pid).and_return(0)
        expect(monitor).to receive(:open).with('/proc/0/statm', 'r') do
          raise Errno::ENOENT.new('Filed does not exist')
        end
        allow(logger).to receive(:error)
        monitor.check_cc_memory_usage
      end

      context 'when the process is running' do
        before do
          expect(process_controller).to receive(:controller_running?).and_return(true)
          expect(process_controller).to receive(:process_pid).and_return(0)
          expect(monitor).to receive(:vmsize_limit).at_least(:once).and_return(40960) # 10 pages
          expect(monitor).to receive(:rss_limit).at_least(:once).and_return(40960) # 10 pages
          expect(monitor).to receive(:get_threshold_ratio).at_least(:once).and_return(0.5)
        end

        context 'should restart the cloud_controller' do
          before do
            allow(logger).to receive(:info)
            expect(process_controller).to receive(:restart_process)
          end

          it 'when exceeding vm size' do
            stream = StringIO.new('7 5 other stuff')
            expect(monitor).to receive(:open).with('/proc/0/statm', 'r').and_yield(stream)
            monitor.check_cc_memory_usage
          end

          it 'when exceeding vm size' do
            stream = StringIO.new('5 7 other stuff')
            expect(monitor).to receive(:open).with('/proc/0/statm', 'r').and_yield(stream)
            monitor.check_cc_memory_usage
          end
        end

        it 'should do nothing when both measures are within bounds' do
          stream = StringIO.new('5 5 other stuff')
          expect(monitor).to receive(:open).with('/proc/0/statm', 'r').and_yield(stream)
          allow(logger).to receive(:info)
          monitor.check_cc_memory_usage
        end

      end
    end

  end
end
