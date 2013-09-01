require "spec_helper"

module VCAP::CloudController
  describe VCAP::CloudController::JobsController, type: :controller do
    let(:current_user_headers) { admin_headers }
    let(:job) { Delayed::Job.enqueue double(:perform => nil) }
    let(:job_request_id) { job.guid }

    describe "GET /v2/jobs/:guid" do
      subject { get("/v2/jobs/#{job_request_id}", {}, current_user_headers) }

      context "when the job exists" do
        it "returns job" do
          subject
          expect(last_response.status).to eq 200
          expect(decoded_response(symbolize_keys: true)).to eq(
            ::JobPresenter.new(job).to_hash
          )
        end

        it "sets the job guid" do
          subject
          expect(decoded_response(symbolize_keys: true)[:metadata][:guid]).not_to be_nil
        end
      end

      context "when the job doesn't exist" do
        let(:job) { nil }
        let(:job_request_id) { 123 }

        it "returns that job was finished" do
          subject
          expect(last_response.status).to eq 200
          expect(decoded_response(symbolize_keys: true)).to eq(
            ::JobPresenter.new(job).to_hash
          )
        end
      end

      context "when you don't have permissions to the job" do
        let(:current_user_headers) { {} }

        it "returns an error" do
          subject
          expect(last_response.status).to eq 401
        end
      end
    end
  end
end