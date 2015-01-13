require 'collins_client'
require 'syslog'
require 'retryingfetcher'
require 'promptcli'
require 'facter'
require 'open3'

module Genesis
  module Framework
    module Task
      def self.included base
        base.extend TaskDslMethods
      end

      module TaskDslMethods
        attr_accessor :blocks, :options, :targets, :dependencies, :description

        def description desc
          add_description desc
        end

        def precondition description, &block
          add_block :precondition, description, block
        end

        def init &block
          set_block :init, block
        end

        def condition description, &block
          add_block :condition, description, block
        end

        def run &block
          set_block :run, block
        end

        def rollback &block
          set_block :rollback, block
        end

        def success &block
          set_block :success, block
        end

        def timeout secs
          set_option :timeout, secs
        end

        def retries count
          if count.is_a? Enumerator then
            set_option :retries, count.to_a
          else
            set_option :retries, count.times.to_a
          end
        end

        # register this task as needing to run after the following tasks
        # deps is varargs of TaskClassNames
        def after_tasks *deps
          self.init_defaults
          self.dependencies = self.dependencies + deps.map(&:to_sym)
        end

        # what targets to participate in
        # targets is varargs of target names (i.e. burnin, intake)
        def wanted_by *targets
          self.init_defaults
          self.targets = self.targets + targets
        end

        # description of what this task does
        def add_description desc
          self.init_defaults
          self.description = desc
        end

        def collins
          Genesis::Framework::Utils.collins
        end

        def facter
          # lets cache the facts on first use
          # TODO symbolize these keys?
          # TODO implement method_missing? on this hash for easy access
          Genesis::Framework::Utils.facter
        end

        def run_cmd *cmd, stdin_data: '', return_both_streams: false, return_merged_streams: false
          if return_both_streams && return_merged_streams
            raise "Invalid run_cmd invocation, can's specify both and merged together"
          end

          if return_merged_streams
            output, status = Open3.capture2e(*cmd, stdin_data: stdin_data)
          else
            stdout, stderr, status = Open3.capture3(*cmd, stdin_data: stdin_data)
            if return_both_streams
              output = [stdout, stderr]
            else
              output = stdout
            end
          end

          if status.exitstatus != 0
            log("Run Command failed for '%s' with exit status '%d' and output: %s" % [cmd.to_s, status.exitstatus, output.to_s])
            raise 'run_cmd exited with status: ' + status.exitstatus.to_s
          end

          return output
        end

        def config
          # We are intentionally causing a deep copy here so one task
          # can't pollute another task's config setup
          # TODO: consider possibly patching hash to not allow setting members?
          @config ||= Marshal.load(Marshal.dump(Genesis::Framework::Utils.config_cache))
        end

        def log message
          Genesis::Framework::Utils.log(self.class.name, message)
        end

        def prompt message, seconds=15, default=false
          Genesis::PromptCLI.ask message, seconds, default
        end

        def install provider, *what
          if provider == :rpm
            Kernel.system("yum", "install", "-y", *what)
            if $?.exitstatus != 0
              raise 'yum install exited with status: ' + $?.exitstatus.to_s
            end
          elsif provider == :gem
            # we give a decent try at detecting if the gem is installed before trying to reinstall again
            # if it contains a - (aka you are specifying a specific version or a / (aka you are specifying a path to find it)
            # then we punt on trying to determine if the gem is already installed and just pass it to install anyway
            gems = what.select { |item| item.include?("-") || item.include?("/") || Gem::Dependency.new(item).matching_specs.count == 0 }
            Kernel.system("gem", "install", "--no-ri", "--no-rdoc", *gems)
            if $?.exitstatus != 0
              raise 'gem install exited with status: ' + $?.exitstatus.to_s
            end

            # now need to clear out the Gem cache so we can load it
            Gem.clear_paths

            # Now we require all the gems you asked to be installed
            what.all? { |gem| require gem }
          else
            raise "Unknown install provider: " + provider.to_s
          end
        end

        def fetch what, filename, base_url: ENV['GENESIS_URL']
          filepath = tmp_path(filename)
          Genesis::RetryingFetcher.get(what, base_url) {|data| File.open(filepath, "w", 0755) { |file| file.write data }}
        end

        def tmp_path filename
          Genesis::Framework::Utils.tmp_path(filename, self.class.name)
        end

        #############################################################
        # These methods are private and not part of the exposed DSL.
        # Use at your own risk.
        #############################################################

        def set_block sym, block
          self.init_defaults
          self.blocks[sym] = block
        end

        def add_block sym, description, block
          self.init_defaults
          if self.blocks[sym].has_key?(description)
            raise "Task defines multiple conditions with the same description"
          end
          self.blocks[sym][description] = block
        end

        def set_option sym, option
          self.init_defaults
          self.options[sym] = option
        end

        def init_defaults
          self.blocks ||= { :precondition => {}, :init => nil, :condition => {}, :run => nil, :rollback => nil, :success => nil }
          self.options ||= { :retries => 3.times.to_a, :timeout => 0 }
          self.targets ||= []
          self.dependencies ||= []
          self.description ||= "no description"
        end

      end
    end
  end
end

