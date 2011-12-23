require 'rubygems'
begin
  #Load our own version of ruby_parser :'(
  require 'ruby_parser/ruby_parser.rb'

  require 'haml'
  require 'sass'
  require 'erb'
  require 'erubis'
  require 'brakeman/processor'
rescue LoadError => e
  $stderr.puts e.message
  $stderr.puts "Please install the appropriate dependency."
  exit
end

#Erubis processor which ignores any output which is plain text.
class Brakeman::ScannerErubis < Erubis::Eruby
  include Erubis::NoTextEnhancer
end

class Brakeman::ErubisEscape < Brakeman::ScannerErubis
  include Erubis::EscapeEnhancer
end

#Scans the Rails application.
class Brakeman::Scanner
  attr_reader :options

  RUBY_1_9 = !!(RUBY_VERSION =~ /^1\.9/)

  #Pass in path to the root of the Rails application
  def initialize options
    @options = options
    @report_progress = options[:report_progress]
    @path = options[:app_path]
    @app_path = File.join(@path, "app")
    @processor = Brakeman::Processor.new options

    if RUBY_1_9
      @ruby_parser = ::Ruby19Parser
    else
      @ruby_parser = ::Ruby18Parser
    end
  end

  #Returns the Tracker generated from the scan
  def tracker
    @processor.tracked_events
  end

  #Process everything in the Rails application
  def process
    warn "Processing configuration..."
    process_config
    warn "Processing gems..."
    process_gems
    warn "Processing initializers..."
    process_initializers
    warn "Processing libs..."
    process_libs
    warn "Processing routes...        "
    process_routes
    warn "Processing templates...     "
    process_templates
    warn "Processing models...        "
    process_models
    warn "Processing controllers...   "
    process_controllers
    warn "Indexing call sites...      "
    index_call_sites
    tracker
  end

  #Process config/environment.rb and config/gems.rb
  #
  #Stores parsed information in tracker.config
  def process_config
    if options[:rails3]
      process_config_file "application.rb"
      process_config_file "environments/production.rb"
    else
      process_config_file "environment.rb"
      process_config_file "gems.rb"
    end

    if File.exists? "#@path/vendor/plugins/rails_xss" or
      options[:rails3] or options[:escape_html] or
      (File.exists? "#@path/Gemfile" and File.read("#@path/Gemfile").include? "rails_xss")

      tracker.config[:escape_html] = true
      warn "[Notice] Escaping HTML by default"
    end
  end

  def process_config_file file
    if File.exists? "#@path/config/#{file}"
      @processor.process_config(parse_ruby(File.read("#@path/config/#{file}")))
    end

  rescue Exception => e
    warn "[Notice] Error while processing config/#{file}"
    tracker.error e.exception(e.message + "\nwhile processing Gemfile"), e.backtrace
  end

  private :process_config_file

  #Process Gemfile
  def process_gems
    if File.exists? "#@path/Gemfile"
      if File.exists? "#@path/Gemfile.lock"
        @processor.process_gems(parse_ruby(File.read("#@path/Gemfile")), File.read("#@path/Gemfile.lock"))
      else
        @processor.process_gems(parse_ruby(File.read("#@path/Gemfile")))
      end
    end
  rescue Exception => e
    warn "[Notice] Error while processing Gemfile."
    tracker.error e.exception(e.message + "\nWhile processing Gemfile"), e.backtrace
  end

  #Process all the .rb files in config/initializers/
  #
  #Adds parsed information to tracker.initializers
  def process_initializers
    Dir.glob(@path + "/config/initializers/**/*.rb").sort.each do |f|
      begin
        @processor.process_initializer(f, parse_ruby(File.read(f)))
      rescue Racc::ParseError => e
        tracker.error e, "could not parse #{f}. There is probably a typo in the file. Test it with 'ruby_parse #{f}'"
      rescue Exception => e
        tracker.error e.exception(e.message + "\nWhile processing #{f}"), e.backtrace
      end
    end
  end

  #Process all .rb in lib/
  #
  #Adds parsed information to tracker.libs.
  def process_libs
    if options[:skip_libs]
      warn '[Skipping]'
      return
    end

    lib_files = Dir.glob(@path + "/lib/**/*.rb").sort
    total = lib_files.length
    current = 0

    lib_files.each do |f|
      warn "Processing #{f}" if options[:debug]
      if @report_progress
        $stderr.print " #{current}/#{total} files processed\r"
        current += 1
      end

      begin
        @processor.process_lib parse_ruby(File.read(f)), f
      rescue Racc::ParseError => e
        tracker.error e, "could not parse #{f}. There is probably a typo in the file. Test it with 'ruby_parse #{f}'"
      rescue Exception => e
        tracker.error e.exception(e.message + "\nWhile processing #{f}"), e.backtrace
      end
    end
  end

  #Process config/routes.rb
  #
  #Adds parsed information to tracker.routes
  def process_routes
    if File.exists? "#@path/config/routes.rb"
      begin
        @processor.process_routes parse_ruby(File.read("#@path/config/routes.rb"))
      rescue Exception => e
        tracker.error e.exception(e.message + "\nWhile processing routes.rb"), e.backtrace
        warn "[Notice] Error while processing routes - assuming all public controller methods are actions."
        options[:assume_all_routes] = true
      end
    else
      warn "[Notice] No route information found"
    end
  end

  #Process all .rb files in controllers/
  #
  #Adds processed controllers to tracker.controllers
  def process_controllers
    controller_files = Dir.glob(@app_path + "/controllers/**/*.rb").sort
    total = controller_files.length * 2
    current = 0

    controller_files.each do |f|
      warn "Processing #{f}" if options[:debug]
      if @report_progress
        $stderr.print " #{current}/#{total} files processed\r"
        current += 1
      end

      begin
        @processor.process_controller(parse_ruby(File.read(f)), f)
      rescue Racc::ParseError => e
        tracker.error e, "could not parse #{f}. There is probably a typo in the file. Test it with 'ruby_parse #{f}'"
      rescue Exception => e
        tracker.error e.exception(e.message + "\nWhile processing #{f}"), e.backtrace
      end
    end

    current = 0
    total = tracker.controllers.length

    warn "Processing data flow in controllers..."

    tracker.controllers.each do |name, controller|
      if @report_progress
        $stderr.print " #{current}/#{total} controllers processed\r"
        current += 1
      end

      @processor.process_controller_alias controller[:src]
    end
  end

  #Process all views and partials in views/
  #
  #Adds processed views to tracker.views
  def process_templates

    views_path = @app_path + "/views/**/*.{html.erb,html.haml,rhtml,js.erb}"
    $stdout.sync = true
    count = 0

    template_files = Dir.glob(views_path).sort
    total = template_files.length

    template_files.each do |f|
      if @report_progress
        $stderr.print " #{count}/#{total} files processed\r"
        count += 1
      end

      type = f.match(/.*\.(erb|haml|rhtml)$/)[1].to_sym
      type = :erb if type == :rhtml
      name = template_path_to_name f
      text = File.read f

      begin
        if type == :erb
          if tracker.config[:escape_html]
            type = :erubis
            if options[:rails3]
              src = Brakeman::RailsXSSErubis.new(text).src
            else
              src = Brakeman::ErubisEscape.new(text).src
            end
          elsif tracker.config[:erubis]
            type = :erubis
            src = Brakeman::ScannerErubis.new(text).src
          else
            src = ERB.new(text, nil, "-").src
            src.sub!(/^#.*\n/, '') if RUBY_1_9
          end

          parsed = parse_ruby src
        elsif type == :haml
          src = Haml::Engine.new(text,
                                 :escape_html => !!tracker.config[:escape_html]).precompiled
          parsed = parse_ruby src
        else
          tracker.error "Unkown template type in #{f}"
        end

        @processor.process_template(name, parsed, type, nil, f)

      rescue Racc::ParseError => e
        tracker.error e, "could not parse #{f}"
      rescue Haml::Error => e
        tracker.error e, ["While compiling HAML in #{f}"] << e.backtrace
      rescue Exception => e
        tracker.error e.exception(e.message + "\nWhile processing #{f}"), e.backtrace
      end
    end

    total = tracker.templates.length
    count = 0

    warn "Processing data flow in templates..."

    tracker.templates.keys.dup.each do |name|
      if @report_progress
        count += 1
        $stderr.print " #{count}/#{total} templates processed\r"
      end

      @processor.process_template_alias tracker.templates[name]
    end

  end

  #Convert path/filename to view name
  #
  # views/test/something.html.erb -> test/something
  def template_path_to_name path
    names = path.split("/")
    names.last.gsub!(/(\.(html|js)\..*|\.rhtml)$/, '')
    names[(names.index("views") + 1)..-1].join("/").to_sym
  end

  #Process all the .rb files in models/
  #
  #Adds the processed models to tracker.models
  def process_models
    model_files = Dir.glob(@app_path + "/models/*.rb").sort

    total = model_files.length
    current = 0

    model_files.each do |f|
      if @report_progress
        $stderr.print " #{current}/#{total} files processed\r"
        current += 1
      end

      begin
        @processor.process_model(parse_ruby(File.read(f)), f)
      rescue Racc::ParseError => e
        tracker.error e, "could not parse #{f}"
      rescue Exception => e
        tracker.error e.exception(e.message + "\nWhile processing #{f}"), e.backtrace
      end
    end
  end

  def index_call_sites
    tracker.index_call_sites
  end

  def parse_ruby input
    @ruby_parser.new.parse input
  end
end

#This is from Rails 3 version of the Erubis handler
class Brakeman::RailsXSSErubis < ::Erubis::Eruby

  def add_preamble(src)
    # src << "_buf = ActionView::SafeBuffer.new;\n"
  end

  def add_text(src, text)
    if text == "\n"
      src << "\n"
    elsif text.include? "\n"
      lines = text.split("\n")
      if text.match(/\n\z/)
        lines.each do |line|
          src << "@output_buffer << ('" << escape_text(line) << "'.html_safe!);\n"
        end
      else
        lines[0..-2].each do |line|
          src << "@output_buffer << ('" << escape_text(line) << "'.html_safe!);\n"
        end

        src << "@output_buffer << ('" << escape_text(lines.last) << "'.html_safe!);"
      end
    else
      src << "@output_buffer << ('" << escape_text(text) << "'.html_safe!);"
    end
  end

  BLOCK_EXPR = /\s+(do|\{)(\s*\|[^|]*\|)?\s*\Z/

  def add_expr_literal(src, code)
    if code =~ BLOCK_EXPR
      src << '@output_buffer.append= ' << code
    else
      src << '@output_buffer.append= (' << code << ');'
    end
  end

  def add_stmt(src, code)
    if code =~ BLOCK_EXPR
      src << '@output_buffer.append_if_string= ' << code
    else
      super
    end
  end

  def add_expr_escaped(src, code)
    if code =~ BLOCK_EXPR
      src << "@output_buffer.safe_append= " << code
    else
      src << "@output_buffer.safe_concat(" << code << ");"
    end
  end

  #Add code to output buffer.
  def add_postamble(src)
    # src << '_buf.to_s'
  end
end

