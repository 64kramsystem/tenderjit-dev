# frozen_string_literal: true

require "helper"

class TenderJIT
  class NewrangeTest < JITTest
    # Simplified version of Ruby's official JIT test.
    #
    # Disassembly of the inner code (as of v3.0.2):
    #
    #   0000 putstring                              "a"                       (   1)[Li]
    #   0002 putstring                              "b"
    #   0004 newrange                               0
    #   0006 leave
    #
    def new_range
      'a'..'b'
    end

    def test_newrange
      meth = method(:new_range)

      assert_has_insn meth, insn: :newrange

      jit.compile(meth)
      jit.enable!
      v = meth.call
      jit.disable!

      assert_equal 1, jit.compiled_methods
      assert_equal 0, jit.exits
      assert_equal 'a'..'b', v
    end
  end
end
