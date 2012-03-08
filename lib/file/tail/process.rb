class File
  # This module can be included in your own File subclasses or used to extend
  # files you want to tail.
  module Tail
    class TailableProcess  < File::Tail::Tailable

      attr_accessor :_command
      attr_reader :_process

      def initialize(command = nil)
        super()
        if command
          @_command = command
          self.reopen_tailable
        end
      end
      # Taialble process should never have a EOF
      # unless they are no longer tailable
      def handle_EOFError
        # Attempt to reopen
        raise ReopenException
      end

      # Ignore the mode
      def reopen_tailable(mode = 'dummy')
        @_process = IO.popen(@_command) if @_command
      end
      def readline
        self._process.readline
      end
      # Used for testing purposes
      def kill_inner
        return if !self._process
        killable = self._process.pid
        $stdout.flush
        begin
          ::Process.kill 'INT', killable
          ::Process.kill 'KILL', killable
        rescue Exception => e
          # Already killed ? Fine.
        end
      end
      def close
        return if !self._process
        # We have to do that to stop the IO
        self.kill_inner
        begin
          self._process.close
        rescue Exception => e
          # Ignore
        end
      end
    end
  end # module Tail
end # class File