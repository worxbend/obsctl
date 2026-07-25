require "c/unistd"

module CryTUI
  lib LibTerminal
    struct WindowSize
      rows : UInt16
      columns : UInt16
      x_pixels : UInt16
      y_pixels : UInt16
    end

    fun ioctl(fd : Int32, request : UInt64, ...) : Int32
  end

  module TerminalSize
    extend self

    {% if flag?(:linux) %}
      GET_WINDOW_SIZE = 0x5413_u64
    {% elsif flag?(:darwin) || flag?(:freebsd) || flag?(:openbsd) %}
      GET_WINDOW_SIZE = 0x40087468_u64
    {% else %}
      GET_WINDOW_SIZE = 0_u64
    {% end %}

    def from(io : IO::FileDescriptor) : Rect?
      return if GET_WINDOW_SIZE == 0
      size = uninitialized LibTerminal::WindowSize
      result = LibTerminal.ioctl(io.fd, GET_WINDOW_SIZE, pointerof(size))
      return unless result == 0 && size.columns > 0 && size.rows > 0
      Rect.new(0, 0, size.columns.to_i, size.rows.to_i)
    end

    def from_environment : Rect?
      columns = ENV["COLUMNS"]?.try(&.to_i?)
      lines = ENV["LINES"]?.try(&.to_i?)
      return unless columns && lines && columns > 0 && lines > 0
      Rect.new(0, 0, columns, lines)
    end
  end
end
