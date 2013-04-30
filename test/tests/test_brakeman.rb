require 'tempfile'

class UtilTests < Test::Unit::TestCase
  def setup
    @ruby_parser = RubyParser
  end

  def util
    Class.new.extend Brakeman::Util
  end

  def test_cookies?
    assert util.cookies?(@ruby_parser.new.parse 'cookies[:x][:y][:z]')
  end

  def test_params?
    assert util.params?(@ruby_parser.new.parse 'params[:x][:y][:z]')
  end
end

class BaseCheckTests < Test::Unit::TestCase
  FakeTracker = Struct.new(:config)
  FakeAppTree = Struct.new(:root)

  def setup
    @tracker = FakeTracker.new
    app_tree = FakeAppTree.new
    @check = Brakeman::BaseCheck.new app_tree, @tracker
  end

  def version_between? version, high, low
    @tracker.config = { :rails_version => version }
    @check.send(:version_between?, high, low)
  end

  def test_version_between
    assert version_between?("2.3.8", "2.3.0", "2.3.8")
    assert version_between?("2.3.8", "2.3.0", "2.3.14")
    assert version_between?("2.3.8", "1.0.0", "5.0.0")
  end

  def test_version_not_between
    assert_equal false, version_between?("3.2.1", "2.0.0", "3.0.0")
    assert_equal false, version_between?("3.2.1", "3.0.0", "3.2.0")
    assert_equal false, version_between?("0.0.0", "3.0.0", "3.2.0")
  end

  def test_version_between_longer
    assert_equal false, version_between?("1.0.1.2", "1.0.0", "1.0.1")
  end

  def test_version_between_pre_release
    assert version_between?("3.2.9.rc2", "3.2.5", "4.0.0")
  end
end

class ConfigTests < Test::Unit::TestCase
  def test_quiet_option_from_file
    config = Tempfile.new("config")

    config.write <<-YAML.strip
    ---
    :quiet: true
    YAML

    config.close

    options = {
      :config_file => config.path,
      :app_path => "/tmp" #doesn't need to be real
    }

    final_options = Brakeman.set_options(options)

    config.unlink

    assert final_options[:quiet], "Expected quiet option to be true, but was #{final_options[:quiet]}"
  end

  def test_quiet_option_default
    options = {
      :app_path => "/tmp" #doesn't need to be real
    }

    final_options = Brakeman.set_options(options)

    assert final_options[:quiet], "Expected quiet option to be true, but was #{final_options[:quiet]}"
  end

  def test_quiet_option_with_nil
    options = {
      :quiet => nil,
      :app_path => "/tmp" #doesn't need to be real
    }

    final_options = Brakeman.set_options(options)

    assert_nil final_options[:quiet]
  end
  
  def output_format_tester options, expected_options
    output_formats = Brakeman.get_output_formats(options)
    
    assert_equal expected_options, output_formats
  end
  
  def test_output_format
    output_format_tester({}, [:to_s])
    output_format_tester({:output_format => :html}, [:to_html])
    output_format_tester({:output_format => :to_html}, [:to_html])
    output_format_tester({:output_format => :csv}, [:to_csv])
    output_format_tester({:output_format => :to_csv}, [:to_csv])
    output_format_tester({:output_format => :pdf}, [:to_pdf])
    output_format_tester({:output_format => :to_pdf}, [:to_pdf])
    output_format_tester({:output_format => :json}, [:to_json])
    output_format_tester({:output_format => :to_json}, [:to_json])
    output_format_tester({:output_format => :tabs}, [:to_tabs])
    output_format_tester({:output_format => :to_tabs}, [:to_tabs])
    output_format_tester({:output_format => :others}, [:to_s])
    
    output_format_tester({:output_files => ['xx.html', 'xx.pdf']}, [:to_html, :to_pdf])
    output_format_tester({:output_files => ['xx.pdf', 'xx.json']}, [:to_pdf, :to_json])
    output_format_tester({:output_files => ['xx.json', 'xx.tabs']}, [:to_json, :to_tabs])
    output_format_tester({:output_files => ['xx.tabs', 'xx.csv']}, [:to_tabs, :to_csv])
    output_format_tester({:output_files => ['xx.csv', 'xx.xxx']}, [:to_csv, :to_s])
    output_format_tester({:output_files => ['xx.xx', 'xx.xx']}, [:to_s, :to_s])
    output_format_tester({:output_files => ['xx.html', 'xx.pdf', 'xx.csv', 'xx.tabs', 'xx.json']}, [:to_html, :to_pdf, :to_csv, :to_tabs, :to_json])
  end
end
