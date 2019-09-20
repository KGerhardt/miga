# @package MiGA
# @license Artistic-2.0

require 'miga/project'
require 'optparse'

##
# MiGA Command Line Interface API.
class MiGA::Cli < MiGA::MiGA

  require 'miga/cli/base'
  require 'miga/cli/opt_helper'
  include MiGA::Cli::OptHelper
  require 'miga/cli/action'

  ##
  # Task to execute, a symbol
  attr_accessor :task

  ##
  # The CLI parameters (except the task), and Array of String
  attr_accessor :argv

  ##
  # Action to launch, an object inheriting from MiGA::Cli::Action
  attr_accessor :action

  ##
  # If files are expected after the parameters, a boolean
  attr_accessor :expect_files

  ##
  # Files passed after all other options, if +#expect_files = true+
  attr_accessor :files

  ##
  # If an operation verb preceding all other arguments is to be expected
  attr_accessor :expect_operation

  ##
  # Interactivity with the user is expected
  attr_accessor :interactive

  ##
  # Operation preceding all other options, if +#expect_operation = true+
  attr_accessor :operation

  ##
  # Include common options, a boolean (true by default)
  attr_writer :opt_common

  ##
  # Default values as a Hash
  attr_accessor :defaults

  ##
  # Parsed values as a Hash
  attr_reader :data

  def initialize(argv)
    @data = {}
    @defaults = {verbose: false, tabular: false}
    @opt_common = true
    @objects = {}
    if argv[0].nil? or argv[0].to_s[0] == '-'
      @task = :generic
    else
      @task = argv.shift.to_sym
      @task = @@TASK_ALIAS[task] unless @@TASK_ALIAS[task].nil?
    end
    @argv = argv
    reset_action
  end

  ##
  # Send +par+ to $stdout, ensuring new line at the end
  def puts(*par)
    $stdout.puts(*par)
  end

  ##
  # Send +par+ to $stdout as is
  def print(*par)
    $stdout.print(*par)
  end

  ##
  # Display a table with headers +header+ and contents +values+, both Array
  def table(header, values)
    self.puts MiGA.tabulate(header, values, self[:tabular])
  end

  ##
  # Send +par+ to $stderr (ensuring new line at the end), iff --verbose.
  # Date/time each line.
  def say(*par)
    return unless self[:verbose]
    par.map! { |i| "[#{Time.now}] #{i}" }
    $stderr.puts(*par)
  end

  ##
  # Reports the advance of a task at +step+ (String), the +n+ out of +total+
  # The report goes to $stderr iff --verborse
  def advance(step, n = 0, total = nil)
    return unless self[:verbose]
    adv = total.nil? ? '' : ('%.1f%% (%d/%d)' % [n/total, n, total])
    $stderr.print("[%s] %s %s    \r" % [Time.now, step, adv])
  end

  ##
  # Ask a question +question+ to the user (requires +#interactive = true+)
  # The +default+ is used if the answer is empty
  # The +answers+ are supported values, unless nil
  # If --auto, all questions are anwered with +default+ unless +force+
  def ask_user(question, default = nil, answers = nil, force = false)
    ans = " (#{answers.join(' / ')})" unless answers.nil?
    dft = " [#{default}]" unless default.nil?
    print "#{question}#{ans}#{dft} > "
    if self[:auto] && !force
      puts ''
    else
      y = gets.chomp
    end
    y = default.to_s if y.nil? or y.empty?
    unless answers.nil? or answers.map(&:to_s).include?(y)
      warn "Answer not recognized: '#{y}'"
      return ask_user(question, default, answers, force)
    end
    y
  end

  ##
  # Set default values in the Hash +hsh+
  def defaults=(hsh)
    hsh.each{ |k,v| @defaults[k] = v }
  end

  ##
  # Access parsed data
  def [](k)
    k = k.to_sym
    @data[k].nil? ? @defaults[k] : @data[k]
  end

  ##
  # Set parsed data
  def []=(k, v)
    @data[k.to_sym] = v
  end

  ##
  # Redefine #action based on #task
  def reset_action
    @action = nil
    if @@EXECS.include? task
      @action = Action.load(task, self)
    else
      warn "No action set for #{task}"
    end
  end

  ##
  # Perform the task requested (see #task)
  def launch
    begin
      raise "See `miga -h`" if action.nil?
      action.launch
    rescue => err
      $stderr.puts "Exception: #{err}"
      $stderr.puts ''
      err.backtrace.each { |l| $stderr.puts "DEBUG: #{l}" }
      err
    end
  end

  ##
  # Parse the #argv parameters
  def parse(&fun)
    if expect_operation
      @operation = @argv.shift unless argv.first =~ /^-/
    end
    OptionParser.new do |opt|
      banner(opt)
      fun[opt]
      opt_common(opt)
    end.parse!(@argv)
    if expect_files
      @files = argv
    end
  end

  ##
  # Send MiGA's banner to OptionParser +opt+
  def banner(opt)
    usage = "Usage: miga #{action.name}"
    usage += ' {operation}' if expect_operation
    usage += ' [options]'
    usage += ' {FILES...}' if expect_files
    opt.banner = "\n#{task_description}\n\n#{usage}\n"
    opt.separator ''
  end

  ##
  # Ensure that these parameters have been passed to the CLI, as defined by
  # +par+, a Hash with object names as keys and parameter flag as values.
  # If missing, raise an error with message +msg+
  def ensure_par(req, msg = '%<name>s is mandatory: please provide %<flag>s')
    req.each do |k,v|
      raise (msg % {name: k, flag: v}) if self[k].nil?
    end
  end

  ##
  # Ensure that "type" is passed and valid for the given +klass+
  def ensure_type(klass)
    ensure_par(type: '-t')
    if klass.KNOWN_TYPES[self[:type]].nil?
      raise "Unrecognized type: #{self[:type]}"
    end
  end

  ##
  # Get the project defined in the CLI by parameter +name+ and +flag+
  def load_project(name = :project, flag = '-P')
    return @objects[name] unless @objects[name].nil?
    ensure_par(name => flag)
    say "Loading project: #{self[name]}"
    @objects[name] = Project.load(self[name])
    raise "Cannot load project: #{self[name]}" if @objects[name].nil?
    @objects[name]
  end

  ##
  # Load the dataset defined in the CLI
  # If +silent=true+, it allows failures silently
  def load_dataset(silent = false)
    return @objects[:dataset] unless @objects[:dataset].nil?
    ensure_par(dataset: '-D')
    @objects[:dataset] = load_project.dataset(self[:dataset])
    if !silent && @objects[:dataset].nil?
      raise "Cannot load dataset: #{self[:dataset]}"
    end
    return @objects[:dataset]
  end

  ##
  # Load an a project or (if defined) a dataset
  def load_project_or_dataset
    self[:dataset].nil? ? load_project : load_dataset
  end

  ##
  # Load and filter a list of datasets as requested in the CLI
  # If +silent=true+, it allows failures silently
  def load_and_filter_datasets(silent = false)
    return @objects[:filtered_datasets] unless @objects[:filtered_datasets].nil?
    say 'Listing datasets'
    ds = self[:dataset].nil? ?
      load_project.datasets : [load_dataset(silent)].compact
    ds.select! { |d| d.is_ref? == self[:ref] } unless self[:ref].nil?
    ds.select! { |d| d.is_active? == self[:active] } unless self[:active].nil?
    ds.select! do |d|
      self[:multi] ? d.is_multi? : d.is_nonmulti?
    end unless self[:multi].nil?
    ds.select! do |d|
      (not d.metadata[:tax].nil?) && d.metadata[:tax].in?(self[:taxonomy])
    end unless self[:taxonomy].nil?
    ds = ds.values_at(self[:dataset_k]-1) unless self[:dataset_k].nil?
    @objects[:filtered_datasets] = ds
  end

  def load_result
    return @objects[:result] unless @objects[:result].nil?
    ensure_par(result: '-r')
    obj = load_project_or_dataset
    if obj.class.RESULT_DIRS[self[:result]].nil?
      klass = obj.class.to_s.gsub(/.*::/,'')
      raise "Unsupported result for #{klass}: #{self[:result]}"
    end
    r = obj.add_result(self[:result], false)
    raise "Cannot load result: #{self[:result]}" if r.nil?
    @objects[:result] = r
  end

  def add_metadata(obj, cli = self)
    cli[:metadata].split(',').each do |pair|
      (k,v) = pair.split('=')
      case v
        when 'true';  v = true
        when 'false'; v = false
        when 'nil';   v = nil
      end
      if k == '_step'
        obj.metadata["_try_#{v}"] ||= 0
        obj.metadata["_try_#{v}"]  += 1
      end
      obj.metadata[k] = v
    end unless cli[:metadata].nil?
    [:type, :name, :user, :description, :comments].each do |k|
      obj.metadata[k] = cli[k] unless cli[k].nil?
    end
    obj
  end

  ##
  # Task description
  def task_description
    @@TASK_DESC[task]
  end
end
