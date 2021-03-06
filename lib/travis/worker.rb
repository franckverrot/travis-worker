require "travis/worker/version"

require 'resque'
require 'resque/heartbeat'
require 'hashie'
require 'travis/worker/core_ext/ruby/hash/deep_symboliz_keys'

module Travis
  module Worker
    autoload :Job,      'travis/worker/job'
    autoload :Reporter, 'travis/worker/reporter'
    autoload :Shell,    'travis/worker/shell'
    autoload :Worker,   'travis/worker'

    class << self
      def perform(payload)
        Worker.perform(payload)
      end
    end

    # Main worker dispatcher class that get's instantiated by Resque. Once we get rid of
    # Resque this class can take over the responsibility of popping jobs from the queue.
    #
    # The Worker instantiates jobs (currently based on the payload, should be based on
    # the queue) and runs them.
    class Worker
      autoload :Config, 'travis/worker/config'

      class << self
        attr_writer :shell

        def init
          Resque.redis = ENV['REDIS_URL'] = Travis::Worker::Worker.config.redis.url
        end

        def perform(payload)
          new(payload).work!
        end

        def config
          @config ||= Config.new
        end

        def shell
          @shell ||= Travis::Worker::Shell::Session.new(vm, vagrant.config.ssh)
        end

        def name
          @name ||= "#{hostname}:#{vm.name}"
        end

        def hostname
          @hostname ||= `hostname`.chomp
        end

        def vm
          @vm ||= vagrant.vms[(ENV['VM'] || '').to_sym] || raise("could not find vm #{ENV['VM'].inspect}")
        end

        def vagrant
          @vagrant ||= begin
            require 'vagrant'
            Vagrant::Environment.new.load!
          end
        end
      end

      attr_reader :payload, :job, :reporter

      def initialize(payload)
        @payload  = payload.deep_symbolize_keys
        @job      = job_type.new(payload)
        @reporter = Reporter::Http.new(job.build)
        job.observers << reporter
      end

      def shell
        self.class.shell
      end

      def work!
        reporter.deliver_messages!
        job.work!
        sleep(0.1) until reporter.finished?
      end

      def job_type
        payload.key?(:build) && payload[:build].key?(:config) ? Job::Build : Job::Config
      end
    end
  end # Worker
end # Travis
