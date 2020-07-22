# @package MiGA
# @license Artistic-2.0

require 'miga/cli/action'

class MiGA::Cli::Action::Browse < MiGA::Cli::Action
  def parse_cli
    cli.parse do |opt|
      cli.defaults = { open: true }
      cli.opt_object(opt, [:project])
    end
  end

  def perform
    p = cli.load_project
    say 'Creating project page'
    create_empty_page(p)
    generate_project_page(p)
    say 'Creating dataset pages'
    cli.load_project.each_dataset do |d|
      generate_dataset_page(p, d)
    end
    say 'Creating index pages'
    generate_datasets_index(p)
    say "Open in your browser: #{File.join(p.path, 'index.html')}"
  end

  private

  ##
  # Create an empty page with necessary assets for project +p+
  def create_empty_page(p)
    FileUtils.mkdir_p(browse_file(p, '.'))
    %w[favicon-32.png style.css].each do |i|
      FileUtils.cp(template_file(i), browse_file(p, i))
    end
    write_file(p, 'about.html') do
      build_from_template('about.html', citation: MiGA::MiGA.CITATION)
    end
  end

  ##
  # Create landing page for project +p+
  def generate_project_page(p)
    # Redirect page
    write_file(p, '../index.html') { build_from_template('redirect.html') }

    # Summaries
    summaries = Dir["#{p.path}/*.tsv"].map do |i|
      "<li><a href='file://#{i}'>#{File.basename(i)}</a></li>"
    end.join('')

    # Project index page
    data = {
      project_active: 'active',
      information: format_metadata(p),
      summaries: summaries.empty? ? 'None' : "<ul>#{summaries}</ul>",
      results: format_results(p)
    }
    write_file(p, 'index.html') { build_from_template('index.html', data) }
  end

  ##
  # Create page for dataset +d+ within project +p+
  def generate_dataset_page(p, d)
    data = {
      unmiga_name: d.name.unmiga_name,
      information: format_metadata(d),
      results: format_results(d),
    }
    write_file(p, "d_#{d.name}.html") do
      build_from_template('dataset.html', data)
    end
  end

  ##
  # Create pages for reference and query dataset indexes
  def generate_datasets_index(p)
    data = {
      ref: { type_name: 'Reference', list: '' },
      qry: { type_name: 'Query', list: '' }
    }
    p.each_dataset do |d|
      data[d.ref? ? :ref : :qry][:list] +=
        "<li><a href='d_#{d.name}.html'>#{d.name.unmiga_name}</a></li>"
    end
    data.each do |k, v|
      write_file(p, "#{k}_datasets.html") do
        v[:list] = 'None' if v[:list] == ''
        build_from_template(
          'datasets.html',
          v.merge(:"#{k}_datasets_active" => 'active')
        )
      end
    end
  end

  ##
  # Format +obj+ metadata as a table
  def format_metadata(obj)
    o = '<table class="table table-sm table-responsive">'
    obj.metadata.data.each do |k, v|
      next if k.to_s =~ /^run_/
      case k
      when :plugins, :user
        next
      when :web_assembly_gz
        v = "<a href='#{v}'>#{v[0..50]}...</a>"
      end
      v = v.size if k == :datasets
      o += "<tr><td class='text-right pr-4'><b>#{k.to_s.unmiga_name}</b></td>"
      o += "<td>#{v}</td></tr>"
    end
    o += '</table>'
    o
  end

  ##
  # Format +obj+ results as cards
  def format_results(obj)
    o = '<div class="row">'
    obj.each_result do |key, res|
      links = format_result_links(res)
      stats = format_result_stats(res)
      next unless links || stats
      name = key.to_s.unmiga_name.sub(/^./, &:upcase)
      name.sub!(/(Aai|Ani|Ogs|Cds|Ssu)/, &:upcase)
      name.sub!(/Haai/, 'hAAI')
      name.sub!(/Mytaxa/, 'MyTaxa')
      url_doc = "http://manual.microbial-genomes.org/part5/workflow#"
      url_doc += key.to_s.gsub('_', '-')
      o += <<~CARD
        <div class="col-md-6 mb-4">
          <h3>#{name}</h3>
          <div class='border-left p-3'>
            #{stats}
            #{links}
          </div>
          <div class='border-top p-2 bg-light'>
            <a target=_blank href="#{url_doc}" class='p-2'>Learn more</a>
          </div>
        </div>
      CARD
    end
    o += '</div>'
    o
  end

  def format_result_links(res)
    links = []
    res.each_file do |key, _|
      name = key.to_s.unmiga_name.sub(/^./, &:upcase)
      links << "<a href='file://#{res.file_path(key)}'>#{name}</a><br/>"
    end
    links.empty? ? nil : links.join('')
  end

  def format_result_stats(res)
    return if res.stats.nil? || res.stats.empty?
    res.stats.map do |k, v|
      v = [v, ''] unless v.is_a? Array
      v[0] = ('%.3g' % v[0]) if v[0].is_a? Float
      "<b>#{k.to_s.unmiga_name}:</b> #{v[0]}#{v[1]}<br/>"
    end.join('') + '<br/>'
  end

  ##
  # Write +file+ within the browse folder of project +p+ using the passed
  # block output as content
  def write_file(p, file)
    File.open(browse_file(p, file), 'w') { |fh| fh.print yield }
  end

  ##
  # Use a +template+ file to generate content with a hash of +data+ over the
  # layout page if +layout+ is true
  def build_from_template(template, data = {}, layout = true)
    cont = File.read(template_file(template)).miga_variables(data)
    return cont unless layout

    build_from_template(
      'layout.html',
      data.merge({ content: cont, project_name: cli.load_project.name }),
      false
    )
  end

  ##
  # Path to the template browse file
  def template_file(file)
    File.join(
      MiGA::MiGA.root_path,
      'lib', 'miga', 'cli', 'action', 'browse', file
    )
  end

  ##
  # Path to the browse file in the project
  def browse_file(p, file)
    File.join(p.path, 'browse', file)
  end

end
