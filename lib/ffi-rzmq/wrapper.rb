require 'ffi' # external gem

module LibC
  extend FFI::Library
  # figures out the correct libc for each platform including Windows
  ffi_lib FFI::Library::LIBC

  # memory allocators
  attach_function :malloc, [:size_t], :pointer
  attach_function :calloc, [:size_t], :pointer
  attach_function :valloc, [:size_t], :pointer
  attach_function :realloc, [:pointer, :size_t], :pointer
  attach_function :free, [:pointer], :void

  # memory movers
  attach_function :memcpy, [:pointer, :pointer, :size_t], :pointer
  attach_function :bcopy, [:pointer, :pointer, :size_t], :void

end # module LibC

module LibZMQ
  extend FFI::Library
  LINUX = ["libzmq.so", "/usr/local/lib/libzmq.so", "/opt/local/lib/libzmq.so"]
  OSX = ["libzmq.dylib", "/usr/local/lib/libzmq.dylib", "/opt/local/lib/libzmq.dylib"]
  WINDOWS = []
  ffi_lib(LINUX + OSX + WINDOWS)

  # Misc
  attach_function :zmq_version, [:pointer, :pointer, :pointer], :void

  # Context and misc api
  attach_function :zmq_init, [:int, :int, :int], :pointer
  attach_function :zmq_socket, [:pointer, :int], :pointer
  attach_function :zmq_term, [:pointer], :int
  attach_function :zmq_errno, [], :int
  attach_function :zmq_strerror, [:int], :pointer

  # Message api
  attach_function :zmq_msg_init, [:pointer], :int
  attach_function :zmq_msg_init_size, [:pointer, :size_t], :int
  attach_function :zmq_msg_init_data, [:pointer, :pointer, :size_t, :pointer, :pointer], :int
  attach_function :zmq_msg_close, [:pointer], :int
  attach_function :zmq_msg_data, [:pointer], :pointer
  attach_function :zmq_msg_size, [:pointer], :size_t
  attach_function :zmq_msg_copy, [:pointer, :pointer], :int
  attach_function :zmq_msg_move, [:pointer, :pointer], :int

  MessageDeallocator = FFI::Function.new(:void, [:pointer, :pointer]) do |data_ptr, hint_ptr|
    LibC.free data_ptr
  end
  MessageDeallocator.autorelease = false

  module MsgLayout
    def self.included(base)
      base.class_eval do
        layout :content,  :pointer,
        :flags,    :uint8,
        :vsm_size, :uint8,
        :vsm_data, [:uint8, 30]
      end
    end
  end # module MsgLayout

  # Used for casting pointers back to the struct
  class Msg < FFI::Struct
    include MsgLayout
  end # class Msg


  # Socket api
  # @blocking = true is a hint to FFI that the following (and only the following)
  # function may block, therefore it should release the GIL before calling it.
  # This can aid in situations where the function call will/may block and another
  # thread within the lib may try to call back into the ruby runtime. Failure to
  # release the GIL will result in a hang; the hint *may* allow things to run
  # smoothly for Ruby runtimes hampered by a GIL.
  attach_function :zmq_setsockopt, [:pointer, :int, :pointer, :int], :int
  attach_function :zmq_bind, [:pointer, :string], :int
  attach_function :zmq_connect, [:pointer, :string], :int
  @blocking = true
  attach_function :zmq_send, [:pointer, :pointer, :int], :int
  @blocking = true
  attach_function :zmq_recv, [:pointer, :pointer, :int], :int
  attach_function :zmq_close, [:pointer], :int

  # Poll api
  @blocking = true
  attach_function :zmq_poll, [:pointer, :int, :long], :int

  module PollItemLayout
    def self.included(base)
      base.class_eval do
        layout :socket,  :pointer,
        :fd,    :int,
        :events, :short,
        :revents, :short
      end
    end
  end # module PollItemLayout

  class PollItem < FFI::Struct
    include PollItemLayout

    def readable?
      !(self[:revents] & ZMQ::POLLIN).zero?
    end

    def writable?
      !(self[:revents] & ZMQ::POLLOUT).zero?
    end

    def both_accessible?
      readable? && writable?
    end

    def inspect
      "socket [#{self[:socket]}], fd [#{self[:fd]}], events [#{self[:events]}], revents [#{self[:revents]}]"
    end

    def to_s; inspect; end
  end # class PollItem

end # module ZMQ
