module TexelLisp

  class DisassemblerInstr
    attr_accessor :lead_byte, :name, :extra_bytes, :has_arg

    def initialize(lead_byte:, name:, extra_bytes: 0, has_arg: false)
      @lead_byte, @name, @extra_bytes, @has_arg = lead_byte, name, extra_bytes, has_arg
    end
  end

  class Disassembler
    attr_accessor :instructions, :labels

    def initialize(labels={})
      @instructions = []
      @labels = labels
    end

    def self.default
      dis = Disassembler.new
      dis.add_instr(name: "nop", lead_byte: 0)
         .add_instr(name: "push_lit", lead_byte: 1, extra_bytes: 1)
         .add_instr(name: "push_slot", lead_byte: 2, has_arg: true)
         .add_instr(name: "push_mem", lead_byte: 3)
         .add_instr(name: "drop", lead_byte: 4)
         .add_instr(name: "pick", lead_byte: 5, has_arg: true)
         .add_instr(name: "init_frame", lead_byte: 6, has_arg: true)
         .add_instr(name: "jump_rel", lead_byte: 7, has_arg: true)
         .add_instr(name: "jump_abs", lead_byte: 8, extra_bytes: 1)
         .add_instr(name: "jump_cond", lead_byte: 9, has_arg: true)
         .add_instr(name: "call_sub", lead_byte: 10, extra_bytes: 1)
         .add_instr(name: "return", lead_byte: 11)
         .add_instr(name: lambda { |val, arg, bytes| ['add','sub','mul','div','mod','binary_and','binary_or','binary_xor','left_shift','right_shift'].at(arg) }, lead_byte: 12, has_arg: true)
         .add_instr(name: "halt", lead_byte: 13)
         .add_instr(name: "set_mem", lead_byte: 14)
         .add_instr(name: "allocate", lead_byte: 15)
         .add_instr(name: "dict", lead_byte: 16)
         .add_instr(name: lambda { |val, arg, bytes| ['equals?','less_than?','greater_than?','less_or_equals?','greater_or_equals?','not_equals?','logical_and','logical_or','logical_xor'].at(arg) }, lead_byte: 17, has_arg: true)
         .add_instr(name: "push_return", lead_byte: 18)
         .add_instr(name: "pop_return", lead_byte: 19)
         .add_instr(name: "swap", lead_byte: 20, has_arg: true)
         .add_instr(name: "not_jump_cond", lead_byte: 21, has_arg: true)
         .add_instr(name: "call_sub_stack", lead_byte: 22)
         .add_instr(name: "destroy_frame", lead_byte: 23, has_arg: true)
         .add_instr(name: "breakpoint", lead_byte: 24)
         .add_instr(name: "set_slot", lead_byte: 25, has_arg: true)
    end

    def add_instr(name:, lead_byte:, extra_bytes: 0, has_arg: false)
      @instructions[lead_byte] = DisassemblerInstr.new(lead_byte: lead_byte,
                                                  name: name,
                                                  extra_bytes: extra_bytes,
                                                  has_arg: has_arg)
      self
    end

    def label_comment(target)
      target_label = @labels.invert[target]
      return " ; #{target_label}" if target_label
      ""
    end

    def jump_call_comment(lead, arg, extra, ip)
      case lead
      when 8 # jump_abs
      when 10 # call_sub
        label_comment(extra)
      when 7 # jump_rel
      when 9 # jump_cond
      when 21 # not_jump_cond
        label_comment(arg + ip)
      else
        ""
      end
    end

    def output_instructions(bytes, num=1, instr_ptr=0)
      raise "Argument must be an array" unless bytes.is_a?(Array)
      raise "Can't pass an empty array" if bytes.empty?
      current_byte = 0
      total_output = ""
      num.times do
        output_line = ""
        lead_byte = bytes[current_byte]
        arg_val = (lead_byte & 0xFFFF0000) >> 16
        instr_val = (lead_byte & 0x0000FFFF)
        instr = @instructions[instr_val]
        if !@instructions[instr_val]
          total_output += "Unsupported instruction\n"
          next
        end
        output_line += instr.name if instr.name.is_a?(String)
        output_line += instr.name.call(instr_val, arg_val, bytes[current_byte..current_byte+instr.extra_bytes]) if instr.name.is_a?(Proc)
        output_line += " #{arg_val}" if instr.has_arg && instr.name.is_a?(String)
        output_line += " #{bytes[current_byte+1]}" if instr.extra_bytes > 0
        output_line += jump_call_comment(lead_byte, arg_val, bytes[current_byte+1], instr_ptr + current_byte)
        total_output += output_line + "\n"
        current_byte += 1 + instr.extra_bytes
      end
      total_output
    end
  end

  class Debugger
    attr_accessor :vm, :as, :disasm

    def initialize(vm, as, disasm=Disassembler.default)
      @as, @disasm, @vm = as, disasm, vm
      @disasm.labels = @as.labels
    end

    def debug
      while true do
        puts debug_header
        full_command = gets.chomp.split(' ')
        in_char = full_command[0] || ''
        arg = full_command[1]
        case in_char.downcase
        when 'n', 'next'
          @vm.execute_next_instruction
        when 'c', 'continue'
          @vm.run
        when 'u', 'until'
          @vm.run_until { |vm| vm.instr_ptr == arg.to_i }
        when 'q', 'quit'
          return
        end
      end

    end

    def debug_header
      "
      DSP: #{vm.data_ptr} DS: #{vm.data_stack}
      RSP: #{vm.return_ptr} RS: #{vm.return_stack}
      LSP: #{vm.local_ptr} LS: #{vm.local_stack}
      DP: #{vm.dict_ptr}
      IP: #{vm.instr_ptr}

      #{@disasm.output_instructions(vm.memory[vm.instr_ptr..-1], 5)}

      "
    end
  end
end