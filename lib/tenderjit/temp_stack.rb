# frozen_string_literal: true

class TenderJIT
  class TempStack
    class Item < Struct.new(:name, :type, :loc)
      # @return [void]
      def symbol?
        type == Ruby::T_SYMBOL
      end

      # @return [void]
      def fixnum?
        type == Ruby::T_FIXNUM
      end
    end

    # @return [void]
    def initialize
      @stack = []
      @sizeof_sp = TenderJIT.member_size(RbControlFrameStruct, "sp")
    end

    # @return [void]
    def freeze
      @stack.freeze
      super
    end

    # Flush the SP to the CFP within the +fisk+ context
    # @return [void]
    def flush fisk
      temp = fisk.register
      fisk.lea(temp, fisk.m(REG_BP, size * @sizeof_sp))
          .mov(fisk.m64(REG_CFP, RbControlFrameStruct.offsetof("sp")), temp)
      fisk.release_register temp
    end

    # Returns the info stored for stack location +idx+.  0 is the TOP of the
    # stack, or the last thing pushed.
    # @return [void]
    def peek idx
      idx = @stack.length - idx - 1
      raise IndexError if idx < 0
      @stack.fetch(idx)
    end

    # Returns the stack location +idx+.  0 is the TOP of the stack, or the last
    # thing that was pushed.
    # @return [void]
    def [] idx
      idx = @stack.length - idx - 1
      raise IndexError if idx < 0
      @stack.fetch(idx) {
        return Fisk::M64.new(REG_BP, idx * @sizeof_sp)
      }.loc
    end

    # @return [void]
    def first num = nil
      if num
        @stack.last(num)
      else
        @stack.last
      end
    end

    # Push a value on the temp stack. Returns the memory location where
    # to write the actual value in machine code.
    # @return [void]
    def push name, type: nil
      m = Fisk::M64.new(REG_BP, size * @sizeof_sp)
      @stack.push Item.new(name, type, m)
      m
    end

    # Pop a value from the temp stack. Returns the memory location where the
    # value should be read in machine code.
    # @return [void]
    def pop
      @stack.pop.loc
    end

    # @return [void]
    def initialize_copy other
      @stack = other.stack.dup
      super
    end

    # Get an operand for the stack pointer plus some bytes
    # @return [void]
    def + bytes
      Fisk::M64.new(REG_BP, (@stack.length * @sizeof_sp) + bytes)
    end

    # Get an operand for the stack pointer plus some bytes
    # @return [void]
    def - bytes
      Fisk::M64.new(REG_BP, (@stack.length * @sizeof_sp) - bytes)
    end

    # @return [void]
    def size
      @stack.size
    end

    protected

    attr_reader :stack
  end
end
