require 'net/ssh'
require 'net/ssh/shell'
require 'travis/worker/patches/net_ssh_shell_process'
require 'fileutils'
require 'vagrant'

module Travis
  module Worker
    module Shell
      class Session
        autoload :Helpers, 'travis/worker/shell/helpers'

        include Shell::Helpers
        #
        # API
        #

        # VirtualBox VM instance used by the session
        attr_reader :vm

        # VirtualBox environment ssh configuration
        attr_reader :config

        # Net::SSH session
        # @return [Net::SSH::Connection::Session]
        attr_reader :shell

        # VBoxManage log file path
        # @return [String]
        attr_reader :log

        def initialize(vm, config)
          @vm     = vm
          @config = config
          @shell  = start_shell
          @log    = '/tmp/travis/log/vboxmanage'

          yield(self) if block_given?

          FileUtils.mkdir_p(File.dirname(log))
          FileUtils.touch(log)
        end

        def sandboxed
          begin
            start_sandbox
            yield
          rescue
            output "#{$!.inspect}\n#{$@}"
          ensure
            rollback_sandbox
          end
        end

        def execute(command, options = {})
          command = echoize(command) unless options[:echo] == false
          exec(command) { |p, data| buffer << data } == 0
        rescue
          output "#{$!.inspect}\n#{$@}"
        end

        def evaluate(command)
          result = ''
          status = exec(command) { |p, data| result << data }
          raise("command #{command} failed: #{result}") unless status == 0
          result
        rescue
          output "#{$!.inspect}\n#{$@}"
        end

        def close
          shell.wait!
          shell.close!
          buffer.flush
        end

        def on_output(&block)
          @on_output = block
        end

        #
        # Protected
        #

        protected

          def vm_name
            vm.vm.name
          end

          def start_shell
            puts "starting ssh session to #{config.host}:#{vm.ssh.port} ..."
            Net::SSH.start(config.host, config.username, :port => vm.ssh.port, :keys => [config.private_key_path]).shell.tap do
              puts 'done.'
            end
          end

          def output(string)
            puts string
            buffer << string
          end

          def buffer
            @buffer ||= Buffer.new do |string|
              @on_output.call(string) if @on_output
            end
          end

          def exec(command, &on_output)
            status = nil
            shell.execute(command) do |process|
              process.on_output(&on_output)
              process.on_finish { |p| status = p.exit_status }
            end
            shell.session.loop { status.nil? }
            status
          end

          def start_sandbox
            puts '[vbox] creating vbox snapshot ...'
            vbox_manage "snapshot '#{vm_name}' take '#{vm_name}-sandbox'"
            puts '[vbox] done.'
          end

          def rollback_sandbox
            puts '[vbox] rolling back to vbox snapshot ...'
            vbox_manage "controlvm '#{vm_name}' poweroff"
            vbox_manage "snapshot '#{vm_name}' restorecurrent"
            delete_snapshots
            vbox_manage "startvm --type headless '#{vm_name}'"
            puts '[vbox] done.'
          rescue
            puts $!.inspect, $@
          end

          def delete_snapshots
            snapshots.reverse.each do |snapshot|
              vbox_manage "snapshot '#{vm_name}' delete '#{snapshot}'"
            end
          end

          def vbox_manage(cmd)
            cmd = "VBoxManage #{cmd}"
            puts "[vbox] #{cmd}"
            result = system(cmd, :out => log, :err => log)
            raise "[vbox] #{cmd} failed. See #{log} for more information." unless result
          end

          def snapshots
            info = `vboxmanage showvminfo #{vm_name} --details`
            info.split(/^Snapshots\s*/).last.split("\n").map { |line| line =~ /\(UUID: ([^\)]*)\)/ and $1 }.compact
          end
      end # Session
    end # Shell
  end # Worker
end # Travis
