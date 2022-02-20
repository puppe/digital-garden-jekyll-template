# coding: utf-8
require 'json'
require 'nokogiri'
require 'open3'
require 'set'

module Jekyll
  module Converters
    class Markdown
      class ZettlrPandoc
        def initialize(config)
          @config = config['zettlr']
        end

        def convert(content)
          args = [];
          args << '--from=markdown'
          args << '--to=html5'
          args << '--katex'
          args << '--citeproc'
          args << "--bibliography=#{@config['bibliography']}"
          args << "--csl=#{@config['csl']}"
          command = "pandoc #{args.join(' ')}"

          output = error = exit_status = nil

          Open3.popen3(command) do |stdin, stdout, stderr, wait_thr|
            stdin.puts content
            stdin.close

            output = stdout.read
            error = stderr.read
            exit_status = wait_thr.value
          end

          raise error unless exit_status && exit_status.success?

          output
        end
      end
    end
  end
end

module Jekyll
  module Zettlr
    NOTE_ID_REGEX = '[[:alnum:]\-_+. ]+'
    CITATION_ID_REGEX = '[[:alnum:]\-_+.]+'

    module BibInfoFilter
      def bib_info(id)
        site = @context.registers[:site]
        reference = JSON.generate(Jekyll::Zettlr::Generator.bib(site)[id])

        args = []
        args << "--style=#{site.config['zettlr']['csl']}"
        command = "citeproc #{args.join(' ')}"
        input = "{ \"references\": [ #{reference} ]}"

        output = error = exit_status = nil

        Open3.popen3(command) do |stdin, stdout, stderr, wait_thr|
          stdin.puts input
          stdin.close

          output = stdout.read
          error = stderr.read
          exit_status = wait_thr.value
        end

        raise error unless exit_status && exit_status.success?
        output = JSON.parse(output)

        output['bibliography'][0][1]
      end
    end

    class Generator < Jekyll::Generator
      def initialize(config)
        @config = config['zettlr']
      end

      def generate(site)
        bib = nil
        open(site.config['zettlr']['bibliography']) do |f|
          bib = load_bibliography(f)
        end

        notes = site.collections['notes'].docs
        notes.concat(generate_literature_notes(site, bib))

        id_map = build_id_map(notes)
        graph = build_graph(notes, bib, id_map)

        (site.pages + site.documents).each do |page|
          substitute_wiki_links(page, id_map)
        end

        site.data['zettlr'] = {
          'bib' => bib,
          'id_map' => id_map,
          'graph' => graph
        }
      end

      private def substitute_wiki_links(page, id_map)
        page.content.gsub!(/\[\[(#{NOTE_ID_REGEX})\]\]/) do |match|
          id = $1
          note = id_map[id]
          if note
            "<a class='internal-link note-link' href='#{note.url}'>[◦]</a>"
          else
            <<~HTML.delete("\n")
              <span title='There is no note that matches this link.' class='invalid-link'>
                <span class='invalid-link-brackets'>[[</span>
                #{id}
                <span class='invalid-link-brackets'>]]</span>
              </span>
            HTML
          end
        end
      end

      def self.bib(site)
        site.data['zettlr']['bib']
      end

      def self.id_map(site)
        site.data['zettlr']['id_map']
      end

      def self.graph(site)
        site.data['zettlr']['graph']
      end

      class DirectedGraph
        def initialize()
          @out_edges = {}
          @in_edges = {}
        end

        def add_edge(n1, n2) raise 'Loops are not allowed' if n1 == n2
          raise "Nodes must not be nil" if n1.nil? || n2.nil?
          @out_edges[n1] ||= Set.new
          @in_edges[n2] ||= Set.new
          @out_edges[n1] << n2
          @in_edges[n2] << n1
        end

        def in_edges(node)
          @in_edges[node]
        end

        def out_edges(node)
          @out_edges[node]
        end
      end

      private def build_graph(notes, bib, id_map)
        graph = DirectedGraph.new

        notes.each do |note|
          note_links = note.content.scan(/(?<=\[\[)#{NOTE_ID_REGEX}(?=\]\])/)
          citation_links = note.content.scan(/(?<![[:alnum:]])(?<=@)#{CITATION_ID_REGEX}/)
          citation_links = citation_links.filter { |link| bib.has_key?(link) }
          links = note_links + citation_links
          links.each do |link|
            other_note = id_map[link]
            next if other_note.nil?
            next if note == other_note
            backlinks = other_note.data['backlinks'] ||= []
            backlinks << note
            # We don‘t use this graph yet, but we might write a JSON file
            # in the future.
            graph.add_edge(note, other_note)
          end
        end
      end

      private def populate_data(data, bib_entry)
        # I am not completely sure about the format of 'date-parts'. Until I get
        # around to looking it up, I make my current (probably wrong) assumption
        # explicit.
        unless bib_entry['issued']['date-parts'].length == 1
          raise "Date of bibliography entry #{bib_entry['id']} is not as expected"
        end

        data['title'] ||= bib_entry['title']
        data['date'] ||= bib_entry['issued']['date-parts'][0][0]
        data['bib_id'] ||= bib_entry['id']
        data['bib_entry'] ||= bib_entry
        data['bib_entry_json'] ||= JSON.generate(bib_entry)
      end

      private def generate_literature_notes(site, bib)
        literature_notes = {}
        notes = site.collections['notes'].docs
        notes.each do |note|
          break unless note.data['literature_note']
          id = note.data['slug']
          literature_notes[id] = note
        end

        new_notes = []
        bib.each do |id, entry|
          note = literature_notes[id]
          if note.nil?
            note = Jekyll::Document.new(
              "#{site.source}/_notes/literatur/#{id}.md",
              {:site => site, :collection => site.collections['notes']})
            new_notes << note
            note.content = ''
            note.data['literature_note'] = true
            note.data['slug'] = entry['id']
          end
          populate_data(note.data, entry)
        end

        new_notes
      end

      private def load_bibliography(bibliography_file)
        bib = nil
        bib = JSON.load(bibliography_file)
        bib_hash = {}
        bib.each do |entry|
          id = entry['id']
          bib_hash[id] = entry
        end
        bib_hash
      end

      private def build_id_map(notes)
        id_map = {}
        add_to_map = -> (id, note) {
          other_note = id_map[id]
          if other_note
            raise "The notes #{note.path} and #{other_note.path} share the same " +
                  "identifier #{id}."
          end
          id_map[id] = note
        }

        notes.each do |note|
          name = File.basename(note.basename, File.extname(note.basename))
          add_to_map.call(name, note)
          ids = note.content.scan(/(?<!\[\[)\d{14}/)
          ids.each { |id| add_to_map.call(id, note) }
        end
        id_map
      end
    end

    def self.add_links_to_literature_notes(page)
      fragment = Nokogiri::HTML5::fragment(page.content)
      bib_entries = fragment.css('.csl-entry')

      bib_entries.each do |entry|
        id = entry.attribute('id').value.match(/^ref-(.*)$/)[1]
        entry.at_css('.csl-left-margin').next= "<div class='lit-note-link'><a class='internal-link' href='/#{id}'>Note</a></div>"
      end
      page.content = fragment.to_s
    end

    Jekyll::Hooks.register :documents, :post_convert, &method(:add_links_to_literature_notes)
    Liquid::Template.register_filter(BibInfoFilter)
  end
end
