#!/usr/bin/env ruby

$: << File.dirname(__FILE__)
$: << File.join(File.dirname(__FILE__),'..', 'lib')

require 'test_helper'
require 'io-tail'
require 'timeout'
require 'thread'
Thread.abort_on_exception = true

class FileTailTest < Test::Unit::TestCase

  def setup
    @out = File.new("test.#$$", "wb")
    append(@out, 100)
    @out.flush
    @out.close
    in_file = ::File.new(@out.path, "rb")
    @in = IO::Tail::File.new(in_file)
    @in.interval            = 0.4
    @in.max_interval        = 0.8
    @in.reopen_deleted      = true # is default
    @in.reopen_suspicious   = true # is default
    @in.suspicious_interval  = 60
  end

  def test_tail_with_nothing_new_has_nothing
    count = 0
    begin 
      timeout(2) do
        @in.tail do |l|
          count += 1
        end
      end
    rescue Timeout::Error
    end
    assert_equal(0, count)
  end
  def teardown
    @in.close
    File.unlink(@out.path)
  end

  private
  def count(file)
    n = 0
    until file._file.eof?
      file.readline
      n += 1
    end
    return n
  end

  def append(file, n, size = 70)
    (1..n).each { |x| file << "#{x} #{"A" * size}\n" }
    file.flush
  end
end
