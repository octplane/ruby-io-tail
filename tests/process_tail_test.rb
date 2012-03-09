#!/usr/bin/env ruby


$: << File.dirname(__FILE__)
$: << File.join(File.dirname(__FILE__),'..', 'lib')


require 'test_helper'
require 'io-tail'
require 'timeout'
require 'thread'
Thread.abort_on_exception = true

class ProcessTailTest < Test::Unit::TestCase

  def setup
    @out = File.new("test.#$$", "wb")
    @in = IO::Tail::Process.new("tail -n 0 -F test.#$$")
    @in.interval            = 0.1
    @in.max_interval        = 0.2
    @in.reopen_deleted      = true # is default
    @in.reopen_suspicious   = true # is default
    @in.suspicious_interval  = 60
  end
  TAIL_CONTENT = ['foo', 'bar', 'qux', 'dog', 'hop', 'mooh']
  # We should be able to do a tail as with a regular file...
  def test_tail_with_block
    teardown
    setup
    Thread.new do
      sleep(2)
      TAIL_CONTENT.each do |fragment|
        @out.puts fragment
        $stdout.flush
        @out.flush
      end
    end
    timeout(5) do
      tail_position = 0
      @in.tail { |l|
        $stdout.flush

        assert_equal(TAIL_CONTENT[tail_position], l.chomp)
        tail_position += 1
        # Exit when all content has been seen
        break if tail_position == TAIL_CONTENT.length
      }
    end
  end

  # However, seeking is not possible for a process
  def test_cannot_seek
    assert_raise(NoMethodError) { @in.backward(1) }
    assert_raise(NoMethodError) { @in.forward(1) }
  end

  # A killed process will be restarted if reopen_* is true
  def test_killed_child_will_reopen
      # Force test resetup
      teardown
      setup

      Thread.new do
        # Wait a bit for the tailer to be ready
        sleep(1)
        TAIL_CONTENT.each_with_index do |fragment, position|
        @out.puts fragment
        @out.flush
        if position == 2
          @in.kill_inner 
          # The tailer will see something's wrong and hopefully reopen the process
          # We have to wait a bit for the tailer to notice the process is down and restart it
          sleep(4)
        end
      end
    end
    timeout(6) do
      tail_position = 0
      @in.tail { |l|
        assert_equal(TAIL_CONTENT[tail_position], l.chomp)
        tail_position += 1
        # Exit when all content has been seen
        break if tail_position == TAIL_CONTENT.length
      }
    end

  end

  def teardown
    @in.close
    @out.close
    File.unlink(@out.path)
  end

  private

  def count(file)
    n = 0
    until file.eof?
      file.readline
      n += 1
    end
    return n
  end

end
