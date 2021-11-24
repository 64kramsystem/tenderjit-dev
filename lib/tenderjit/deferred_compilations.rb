require "fisk"
require "tenderjit/jit_context"

class TenderJIT
  class DeferredCompilations
    class DeferralRequest
      attr_reader :entry

      # @return [void]
      def initialize temp_stack, jit_buf, block
        @jit_buffer = jit_buf
        @temp_stack    = temp_stack
        @entry = @jit_buffer.memory.to_i + @jit_buffer.pos
        @block = block
      end

      # @return [void]
      def call
        fisk = Fisk.new
        @temp_stack.flush fisk

        ctx = JITContext.new(fisk, @jit_buffer, @temp_stack)

        @block.call ctx

        ctx.write!
      end
    end

    # @return [void]
    def initialize jit_buffer
      @jit_buffer = jit_buffer
    end

    # @return [DeferralRequest]
    # @yieldparam [JITContext]
    # @return [void]
    def deferred_call(temp_stack, &block)
      DeferralRequest.new(temp_stack.dup, @jit_buffer, block)
    end
  end
end
