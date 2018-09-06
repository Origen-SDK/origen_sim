require 'origen'
class OrigenSimApplication < Origen::Application
  attr_accessor :update_sim_captures

  # See http://origen-sdk.org/origen/api/Origen/Application/Configuration.html
  # for a full list of the configuration options available

  # These attributes should never be changed, the duplication here will be resolved in future
  # by condensing these attributes that do similar things
  self.name       = "origen_sim"
  self.namespace  = "OrigenSim"
  config.name     = "origen_sim"
  config.initials = "OrigenSim"
  config.rc_url   = "git@github.com:Origen-SDK/origen_sim.git"
  config.release_externally = true

  # To enable deployment of your documentation to a web server (via the 'origen web'
  # command) fill in these attributes.
  config.web_directory = "git@github.com:Origen-SDK/Origen-SDK.github.io.git/sim"
  config.web_domain = "http://origen-sdk.org/sim"

  # When false Origen will be less strict about checking for some common coding errors,
  # it is recommended that you leave this to true for better feedback and easier debug.
  # This will be the default setting in Origen v3.
  config.strict_errors = true

  config.shared = {
    #:patterns => "pattern",
    #:templates => "templates",
    #:programs => "program",
    command_launcher: "config/shared_commands.rb",
    global_launcher: "config/global_commands.rb",
    origen_guides: "templates/origen_guides",
    origen_guides_index: -> (index) do
      index.section :simulation, heading: "Simulation", after: :program do |section|
        section.page :introduction, heading: "Introduction"
        section.page :howitworks, heading: "How It Works"
        section.page :compiling, heading: "Compiling the DUT"
        section.page :environment, heading: "Environment Setup"
        section.page :patterns, heading: "Simulating Patterns"
        section.page :flows, heading: "Simulating Flows"
        section.page :debugging, heading: "Interactive Debugging"
        section.page :capturing, heading: "Capturing Responses"
      end
    end
  }

  config.remotes = [
    {
      dir: "example_rtl",
      rc_url: 'https://github.com/Origen-SDK/example_rtl.git',
      version: "master",
      development: true
    }
  ]

  # See: http://origen-sdk.org/origen/latest/guides/utilities/lint/
  config.lint_test = {
    # Require the lint tests to pass before allowing a release to proceed
    run_on_tag: true,
    # Auto correct violations where possible whenever 'origen lint' is run
    auto_correct: true, 
    # Limit the testing for large legacy applications
    #level: :easy,
    # Run on these directories/files by default
    #files: ["lib", "config/application.rb"],
  }

  config.semantically_version = true

  # An example of how to set application specific LSF parameters
  #config.lsf.project = "msg.te"
  config.lsf.queue = ENV["ORIGEN_LSF_QUEUE"] if ENV["ORIGEN_LSF_QUEUE"]
  config.lsf.resource = ENV["ORIGEN_LSF_RESOURCE"] if ENV["ORIGEN_LSF_RESOURCE"]

  # An example of how to specify a prefix to add to all generated patterns
  #config.pattern_prefix = "nvm"

  # An example of how to add header comments to all generated patterns
  #config.pattern_header do
  #  cc "This is a pattern created by the example origen application"
  #end

  # By default all generated output will end up in ./output.
  # Here you can specify an alternative directory entirely, or make it dynamic such that
  # the output ends up in a setup specific directory. 
  #config.output_directory do
  #  "#{Origen.root}/output/#{$dut.class}"
  #end

  # Similarly for the reference files, generally you want to setup the reference directory
  # structure to mirror that of your output directory structure.
  #config.reference_directory do
  #  "#{Origen.root}/.ref/#{$dut.class}"
  #end
 
  # This will automatically deploy your documentation after every tag
  #def after_release_email(tag, note, type, selector, options)
  #  command = "origen web compile --remote --api"
  #  Dir.chdir Origen.root do
  #    system command
  #  end
  #end

  # Ensure that all tests pass before allowing a release to continue
  #def validate_release
  #  if !system("origen specs") || !system("origen examples")
  #    puts "Sorry but you can't release with failing tests, please fix them and try again."
  #    exit 1
  #  else
  #    puts "All tests passing, proceeding with release process!"
  #  end
  #end

  # To enabled source-less pattern generation create a class (for example PatternDispatcher)
  # to generate the pattern. This should return false if the requested pattern has been
  # dispatched, otherwise Origen will proceed with looking up a pattern source as normal.
  #def before_pattern_lookup(requested_pattern)
  #  PatternDispatcher.new.dispatch_or_return(requested_pattern)
  #end

  # If you use pattern iterators you may come across the case where you request a pattern
  # like this:
  #   origen g example_pat_b0.atp
  #
  # However it cannot be found by Origen since the pattern name is actually example_pat_bx.atp
  # In the case where the pattern cannot be found Origen will pass the name to this translator
  # if it exists, and here you can make any substitutions to help Origen find the file you 
  # want. In this example any instances of _b\d, where \d means a number, are replaced by
  # _bx.
  #config.pattern_name_translator do |name|
  #  name.gsub(/_b\d/, "_bx")
  #end

end
