require 'spec_helper'

module VCAP::CloudController
  describe Varz do
    let(:threadqueue) { double(EventMachine::Queue, size: 20, num_waiting: 0) }
    let(:resultqueue) { double(EventMachine::Queue, size: 0, num_waiting: 1) }

    before do
      allow(EventMachine).to receive(:connection_count).and_return(123)

      allow(EventMachine).to receive(:instance_variable_get) do |instance_var|
        case instance_var
        when :@threadqueue then threadqueue
        when :@resultqueue then resultqueue
        else raise "Unexpected call: #{instance_var}"
        end
      end
    end

    describe '#setup_updates' do
      before do
        allow(EventMachine).to receive(:add_periodic_timer)
      end

      it 'bumps the number of users and sets periodic timer' do
        expect(VCAP::CloudController::Varz).to receive(:record_user_count).once
        Varz.setup_updates
      end

      it 'bumps the length of cc job queues and sets periodic timer' do
        expect(VCAP::CloudController::Varz).to receive(:update_job_queue_length).once
        Varz.setup_updates
      end

      it 'updates thread count and event machine queues' do
        expect(VCAP::CloudController::Varz).to receive(:update_thread_info).once
        Varz.setup_updates
      end

      context 'when EventMachine periodic_timer tasks are run' do
        before do
          @periodic_timers = []

          allow(EventMachine).to receive(:add_periodic_timer) do |interval, &block|
            @periodic_timers << {
              interval: interval,
              block: block
            }
          end

          Varz.setup_updates
        end

        it 'bumps the number of users and sets periodic timer' do
          expect(VCAP::CloudController::Varz).to receive(:record_user_count).once
          expect(@periodic_timers[0][:interval]).to eq(600)

          @periodic_timers[0][:block].call
        end

        it 'bumps the length of cc job queues and sets periodic timer' do
          expect(VCAP::CloudController::Varz).to receive(:update_job_queue_length).once
          expect(@periodic_timers[1][:interval]).to eq(30)

          @periodic_timers[1][:block].call
        end

        it 'updates thread count and event machine queues' do
          expect(VCAP::CloudController::Varz).to receive(:update_thread_info).once
          expect(@periodic_timers[2][:interval]).to eq(30)

          @periodic_timers[2][:block].call
        end
      end
    end

    describe '#record_user_count' do
      it 'should include the number of users in varz' do
        # We have to use stubbing here because when we run in parallel mode,
        # there might other tests running and create/delete users concurrently.
        VCAP::Component.varz.synchronize do
          VCAP::Component.varz[:cc_user_count] = 0
        end

        allow_any_instance_of(User).to receive(:cache_username)
        4.times{ User.create(guid: SecureRandom.uuid) }
        Varz.record_user_count

        VCAP::Component.varz.synchronize do
          expected_user_count = User.count
          expect(VCAP::Component.varz[:cc_user_count]).to eql expected_user_count
        end
      end
    end

    describe '#update_job_queue_length' do
      it 'should include the length of the delayed job queue' do
        VCAP::Component.varz.synchronize do
          VCAP::Component.varz[:cc_job_queue_length] = 0
        end

        Delayed::Job.enqueue(Jobs::Runtime::AppBitsPacker.new('abc', 'def', []), queue: 'cc_local')
        Delayed::Job.enqueue(Jobs::Runtime::AppBitsPacker.new('ghj', 'klm', []), queue: 'cc_local')
        Delayed::Job.enqueue(Jobs::Runtime::AppBitsPacker.new('abc', 'def', []), queue: 'cc_generic')

        Varz.update_job_queue_length

        VCAP::Component.varz.synchronize do
          expect(VCAP::Component.varz[:cc_job_queue_length][:cc_local]).to eq(2)
          expect(VCAP::Component.varz[:cc_job_queue_length][:cc_generic]).to eq(1)
        end
      end

      it 'should find jobs which have not been attempted yet' do
        Delayed::Job.enqueue(Jobs::Runtime::AppBitsPacker.new('abc', 'def', []), queue: 'cc_local')
        Delayed::Job.enqueue(Jobs::Runtime::AppBitsPacker.new('abc', 'def', []), queue: 'cc_generic')

        Varz.update_job_queue_length

        VCAP::Component.varz.synchronize do
          expect(VCAP::Component.varz[:cc_job_queue_length][:cc_local]).to eq(1)
          expect(VCAP::Component.varz[:cc_job_queue_length][:cc_generic]).to eq(1)
        end
      end

      it 'should ignore jobs that have already been attempted' do
        job = Jobs::Runtime::AppBitsPacker.new('abc', 'def', [])
        Delayed::Job.enqueue(job, queue: 'cc_generic', attempts: 1)

        Varz.update_job_queue_length

        VCAP::Component.varz.synchronize do
          expect(VCAP::Component.varz[:cc_job_queue_length]).to eq({})
        end
      end
    end

    describe '#update_thread_info' do
      before do
        Varz.update_thread_info
      end

      it 'should contain EventMachine data' do
        VCAP::Component.varz.synchronize do
          expect(VCAP::Component.varz[:thread_info][:thread_count]).to eq(Thread.list.size)
          expect(VCAP::Component.varz[:thread_info][:event_machine][:connection_count]).to eq(123)
          expect(VCAP::Component.varz[:thread_info][:event_machine][:threadqueue][:size]).to eq(20)
          expect(VCAP::Component.varz[:thread_info][:event_machine][:threadqueue][:num_waiting]).to eq(0)
          expect(VCAP::Component.varz[:thread_info][:event_machine][:resultqueue][:size]).to eq(0)
          expect(VCAP::Component.varz[:thread_info][:event_machine][:resultqueue][:num_waiting]).to eq(1)
        end
      end

      context 'when resultqueue and/or threadqueue is not a queue' do
        let(:resultqueue) { [] }
        let(:threadqueue) { nil }

        it 'does not blow up' do
          VCAP::Component.varz.synchronize do
            expect(VCAP::Component.varz[:thread_info][:event_machine][:resultqueue][:size]).to eq(0)
            expect(VCAP::Component.varz[:thread_info][:event_machine][:resultqueue][:num_waiting]).to eq(0)
            expect(VCAP::Component.varz[:thread_info][:event_machine][:threadqueue][:size]).to eq(0)
            expect(VCAP::Component.varz[:thread_info][:event_machine][:threadqueue][:num_waiting]).to eq(0)
          end
        end
      end
    end

    describe '#update!' do
      it 'calls all update methods' do
        expect(VCAP::CloudController::Varz).to receive(:record_user_count).once
        expect(VCAP::CloudController::Varz).to receive(:update_job_queue_length).once
        expect(VCAP::CloudController::Varz).to receive(:update_thread_info).once
        Varz.update!
      end
    end
  end
end
