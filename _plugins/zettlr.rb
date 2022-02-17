require 'json'
require 'nokogiri'
require 'open3'

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
    module BibInfoFilter
      def bib_info(id)
        site = @context.registers[:site]
        reference = JSON.generate(site.data['bib'][id])

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

    class LiteratureNoteGenerator < Jekyll::Generator
      def initialize(config)
        @config = config['zettlr']
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

      def generate(site)
        bib = nil
        open(@config['bibliography']) do |f|
          bib = JSON.load(f)
        end

        literature_notes = {}
        notes = site.collections['notes']
        notes.docs.each do |note|
          break unless note.data['literature_note']
          id = note.data['slug']
          literature_notes[id] = note
        end

        bib_hash = {}
        bib.each do |entry|
          id = entry['id']
          bib_hash[id] = entry
          note = literature_notes[id]
          if note.nil?
            note = Jekyll::Document.new(
              "#{site.source}/_notes/literatur/#{id}.md",
              {:site => site, :collection => site.collections['notes']})
            notes.docs << note
            note.data['literature_note'] = true
            note.data['slug'] = entry['id']
          end
          populate_data(note.data, entry)
        end
        site.data['bib'] = bib_hash
      end
    end

    def self.add_links_to_literature_notes(page)
      doc = Nokogiri::HTML5(page.content)
      bib_entries = doc.css('.csl-entry')

      bib_entries.each do |entry|
        id = entry.attribute('id').value.match(/^ref-(.*)$/)[1]
        entry.at_css('.csl-left-margin').next= "<div class='lit-note-link'><a class='internal-link' href='/#{id}'>Note</a></div>"
      end
      page.content = doc.to_s
    end

    Jekyll::Hooks.register :documents, :post_convert, &method(:add_links_to_literature_notes)
    Liquid::Template.register_filter(BibInfoFilter)
  end
end
