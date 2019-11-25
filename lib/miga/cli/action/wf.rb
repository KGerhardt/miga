# @package MiGA
# @license Artistic-2.0

##
# Helper module for workflows
module MiGA::Cli::Action::Wf
  def default_opts_for_wf
    cli.expect_files = true
    cli.defaults = {
      clean: false, regexp: MiGA::Cli.FILE_REGEXP,
      project_type: :genomes, dataset_type: :popgenome,
      ncbi_draft: true }
  end

  def opts_for_wf(opt, files_desc, params = {})
    {
      multi: false, cleanup: true, project_type: false, ncbi: true
    }.each { |k, v| params[k] = v if params[k].nil? }
    opt.on(
      '-o', '--out_dir PATH',
      '(Mandatory) Directory to be created with all output data'
    ) { |v| cli[:outdir] = v }
    opt.separator ''
    opt.separator "    FILES...: #{files_desc}"
    opt.separator ''
    opt.separator 'Workflow Control Options'
    if params[:ncbi]
      opt.on(
        '-T', '--ncbi-taxon STRING',
        'Download all the genomes in NCBI classified as this taxon'
      ) { |v| cli[:ncbi_taxon] = v }
      opt.on(
        '--no-draft',
        'Only download complete genomes, not drafts'
      ) { |v| cli[:ncbi_draft] = v }
    end
    if params[:cleanup]
      opt.on(
        '-c', '--clean',
        'Clean all intermediate files after generating the reports'
      ) { |v| cli[:clean] = v }
    end
    opt.on(
      '-R', '--name-regexp REGEXP', Regexp,
      'Regular expression indicating how to extract the name from the path',
      "By default: '#{cli[:regexp]}'"
    ) { |v| cli[:regexp] = v }
    opt.on(
      '--type STRING',
      "Type of datasets. By default: #{cli[:dataset_type]}",
      'Recognized types:',
      *MiGA::Dataset.KNOWN_TYPES
        .map do |k, v|
          "~ #{k}: #{v[:description]}" unless !params[:multi] && v[:multi]
        end.compact
    ) { |v| cli[:dataset_type] = v.downcase.to_sym }
    if params[:project_type]
      opt.on(
        '--project-type STRING',
        "Type of project. By default: #{cli[:project_type]}",
        'Recognized types:',
        *MiGA::Project.KNOWN_TYPES
          .map do |k, v|
            "~ #{k}: #{v[:description]}" unless !params[:multi] && v[:multi]
          end.compact
      ) { |v| cli[:project_type] = v.downcase.to_sym }
    end
    opt.on(
      '--daemon PATH',
      'Use custom daemon configuration in JSON format',
      'By default: ~/.miga_daemon.json'
    ) { |v| cli[:daemon_json] = v }
    opt.on(
      '-j', '--jobs INT',
      'Number of parallel jobs to execute',
      'By default controlled by the daemon configuration (maxjobs)'
    ) { |v| cli[:jobs] = v.to_i }
    opt.on(
      '-t', '--threads INT',
      'Number of CPUs to use per job',
      'By default controlled by the daemon configuration (ppn)'
    ) { |v| cli[:threads] = v.to_i }
  end

  def opts_for_wf_distances(opt)
    opt.on('--fast', 'Alias to: --aai-p diamond --ani-p fastani') do
      cli[:aai_p] = 'diamond'
      cli[:ani_p] = 'fastani'
    end
    opt.on(
      '--haai-p STRING',
      'hAAI search engine. One of: blast+ (default), blat, diamond, no'
    ) { |v| cli[:haai_p] = v }
    opt.on(
      '--aai-p STRING',
      'AAI search engine. One of: blast+ (default), blat, diamond'
    ) { |v| cli[:aai_p] = v }
    opt.on(
      '--ani-p STRING',
      'ANI search engine. One of: blast+ (default), blat, fastani'
    ) { |v| cli[:ani_p] = v }
  end

  def create_project(stage, p_metadata = {}, d_metadata = {})
    cli.ensure_par(
      outdir: '-o',
      project_type: '--project-type',
      dataset_type: '--dataset-type')
    # Create empty project
    call_cli([
      'new',
      '-P', cli[:outdir],
      '-t', cli[:project_type],
      '-m', p_metadata.map{ |k,v| "#{k}=#{v}" }.join(',')
    ])
    # Download datasets
    call_cli([
      'ncbi_get',
      '-P', cli[:outdir],
      '-T', cli[:ncbi_taxon],
      (cli[:ncbi_draft] ? '--all' : '--complete'),
      '-m', d_metadata.map{ |k,v| "#{k}=#{v}" }.join(',')
    ]) unless cli[:ncbi_taxon].nil?
    # Add datasets
    call_cli([
      'add',
      '-P', cli[:outdir],
      '-t', cli[:dataset_type],
      '-i', stage,
      '-R', cli[:regexp],
      '-m', d_metadata.map{ |k,v| "#{k}=#{v}" }.join(',')
    ] + cli.files) unless cli.files.empty?
    p = MiGA::Project.load(cli[:outdir])
    raise "Impossible to create project: #{cli[:outdir]}" if p.nil?
    [:haai_p, :aai_p, :ani_p].each do |i|
      p.metadata[i] = cli[i] unless cli[i].nil?
    end
    p.save
    p
  end

  def summarize(which = %w[cds assembly essential_genes ssu])
    which.each do |r|
      cli.say "Summary: #{r}"
      call_cli([
        'summary',
        '-P', cli[:outdir],
        '-r', r,
        '-o', File.expand_path("#{r}.tsv", cli[:outdir]),
        '--tab'
      ])
    end
  end

  def cleanup
    return unless cli[:clean]
    cli.say "Cleaning up intermediate files"
    %w[data daemon metadata miga.project.json].each do |f|
      FileUtils.rm_rf(File.expand_path(f, cli[:outdir]))
    end
  end

  def call_cli(cmd)
    cmd << '-v' if cli[:verbose]
    MiGA::Cli.new(cmd.map(&:to_s)).launch
  end

  def run_daemon
    cmd  = ['daemon', 'run', '-P', cli[:outdir], '--shutdown-when-done']
    cmd += ['--json', cli[:daemon_json]] unless cli[:daemon_json].nil?
    cmd += ['--max-jobs', cli[:jobs]] unless cli[:jobs].nil?
    cmd += ['--ppn', cli[:threads]] unless cli[:threads].nil?
    cwd = Dir.pwd
    call_cli cmd
    Dir.chdir(cwd)
  end

end