class IO
  module Tail

    # This is the base class of all exceptions that are raised
    # in IO::Tail.
    class TailException < Exception; end

    # The DeletedException is raised if a file is
    # deleted while tailing it.
    class DeletedException < TailException; end

    # The ReturnException is raised and caught
    # internally to implement "tail -10" behaviour.
    class ReturnException < TailException; end

    # The BreakException is raised if the <code>break_if_eof</code>
    # attribute is set to a true value and the end of tailed file
    # is reached.
    class BreakException < TailException; end

    # The ReopenException is raised internally if File::Tail
    # gets suspicious something unusual has happend to
    # the tailed file, e. g., it was rotated away. The exception
    # is caught and an attempt to reopen it is made.
    class ReopenException < TailException
      attr_reader :mode

      # Creates an ReopenException object. The mode defaults to
      # <code>:bottom</code> which indicates that the file
      # should be tailed beginning from the end. <code>:top</code>
      # indicates, that it should be tailed from the beginning from the
      # start.
      def initialize(mode = :bottom)
        super(self.class.name)
        @mode = mode
      end
    end

    class Tailable

      # The maximum interval File::Tail sleeps, before it tries
      # to take some action like reading the next few lines
      # or reopening the file.
      attr_accessor :max_interval

      # The start value of the sleep interval. This value
      # goes against <code>max_interval</code> if the tailed
      # file is silent for a sufficient time.
      attr_accessor :interval

      # If this attribute is set to a true value, File::Tail persists
      # on reopening a deleted file waiting <code>max_interval</code> seconds
      # between the attempts. This is useful if logfiles are
      # moved away while rotation occurs but are recreated at
      # the same place after a while. It defaults to true.
      attr_accessor :reopen_deleted

      # If this attribute is set to a true value, File::Tail
      # attempts to reopen it's tailed file after
      # <code>suspicious_interval</code> seconds of silence.
      attr_accessor :reopen_suspicious

      # The callback is called with _self_ as an argument after a reopen has
      # occured. This allows a tailing script to find out, if a logfile has been
      # rotated.
      def after_reopen(&block)
        @after_reopen = block
      end

      # This attribute is the interval in seconds before File::Tail
      # gets suspicious that something has happend to its tailed file
      # and an attempt to reopen it is made.
      #
      # If the attribute <code>reopen_suspicious</code> is
      # set to a non true value, suspicious_interval is
      # meaningless. It defaults to 60 seconds.
      attr_accessor :suspicious_interval

      # If this attribute is set to a true value, File::Fail's tail method
      # raises a BreakException if the end of the file is reached.
      attr_accessor :break_if_eof

      # If this attribute is set to a true value, File::Fail's tail method
      # just returns if the end of the file is reached.
      attr_accessor :return_if_eof

      # Default buffer size, that is used while going backward from a file's end.
      # This defaults to nil, which means that File::Tail attempts to derive this
      # value from the filesystem block size.
      attr_accessor :default_bufsize



      # This method tails this file and yields to the given block for
      # every new line that is read.
      # If no block is given an array of those lines is
      # returned instead. (In this case it's better to use a
      # reasonable value for <code>n</code> or set the
      # <code>return_if_eof</code> or <code>break_if_eof</code>
      # attribute to a true value to stop the method call from blocking.)
      #
      # If the argument <code>n</code> is given, only the next <code>n</code>
      # lines are read and the method call returns. Otherwise this method
      # call doesn't return, but yields to block for every new line read from
      # this file for ever.
      def tail(n = nil, &block) # :yields: line
        @n = n
        result = []
        array_result = false
        unless block
          block = lambda { |line| result << line }
          array_result = true
        end
        preset_attributes unless @lines
        loop do
          begin
            restat
            read_line(&block)
            redo
          rescue ReopenException => e
            handle_ReopenException(e, &block)
          rescue ReturnException
            return array_result ? result : nil
          end
        end
      end

      # Override me
      def close
        raise "Not implemented"
      end

      private

      def preset_attributes
        @reopen_deleted       = true if @reopen_deleted.nil?
        @reopen_suspicious    = true if @reopen_suspicious.nil?
        @break_if_eof         = false if @break_if_eof.nil?
        @return_if_eof        = false if @return_if_eof.nil?
        @max_interval         ||= 10
        @interval             ||= @max_interval
        @suspicious_interval  ||= 60
        @lines                = 0
        @no_read              = 0
      end

      def read_line(&block)
        if @n
          until @n == 0
            block.call readline
            @lines   += 1
            @no_read = 0
            @n       -= 1
            output_debug_information
          end
          raise ReturnException
        else
          block.call readline
          @lines   += 1
          @no_read = 0
          output_debug_information
        end
      rescue EOFError
        handle_EOFError
      rescue Errno::ENOENT, Errno::ESTALE, Errno::EBADF
        raise ReopenException
      end

      # Oy, override me !
      def readline
        raise "Not implemented"
      end

      # You can override this method in order to handle EOF error while reading
      def handle_EOFError
        raise ReopenException if @reopen_suspicious and
          @no_read > @suspicious_interval
        raise BreakException if @break_if_eof
        raise ReturnException if @return_if_eof
        sleep_interval
      end

      # You should overfide this method to behave correctly when a Reopen Exception is thrown
      def handle_ReopenException(ex, &block)
        reopen_tailable(ex.mode)
        @after_reopen.call self if @after_reopen
      end
      # You have to implement this method in order to detect underlying IO change
      def restat
        # Nothing
      end

      def sleep_interval
        if @lines > 0
          # estimate how much time we will spend on waiting for next line
          @interval = (@interval.to_f / @lines)
          @lines = 0
        else
          # exponential backoff if logfile is quiet
          @interval *= 2
        end
        if @interval > @max_interval
          # max. wait @max_interval
          @interval = @max_interval
        end
        output_debug_information
        sleep @interval
        @no_read += @interval
      end

      # You can override me too.
      def output_debug_information
        $DEBUG or return
        STDERR.puts({
          :lines    => @lines,
          :interval => @interval,
          :no_read  => @no_read,
          :n        => @n,
        }.inspect)
        self
      end

    end



    class File < Tailable
      attr_reader :_file

      def initialize(file_or_filename = nil)
        super()
        if file_or_filename.is_a?(String)
          @_file = ::File.new(file_or_filename, 'rb')
        elsif file_or_filename.is_a?(::File)
          @_file = file_or_filename
        end
      end

      def close
        self._file.close
      end

      def path
        self._file.path
      end

      def puts o
        self._file.puts o
      end

      # Skip the first <code>n</code> lines of this file. The default is to don't
      # skip any lines at all and start at the beginning of this file.
      def forward(n = 0)
        self._file.seek(0, ::File::SEEK_SET)
        while n > 0 and not self._file.eof?
          self._file.readline
          n -= 1
        end
        self
      end
      # Rewind the last <code>n</code> lines of this file, starting
      # from the end. The default is to start tailing directly from the
      # end of the file.
      #
      # The additional argument <code>bufsize</code> is
      # used to determine the buffer size that is used to step through
      # the file backwards. It defaults to the block size of the
      # filesystem this file belongs to or 8192 bytes if this cannot
      # be determined.
      def backward(n = 0, bufsize = nil)
        if n <= 0
          self._file.seek(0, ::File::SEEK_END)
          return self
        end
        bufsize ||= default_bufsize || self._file.stat.blksize || 8192
        size = self._file.stat.size
        begin
          if bufsize < size
            self._file.seek(0, ::File::SEEK_END)
            while n > 0 and self._file.tell > 0 do
              start = self._file.tell
              self._file.seek(-bufsize, ::File::SEEK_CUR)
              buffer = self._file.read(bufsize)
              n -= buffer.count("\n")
              self._file.seek(-bufsize, ::File::SEEK_CUR)
            end
          else
            self._file.seek(0, ::File::SEEK_SET)
            buffer = self._file.read(size)
            n -= buffer.count("\n")
            self._file.seek(0, ::File::SEEK_SET)
          end
        rescue Errno::EINVAL
          size = self._file.tell
          retry
        end
        pos = -1
        while n < 0  # forward if we are too far back
          pos = buffer.index("\n", pos + 1)
          n += 1
        end
        self._file.seek(pos + 1, ::File::SEEK_CUR)
        self
      end

      # On EOF, we seek to position 0
      # Next read will reopen the file if it has changed
      def handle_EOFError
        self._file.seek(0, ::File::SEEK_CUR)
        super
      end

      def handle_ReopenException(ex, &block)
        # Something wrong with the file, attempt to go until its end
        # or at least to read n lines and then proceed to reopening
        until self._file.eof? || @n == 0
          block.call self._file.readline
          @n -= 1 if @n
        end
        super
      end

      def readline
        self._file.readline
      end

      def restat
        stat = ::File.stat(self._file.path)
        if @stat
          if stat.ino != @stat.ino or stat.dev != @stat.dev
            @stat = nil
            raise ReopenException.new(:top)
          end
          if stat.size < @stat.size
            @stat = nil
            raise ReopenException.new(:top)
          end
        else
          @stat = stat
        end
      rescue Errno::ENOENT, Errno::ESTALE
        raise ReopenException
      end

      def reopen_tailable(mode)
        $DEBUG and $stdout.print "Reopening '#{path}', mode = #{mode}.\n"
        @no_read = 0
        self._file.reopen(::File.new(self._file.path, 'rb'))
        if mode == :bottom
          backward
        end
      rescue Errno::ESTALE, Errno::ENOENT
        if @reopen_deleted
          sleep @max_interval
          retry
        else
          raise DeletedException
        end
      end

    end
  end
end