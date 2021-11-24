# frozen_string_literal: true

# Just some additions to fiddle that maybe we should upstream?

require "fiddle"

module Fiddle
  TYPE_TO_NAME = Fiddle.constants.grep(/^TYPE_/).each_with_object({}) { |n, h|
    h[Fiddle.const_get(n)] = n.to_s
  }

  # @return [void]
  def self.adjust_addresses syms
    slide = Fiddle::Handle::DEFAULT["rb_st_insert"] - syms.fetch("rb_st_insert")
    syms.transform_values! { |v| v + slide }
    syms
  end

  class CArray # :nodoc:
    # @return [void]
    def self.unpack ptr, len, type
      size = Fiddle::PackInfo::SIZE_MAP[type]
      bytesize = size * len
      ptr[0, bytesize].unpack("#{Fiddle::PackInfo::PACK_MAP[type]}#{len}")
    end
  end

  # @return [void]
  def self.read_ptr ptr, offset
    Fiddle::Pointer.new(ptr)[offset, Fiddle::SIZEOF_VOIDP].unpack1("l!")
  end

  # @return [void]
  def self.write_ptr ptr, offset, val
    data = [val].pack("l!")
    Fiddle::Pointer.new(ptr)[offset, Fiddle::SIZEOF_VOIDP] = data
    nil
  end

  # @return [void]
  def self.read_unsigned_int ptr, offset
    Fiddle::Pointer.new(ptr)[offset, Fiddle::SIZEOF_INT].unpack1(PackInfo::PACK_MAP[-TYPE_INT])
  end

  module Layout
    # Describes the layout of a struct object from C
    class Struct
      class Instance
        attr_reader :layout, :base

        # @return [void]
        def initialize layout, ptr
          @layout = layout
          @base   = ptr.to_i
        end

        # @return [void]
        def to_i
          base
        end
        alias :to_int :to_i

        # @return [void]
        def to_ptr
          Fiddle::Pointer.new to_i
        end
      end

      class Member
        attr_reader :name, :type, :offset

        # @return [void]
        def initialize name, type, offset
          raise ArgumentError unless offset

          @name = name
          @type = type
          @offset = offset
        end

        # @return [void]
        def substruct?; false; end
        # @return [void]
        def immediate?; false; end

        # @return [void]
        def byte_size
          Fiddle::PackInfo::SIZE_MAP[type]
        end

        # @return [void]
        def unpack
          Fiddle::PackInfo::PACK_MAP[type]
        end

        # @return [void]
        def real_type
          type
        end
      end

      class Immediate < Member
        # @return [void]
        def immediate?; true; end

        # @return [void]
        def read base
          Fiddle::Pointer.new(base)[offset, byte_size].unpack1(unpack)
        end

        # @return [void]
        def write base, val
          data = [val].pack(unpack)
          Fiddle::Pointer.new(base)[offset, byte_size] = data
          nil
        end
      end

      class SubStruct < Member
        # @return [void]
        def substruct?; true; end

        # @return [void]
        def read base
          raise ArgumentError unless base

          type.new(base + offset)
        end

        # @return [void]
        def byte_size
          type.byte_size
        end
      end

      class RefCast < Member
        # @return [void]
        def initialize name, type, offset, block
          super(name, type, offset)
          @block = block
        end

        # @return [void]
        def read base
          @block.call.new(type.read(base))
        end

        # @return [void]
        def size
          type.size
        end

        # @return [void]
        def real_type
          type.type
        end
      end

      class D4Reader < ::Struct.new(:loc, :byte_size, :bit_offset, :bit_size)
        # @return [void]
        def real_type
          -Fiddle::TYPE_INT32_T
        end

        # @return [void]
        def read base
          bits = byte_size * 8

          mask = 0xFFFFFFFF
          bitfield = Fiddle::Pointer.new(base)[loc, Fiddle::SIZEOF_INT].unpack1("i!")
          bitfield = mask & (bitfield << bit_offset)
          bitfield >> (bit_offset + (bits - (bit_size + bit_offset)))
        end
      end

      class D5Reader < ::Struct.new(:name, :bit_offset, :bit_size)
        INT_BITS = Fiddle::SIZEOF_INT * 8

        # @return [void]
        def real_type
          -Fiddle::TYPE_INT32_T
        end

        # @return [void]
        def read base
          aligned_offset = ((bit_offset >> 5) << 5)
          buffer_loc = (aligned_offset / INT_BITS) * Fiddle::SIZEOF_INT

          bitfield = Fiddle::Pointer.new(base)[buffer_loc, Fiddle::SIZEOF_INT].unpack1("i!")
          bitfield >>= (bit_offset - aligned_offset)
          bitfield & ((1 << bit_size) - 1)
        end
      end

      attr_reader :byte_size, :instance_class, :name

      # @return [void]
      def initialize name, byte_size, names, types, offsets = nil
        @name = name
        @members_by_name = {}

        names.map.with_index do |name, i|
          case types[i]
          when Struct, Union, Array
            member = SubStruct.new(name, types[i], offsets[i])
            @members_by_name[name] = member
          when Layout::AutoRef
            reader = Immediate.new(name, types[i].type, offsets[i])
            member = RefCast.new(name, reader, offsets[i], types[i].block)
            @members_by_name[name] = member
          when Layout::D5BitField
            type = types[i]
            name.zip(type.bitfields).each do |bname, (bit_offset, bit_size)|
              @members_by_name[bname] = D5Reader.new(bname, bit_offset, bit_size)
            end
          when Layout::D4BitField
            type = types[i]
            name.zip(types[i].bitfields).each do |bname, (loc, byte_size, bit_offset, bit_size)|
              @members_by_name[bname] = D4Reader.new(loc, byte_size, bit_offset, bit_size)
            end
            member = Immediate.new(name, -Fiddle::TYPE_INT32_T, offsets[i])
          else
            member = Immediate.new(name, types[i], offsets[i])
            @members_by_name[name] = member
          end
        end

        @byte_size = byte_size
        @instance_class = make_class(@members_by_name.keys)
        extend make_module(@members_by_name.keys)
      end

      # @return [void]
      def members; @members_by_name.keys; end

      private def make_class members
        Class.new(Instance) {
          members.each do |name|
            define_method(name) { @layout.read(base, name) }
            define_method("#{name}=") { |v| @layout.write(base, name, v) }
          end
        }
      end

      private def make_module members
        Module.new {
          members.each do |name|
            define_method(name) { |base| read(base, name) }
            define_method("set_#{name}") { |base, v| write(base, name, v) }
          end
        }
      end

      # @return [void]
      def types; @members_by_name.values.map(&:real_type); end

      # @return [void]
      def member? name
        @members_by_name.key? name
      end

      # @return [void]
      def member name
        @members_by_name[name]
      end

      # @return [void]
      def offsetof name
        @members_by_name[name].offset
      end

      # @return [void]
      def new ptr
        @instance_class.new self, ptr
      end

      # @return [void]
      def read ptr, name
        raise ArgumentError unless ptr

        @members_by_name.fetch(name).read ptr
      end

      # @return [void]
      def write ptr, name, val
        raise ArgumentError unless ptr && val

        @members_by_name.fetch(name).write ptr, val
      end

      # @return [void]
      def member_size name
        @members_by_name[name].byte_size
      end
    end

    AutoRef = ::Struct.new(:type, :block)
    D5BitField = ::Struct.new(:bitfields)
    D4BitField = ::Struct.new(:bitfields)

    class Union < Struct; end

    # Describes the layout of an array
    class Array

      # An instance of the described layout
      class Instance
        include Enumerable

        # @return [void]
        def initialize layout, base
          @layout = layout
          @base = base
        end

        # @return [void]
        def to_i
          @base
        end

        # @return [void]
        def [] idx
          @layout.read @base, idx
        end

        # @return [void]
        def each
          length.times do |i|
            yield self[i]
          end
        end

        # @return [void]
        def length
          @layout.len
        end
      end

      attr_reader :type, :len

      # @return [void]
      def initialize type, len
        @type = type
        @len = len
      end

      # Read from an array with the +base+ pointer at the index +idx+
      # @return [void]
      def read base, idx
        Fiddle::Pointer.new(base)[idx * byte_size, byte_size].unpack1(unpack)
      end

      # Create an instance of an array at the base pointer +base+
      # @return [void]
      def new base
        Instance.new self, base
      end

      # @return [void]
      def byte_size
        Fiddle::PackInfo::SIZE_MAP.fetch(type)
      end

      # @return [void]
      def unpack
        Fiddle::PackInfo::PACK_MAP.fetch(type)
      end
    end
  end
end
