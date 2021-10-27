# frozen_string_literal: true

require "helper"

class TenderJIT
  class OptNeqTest < JITTest
    # Disasm, as of v3.0.2:
    #
    #   0000 putobject_INT2FIX_1_                                             (   1)[Li]
    #   0001 putobject                              2
    #   0003 opt_neq                                <calldata!mid:==, argc:1, ARGS_SIMPLE>, <calldata!mid:!=, argc:1, ARGS_SIMPLE>
    #   0006 leave
    #
    def neq
      1 != 2
    end

    def test_opt_neq
      meth = method(:neq)

      assert_has_insn meth, insn: :opt_neq

      jit.compile(meth)
      jit.enable!
      result = meth.call
      jit.disable!

      assert_equal 1, jit.compiled_methods
      assert_equal 0, jit.exits
      assert_equal true, result
    end
  end
end
