# frozen_string_literal: true

require "spec_helper"

RSpec.describe SidekiqUniqueJobs::Logging do
  let(:logger)  { SidekiqUniqueJobs.logger }
  let(:message) { "A log message" }
  let(:level)   { nil }
  let(:item)    { { "lock" => "until_executed", "unique_digest" => "abcdef" } }

  before do
    allow(logger).to receive(level)
  end

  include described_class

  describe "#log_debug" do
    let(:level) { :debug }

    it "delegates to logger.debug" do
      expect(log_debug(message)).to be_nil
      expect(logger).to have_received(level).with(message)
    end
  end

  describe "#log_info" do
    let(:level) { :info }

    it "delegates to logger.info" do
      expect(log_info(message)).to be_nil
      expect(logger).to have_received(level).with(message)
    end
  end

  describe "#log_warn" do
    let(:level) { :warn }

    it "delegates to logger.warn" do
      expect(log_warn(message)).to be_nil
      expect(logger).to have_received(level).with(message)
    end
  end

  describe "#log_error" do
    let(:level) { :error }

    it "delegates to logger.error" do
      expect(log_error(message)).to be_nil
      expect(logger).to have_received(level).with(message)
    end
  end

  describe "#log_fatal" do
    let(:level) { :fatal }

    it "delegates to logger.fatal" do
      expect(log_fatal(message)).to be_nil
      expect(logger).to have_received(level).with(message)
    end
  end

  describe "#logging_context" do
    let(:level)   { :error }

    it { expect { logging_context }.to raise_error(NotImplementedError) }
  end

  describe "#with_configured_loggers_context" do
    let(:level) { :warn }

    include SidekiqUniqueJobs::Logging::Middleware

    context "when Sidekiq::Logging is defined" do
      before do
        if defined?(Sidekiq::Logging)
          @keep_constant = true
        else
          @keep_constant = false
          require "sidekiq/logging"
        end

        allow(logger).to receive(:respond_to?).with(:with_context).and_return(false)
        allow(Sidekiq::Logging).to receive(:with_context).and_call_original
      end

      after do
        Sidekiq.send(:remove_const, "Logging") unless @keep_constant # rubocop:disable RSpec/InstanceVariable
      end

      it "sets up a logging context" do
        with_configured_loggers_context do
          log_warn("TOODELOO")
        end

        expect(logger).to have_received(:warn).with("TOODELOO")
      end
    end

    context "when logger does not support context" do
      let(:logger) { Logger.new("/dev/null") }

      before do
        allow(logger).to receive(:respond_to?).with(:with_context).and_return(false)
        hide_const("Sidekiq::Logging")
      end

      it "logs a warning" do
        with_configured_loggers_context {}

        expect(logger).to have_received(:warn).with(
          "Don't know how to create the logging context. Please open a feature request:" \
          " https://github.com/mhenrixon/sidekiq-unique-jobs/issues/new?template=feature_request.md",
        )
      end
    end
  end
end
