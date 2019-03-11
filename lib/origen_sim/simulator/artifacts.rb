module OrigenSim
  module Artifacts
    class Artifacts
      include Origen::Componentable

      # Disable accessors on the simulator. Artifact retrieval must use simulator.artifact[name]
      COMPONENTABLE_ADDS_ACCESSORS = false

      # Clean up the names a bit. Componentable assumes the class name is the singleton name, but we're doing the opposite here.
      COMPONENTABLE_SINGLETON_NAME = 'artifact'
      COMPONENTABLE_PLURAL_NAME = 'artifacts'

      def initialize
        # Don't need the full extent of Origen::Mdoel, so we'll just init the includer class directly.
        Origen::Componentable.init_includer_class(self)
      end

      # Force the class to be an OrigenSim::Artifacts::Artifact
      def add(name, options = {}, &block)
        instances = _split_by_instances(name, options, &block)
        return_instances = []
        instances.each do |n, opts|
          opts[:class_name] = OrigenSim::Artifacts::Artifact
          return_instances << _add(n, opts)
        end

        return_instances.size == 1 ? return_instances.first : return_instances
      end

      def populate
        artifacts.each do |name, artifact|
          Origen.log.info "Populating artifact: #{artifact.target}"
          Origen.log.info "                 to: #{artifact.run_target}"
          artifact.populate
        end
        true
      end

      def clean
        artifacts.each do |name, artifact|
          Origen.log.info "Cleaning artifact: #{artifact.run_target}"
          artifact.clean
        end
        true
      end
    end

    class Artifact
      attr_reader :name
      attr_reader :parent

      def initialize(options)
        @name = options.delete(:name)
        @parent = options.delete(:parent)
        @options = options
      end

      def target
        Pathname(@options[:target] || parent.artifact_dir)
      end

      def run_target
        run_target = Pathname(@options[:run_target] || parent.artifact_run_dir)
        if run_target.absolute?
          run_target.join(target.basename)
        else
          parent.artifact_run_dir.join(run_target).join(target.basename)
        end
      end

      def populate_method
        @options[:populate_method] || parent.artifact_populate_method
      end
      alias_method :pop_method, :populate_method

      def populate
        unless Dir.exist?(run_target.dirname)
          FileUtils.mkdir_p(run_target.dirname)
        end

        if populate_method == :symlink
          File.symlink(target, run_target)
        elsif populate_method == :copy
          FileUtils.cp(target, run_target)
        else
          Origen.app.fail! "Cannot populate artifact :#{name} with populate method #{populate_method}!"
        end
      end

      def clean
        if File.exist?(run_target)
          if File.symlink?(run_target)
            File.unlink(run_target)
          else
            FileUtils.rm_r(run_target)
          end
        end
      end

      def reconfigure(options)
        @options = options
      end
    end
  end
end
