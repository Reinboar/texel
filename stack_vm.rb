module TexelLisp
  class StackVM

    CELL_SIZE = 4 # in bytes

    attr_accessor :memory, :instr_ptr,
                  :data_ptr, :data_init,
                  :return_ptr, :return_init,
                  :local_ptr, :local_init,
                  :dict_ptr, :dict_init,
                  :instruction_set, :running

    def self.from_code(code)
      raise "Code must be an Array" unless code.is_a?(Array)
      vm = StackVM.new(offset: code.size)
      vm.memory[0..code.size] = code
      vm
    end

    def initialize(mem_size: 65536, data_stack_size: 100,
                   return_stack_size: 100, local_stack_size: 100,
                   offset: 0)
      @memory = Array.new(mem_size) { 0 }
      @data_init = offset+data_stack_size
      @return_init = offset+data_stack_size+return_stack_size
      @local_init = offset+data_stack_size+return_stack_size+local_stack_size
      @dict_init = offset+data_stack_size+return_stack_size+local_stack_size+1
      @instr_ptr, @data_ptr, @return_ptr, @dict_ptr, @local_ptr =
        0,
          @data_init,
          @return_init,
          @dict_init,
          @local_init

      @running = false
      @instruction_set = {
        0 => NopInstr.new,
        1 => PushLiteralInstr.new,
        2 => PushFrameValInstr.new,
        3 => PushMemInstr.new,
        4 => DropInstr.new,
        5 => PickInstr.new,
        6 => InitFrameInstr.new,
        7 => JumpRelInstr.new,
        8 => JumpAbsInstr.new,
        9 => ConditionalJumpInstr.new,
        10 => CallSubInstr.new,
        11 => ReturnInstr.new,
        12 => BinaryOperatorInstr.new,
        13 => HaltInstr.new,
        14 => SetMemInstr.new,
        15 => AllocInstr.new,
        16 => DictInstr.new,
        17 => ComparisonOperatorInstr.new,
        18 => PushToReturnInstr.new,
        19 => PopFromReturnInstr.new,
        20 => SwapInstr.new,
        21 => NotConditionalJumpInstr.new,
        22 => CallSubStackInstr.new,
        23 => DestroyFrameInstr.new,
        24 => BreakpointInstr.new,
        25 => SetFrameValInstr.new,
      }
    end

    def push_data(val)
      val = force_cell_size(val)
      @memory[@data_ptr] = val
      @data_ptr -= 1
      nil
    end

    def pop_data
      @data_ptr += 1
      @memory[@data_ptr]
    end

    def data_stack
      @memory[@data_ptr+1..@data_init]
    end

    def push_return(val)
      val = force_cell_size(val)
      @memory[@return_ptr] = val
      @return_ptr -= 1
    end

    def pop_return
      @return_ptr += 1
      @memory[@return_ptr]
    end

    def return_stack
      @memory[@return_ptr+1..@return_init]
    end

    def dictionary
      @memory[@dict_init..@dict_ptr-1]
    end

    def push_local(val)
      val = force_cell_size(val)
      @memory[@local_ptr] = val
      @local_ptr -= 1
      nil
    end

    def pop_local
      @local_ptr += 1
      @memory[@local_ptr]
    end

    def init_frame(frame_size)
      frame_size.times { push_local(pop_data) }
    end

    def local_stack
      @memory[@local_ptr+1..@local_init]
    end

    def get_frame_slot(slot)
      @memory[@local_ptr+slot+1]
    end

    def set_frame_slot(slot, val)
      force_cell_size(val)
      @memory[@local_ptr+slot+1] = val
      nil
    end

    def advance_ip
      binding.irb unless @instr_ptr
      @instr_ptr += 1
      @memory[@instr_ptr-1]
    end

    def execute_next_instruction
      instr = advance_ip
      arg_val = (instr & 0xFFFF0000) >> 16
      instr_val = (instr & 0x0000FFFF)
      binding.irb unless @instruction_set[instr_val]
      @instruction_set[instr_val].execute(self, arg_val)
    end

    def run
      @running = true
      while @running
        execute_next_instruction
      end
    end

    def run_until(&block)
      @running = true
      while @running && !block.call(self)
        execute_next_instruction
      end
    end

    private

    def force_cell_size(val)
      # raise "Value is not a number" unless val.is_a?(Numeric)
      binding.irb unless val.is_a?(Numeric)
      TexelLisp.to_32_bit(val)
    end

  end

  class StackVMInstruction
    def initialize
    end

    def execute(vm, arg_val)
      raise "Unimplemented"
    end
  end

  class PushLiteralInstr < StackVMInstruction # ( -- val )
    def execute(vm, arg_val)
      literal = vm.advance_ip
      vm.push_data(literal)
    end
  end

  class PushMemInstr < StackVMInstruction # ( addr -- val )
    def execute(vm, arg_val)
      val = vm.memory[vm.pop_data]
      vm.push_data(val)
    end
  end

  class SetMemInstr < StackVMInstruction # ( val addr -- )
    def execute(vm, arg_val)
      addr = vm.pop_data
      val = vm.pop_data
      vm.memory[addr] = val
    end
  end

  class DupInstr < StackVMInstruction # ( a -- a a )
    def execute(vm, arg_val)
      a = vm.pop_data
      vm.push_data(a)
      vm.push_data(a)
    end
  end

  class DropInstr < StackVMInstruction # ( val -- )
    def execute(vm, arg_val)
      vm.pop_data
      nil
    end
  end

  class PushFrameValInstr < StackVMInstruction # ( -- val )
    def execute(vm, arg_val)
      vm.push_data(vm.get_frame_slot(arg_val))
    end
  end

  class SetFrameValInstr < StackVMInstruction # ( val -- )
    def execute(vm, arg_val)
      vm.set_frame_slot(arg_val, vm.pop_data)
    end
  end

  class InitFrameInstr < StackVMInstruction # ( -- )
    def execute(vm, arg_val)
      vm.init_frame(TexelLisp.from_16_bit(arg_val))
    end
  end

  class JumpAbsInstr < StackVMInstruction # ( -- )
    def execute(vm, arg_val)
      dest = vm.advance_ip
      vm.instr_ptr = dest
    end
  end

  class JumpRelInstr < StackVMInstruction # ( -- )
    def execute(vm, arg_val)
      dest = vm.instr_ptr + TexelLisp.from_16_bit(arg_val)
      vm.instr_ptr = dest
    end
  end

  class CallSubStackInstr < StackVMInstruction
    def execute(vm, arg_val)
      vm.push_return(vm.instr_ptr)
      vm.instr_ptr = vm.pop_data
    end
  end

  class CallSubInstr < StackVMInstruction # ( -- )
    def execute(vm, arg_val)
      vm.push_return(vm.instr_ptr+1)
      vm.instr_ptr = vm.advance_ip
    end
  end

  class ReturnInstr < StackVMInstruction # ( -- )
    def execute(vm, arg_val)
      vm.instr_ptr = vm.pop_return
    end
  end

  class NopInstr < StackVMInstruction # ( -- )
    def execute(vm, arg_val)

    end
  end

  class HaltInstr < StackVMInstruction # ( -- )
    def execute(vm, arg_val)
      vm.running = false
    end
  end

  class AllocInstr < StackVMInstruction # ( val -- )
    def execute(vm, arg_val)
      vm.dict_ptr += vm.pop_data
    end
  end

  class DictInstr < StackVMInstruction # ( -- addr )
    def execute(vm, arg_val)
      vm.push_data(vm.dict_ptr)
    end
  end

  class BinaryOperatorInstr < StackVMInstruction # ( a b -- c )
    def execute(vm, arg_val)
      b = TexelLisp.from_32_bit(vm.pop_data)
      a = TexelLisp.from_32_bit(vm.pop_data)
      case arg_val
      when 0 # addition
        vm.push_data(a+b)
      when 1 # subtraction
        vm.push_data(a-b)
      when 2 # multiplication
        vm.push_data(a*b)
      when 3 # integer division
        vm.push_data(a.div(b))
      when 4 # modulo
        vm.push_data(a%b)
      when 5 # binary AND
        vm.push_data(a&b)
      when 6 # binary OR
        vm.push_data(a|b)
      when 7 # binary XOR
        vm.push_data(a^b)
      when 8 # left shift
        vm.push_data(a<<b)
      when 9 # right shift
        vm.push_data(a>>b)
      else
        raise "Unsupported binary operator instruction"
      end
    end
  end

  class ComparisonOperatorInstr < StackVMInstruction # ( a b -- ? )
    def boolean_to_num(val)
      val ? 1 : 0
    end

    def execute(vm, arg_val)
      b = vm.pop_data
      a = vm.pop_data
      case arg_val
      when 0
        vm.push_data(boolean_to_num(a == b))
      when 1
        vm.push_data(boolean_to_num(a < b))
      when 2
        vm.push_data(boolean_to_num(a > b))
      when 3
        vm.push_data(boolean_to_num(a <= b))
      when 4
        vm.push_data(boolean_to_num(a >= b))
      when 5
        vm.push_data(boolean_to_num(a != b))
      when 6
        vm.push_data(boolean_to_num((a != 0) && (b != 0)))
      when 7
        vm.push_data(boolean_to_num((a != 0) || (b != 0)))
      when 8
        vm.push_data(boolean_to_num((a != 0) ^ (b != 0)))
      else
        raise "Unsupported comparison operator instruction"
      end
    end
  end

  class ConditionalJumpInstr < StackVMInstruction # ( a -- )
    def execute(vm, arg_val)
      a = vm.pop_data
      dest = vm.instr_ptr + TexelLisp.from_16_bit(arg_val)
      vm.instr_ptr = dest unless a == 0
    end
  end

  class NotConditionalJumpInstr < StackVMInstruction
    def execute(vm, arg_val)
      a = vm.pop_data
      dest = vm.instr_ptr + TexelLisp.from_16_bit(arg_val)
      vm.instr_ptr = dest if a == 0
    end
  end

  class PushToReturnInstr < StackVMInstruction # ( a -- )
    def execute(vm, arg_val)
      a = vm.pop_data
      vm.push_return(a)
    end
  end

  class PopFromReturnInstr < StackVMInstruction # ( -- a )
    def execute(vm, arg_val)
      a = vm.pop_return
      vm.push_data(a)
    end
  end

  class SwapInstr < StackVMInstruction
    def execute(vm, arg_val)
      swap_n = TexelLisp.from_16_bit(arg_val)
      if swap_n >= 0
        target_cell = vm.memory[vm.data_ptr+swap_n+1]
        rest_cells = vm.memory[vm.data_ptr+1..vm.data_ptr+swap_n]
        vm.memory[vm.data_ptr+1..vm.data_ptr+swap_n+1] = [target_cell, *rest_cells]
      else
        swap_n = swap_n.abs
        target_cell = vm.memory[vm.data_ptr+1]
        rest_cells = vm.memory[vm.data_ptr+2..vm.data_ptr+swap_n+1]
        vm.memory[vm.data_ptr+1..vm.data_ptr+swap_n+1] = [*rest_cells, target_cell]
      end
    end
  end

  class PickInstr < StackVMInstruction # ( ... n -- a )
    def execute(vm, arg_val)
      n = TexelLisp.from_16_bit(arg_val)
      raise "Argument to PICK cannot be negative" unless n > -1
      vm.push_data(vm.memory[vm.data_ptr + n + 1])
    end
  end

  class DestroyFrameInstr < StackVMInstruction
    def execute(vm, arg_val)
      n = TexelLisp.from_16_bit(arg_val)
      n.times { vm.pop_local }
    end
  end

  class BreakpointInstr < StackVMInstruction
    def execute(vm, arg_val)
      binding.irb
    end
  end

end