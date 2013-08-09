#Load all files in processors/
Dir.glob("#{File.expand_path(File.dirname(__FILE__))}/processors/*.rb").each { |f| require f.match(/brakeman\/processors.*/)[0] }
require 'brakeman/tracker'
require 'set'
require 'pathname'

module Brakeman
  #Makes calls to the appropriate processor.
  #
  #The ControllerProcessor, TemplateProcessor, and ModelProcessor will
  #update the Tracker with information about what is parsed.
  class Processor
    include Util

    def initialize(app_tree, options)
      @app_tree = app_tree
      @tracker = Tracker.new(@app_tree, self, options)
    end

    def tracked_events
      @tracker
    end

    #Process configuration file source
    def process_config src
      Brakeman.benchmark :config_processing do
        ConfigProcessor.new(@tracker).process_config src
      end
    end

    #Process Gemfile
    def process_gems src, gem_lock = nil
      Brakeman.benchmark :gem_processing do
        GemProcessor.new(@tracker).process_gems src, gem_lock
      end
    end

    #Process route file source
    def process_routes src
      Brakeman.benchmark :route_processing do
        RoutesProcessor.new(@tracker).process_routes src
      end
    end

    #Process controller source. +file_name+ is used for reporting
    def process_controller src, file_name
      if contains_class? src
        Brakeman.benchmark :controller_processing do
          ControllerProcessor.new(@app_tree, @tracker).process_controller src, file_name
        end
      else
        Brakeman.benchmark :library_processing do
          LibraryProcessor.new(@tracker).process_library src, file_name
        end
      end
    end

    #Process variable aliasing in controller source and save it in the
    #tracker.
    def process_controller_alias name, src, only_method = nil
      ControllerAliasProcessor.new(@app_tree, @tracker, only_method).process_controller name, src
    end

    #Process a model source
    def process_model src, file_name
<<<<<<< HEAD
      result = nil

      Brakeman.benchmark :model_processing do
        result = ModelProcessor.new(@tracker).process_model src, file_name
      end

      Brakeman.benchmark :model_alias_processing do
        AliasProcessor.new(@tracker).process result
      end
=======
      result = ModelProcessor.new(@tracker).process_model src, file_name
      AliasProcessor.new(@tracker).process_all result if result
>>>>>>> master
    end

    #Process either an ERB or HAML template
    def process_template name, src, type, called_from = nil, file_name = nil
<<<<<<< HEAD
      result = nil

      Brakeman.benchmark :template_processing do
        case type
        when :erb
          result = ErbTemplateProcessor.new(@tracker, name, called_from, file_name).process src
        when :haml
          result = HamlTemplateProcessor.new(@tracker, name, called_from, file_name).process src
        when :erubis
          result = ErubisTemplateProcessor.new(@tracker, name, called_from, file_name).process src
        else
          abort "Unknown template type: #{type} (#{name})"
        end
=======
      case type
      when :erb
        result = ErbTemplateProcessor.new(@tracker, name, called_from, file_name).process src
      when :haml
        result = HamlTemplateProcessor.new(@tracker, name, called_from, file_name).process src
      when :erubis
        result = ErubisTemplateProcessor.new(@tracker, name, called_from, file_name).process src
      when :slim
        result = SlimTemplateProcessor.new(@tracker, name, called_from, file_name).process src
      else
        abort "Unknown template type: #{type} (#{name})"
>>>>>>> master
      end

      #Each template which is rendered is stored separately
      #with a new name.
      if called_from
        name = ("#{name}.#{called_from}").to_sym
      end

      @tracker.templates[name][:src] = result
      @tracker.templates[name][:type] = type
    end

    #Process any calls to render() within a template
    def process_template_alias template
      Brakeman.benchmark :template_alias_processing do
        TemplateAliasProcessor.new(@tracker, template).process_safely template[:src]
      end
    end

    #Process source for initializing files
    def process_initializer name, src
      res = nil
      Brakeman.benchmark :initializer_processing do
        res = BaseProcessor.new(@tracker).process src
      end

      Brakeman.benchmark :initializer_alias_processing do
        res = AliasProcessor.new(@tracker).process res
      end

      @tracker.initializers[Pathname.new(name).basename.to_s] = res
    end

    #Process source for a library file
    def process_lib src, file_name
      Brakeman.benchmark :library_processing do
        LibraryProcessor.new(@tracker).process_library src, file_name
      end
    end
  end
end
