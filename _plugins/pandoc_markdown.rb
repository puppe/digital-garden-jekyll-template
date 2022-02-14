require 'open3'

module Jekyll
  module Converters
    class Markdown
      class Pandoc
        def initialize(config)
        end

        def convert(content)
          args = [];
          args << '--from=markdown'
          args << '--to=html5'
          args << '--katex'
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
