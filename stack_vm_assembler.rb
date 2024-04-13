module TexelLisp
  class StackVMAssembler
    attr_accessor :lines, :current_line, :macros,
                  :labels, :output, :anon_labels,
                  :current_anon_label

    def self.from_file(filename)
      StackVMAssembler.new(code: File.read(filename))
    end

    def initialize(code:)
      @lines = code.gsub("\r","").split("\n").map(&:strip).reject(&:empty?)
      @current_line = 0
      @macros = {}
      @labels = {}
      @anon_labels = []
      @current_anon_label = 0

      @directives = {
        "org" => OrgBlock.new,
        "equ" => EquBlock.new,
        "macro" => MacroBlock.new,
        "cell" => CellBlock.new,
      }

      @instructions = {
        "push_lit" => PushLiteralBlock.new,
        "push_slot" => PushFrameValBlock.new,
        "set_slot" => SetFrameValBlock.new,
        "push_mem" => PushMemBlock.new,
        "set_mem" => SetMemBlock.new,
        "pick" => PickBlock.new,
        "drop" => DropBlock.new,
        "swap" => SwapBlock.new,
        "init_frame" => InitFrameBlock.new,
        "destroy_frame" => DestroyFrameBlock.new,
        "jump_rel" => JumpRelBlock.new,
        "jump_abs" => JumpAbsBlock.new,
        "jump_cond" => JumpCondBlock.new,
        "call_sub" => CallSubBlock.new,
        "return" => ReturnBlock.new,
        "add" => AddBlock.new,
        "sub" => SubBlock.new,
        "mul" => MulBlock.new,
        "div" => DivBlock.new,
        "mod" => ModBlock.new,
        "bitwise_and" => AndBlock.new,
        "bitwise_or" => OrBlock.new,
        "bitwise_xor" => XorBlock.new,
        "left_shift" => LShiftBlock.new,
        "right_shift" => RShiftBlock.new,
        "nop" => NopBlock.new,
        "halt" => HaltBlock.new,
        "allocate" => AllocBlock.new,
        "dict" => DictBlock.new,
        "equals?" => EqualsBlock.new,
        "less_than?" => LessThanBlock.new,
        "greater_than?" => GreaterThanBlock.new,
        "less_or_equals?" => LessThanOrEqualsBlock.new,
        "greater_or_equals?" => GreaterThanOrEqualsBlock.new,
        "not_equals?" => NotEqualsBlock.new,
        "logical_and" => LogicalAndBlock.new,
        "logical_or" => LogicalOrBlock.new,
        "logical_xor" => LogicalXorBlock.new,
        "push_return" => PushReturnBlock.new,
        "pop_return" => PopReturnBlock.new,
        "not_jump_cond" => NotConditionalJumpBlock.new,
        "call_sub_stack" => CallSubStackBlock.new,
        "breakpoint" => BreakpointBlock.new,
      }

      @output = StackVMBinary.new
    end

    def assemble
      until @current_line >= @lines.size
        process_line(@lines[@current_line])
        @current_line += 1
      end
      @output.resolve_cells
      @output.content
    end

    def remove_comment(line)
      comment_ind = line.index(';')
      comment_ind ? line[0...comment_ind] : line
    end

    def extract_line(line)
      line = remove_comment(line)
      first_space_ind = line.index(' ')
      return line, [] unless first_space_ind
      command = line[0...first_space_ind]
      args = line[first_space_ind..-1].split(',').map(&:strip)
      return command, args
    end

    def process_line(line)
      puts "CURRENT LINE: '#{line}'"
      return nil if line.empty?
      command, args = extract_line(line)
      case command[0]
      when '.'
        process_directive(command[1..-1], args)
      when '$'
        process_macro(command[1..-1], args)
      else
        if command[-1] == ':'
          add_label(command[0..-2], @output.current_cell) if command.length > 1
          add_anonymous_label(@output.current_cell) if command.length == 1
        else
          process_instruction(command, args)
        end
      end
    end

    def process_macro(command, args)
      @macros[command.downcase].execute(self, args)
    end

    def process_directive(command, args)
      @directives[command.downcase].execute(self, args)
    end

    def process_instruction(command, args)
      raise "On line #{@current_line}: #{command} is not a valid instruction." unless @instructions[command]
      @instructions[command.downcase].execute(self, args)
    end

    def resolve_argument(val)
      if /^\d+$/.match?(val)
        val.to_i
      else
        resolve_label(val)
      end
    end

    def is_label?(label)
      !/^-?\d+$/.match?(label)
    end

    def is_anon_label?(label)
      /^:(\++|-+)?$/.match?(label)
    end

    def anon_label_exists?(label)
      anon_offset = label[1..-1].chars.reduce(0) { |a,e| { '+' => 1, '-' => -1 }[e] + a }
      anon_offset < 0
    end

    def label_exists?(label)
      return true if is_anon_label?(label) && anon_label_exists?(label)
      @labels[label] != nil
    end

    def resolve_anon_label(label)
      anon_offset = label[1..-1].chars.reduce(0) { |a,e| { '+' => 1, '-' => -1 }[e] + a }
      pp @anon_labels
      puts "RESOLVING ANON LABEL:: current -> #{@current_anon_label} ; offset -> #{anon_offset} ; value -> #{@anon_labels[@current_anon_label + anon_offset]}"
      @anon_labels[@current_anon_label + anon_offset]
    end

    def resolve_label(label)
      return resolve_anon_label(label) if is_anon_label?(label)
      @labels[label]
    end

    def add_label(label, val)
      raise "Value must be a number" unless val.is_a?(Numeric)
      @labels[label] = val
    end

    def add_anonymous_label(val)
      @anon_labels[@current_anon_label] = val
      @current_anon_label += 1
    end

  end

  class StackVMBinary
    attr_accessor :content, :current_cell

    def initialize
      @content = Array.new(0, 0)
      @current_cell = 0
    end

    def add_cell(cell)
      raise "Cell cannot be NIL" unless cell
      @content[@current_cell] = cell.is_a?(Numeric) ? cell & 0xFFFFFFFF : cell
      @current_cell += 1
      self
    end

    def add_cells(*cells)
      cells.each { |c| add_cell(c) }
      self
    end

    def add_instr(instr, arg)
      final_instr = (instr & 0x0000FFFF) | ((arg & 0x0000FFFF) << 16)
      add_cell(final_instr)
      self
    end

    def resolve_cells
      @content.map! do |c|
        c.is_a?(Proc) ? c.call : c
      end
    end

  end

  class StackVMMacro
    attr_accessor :lines, :params

    def initialize(lines:, params:)
      @lines, @params = lines, params
    end

    def execute(assembler, args)
      assembler.lines.delete_at(assembler.current_line)
      assembler.lines.insert(assembler.current_line, *resolve(args))
      assembler.current_line -= 1
      nil
    end

    def resolve(args)
      raise "Macro does not have enough arguments" unless args.size == @params
      @lines.map do |l|
        new_line = l
        @params.times do |i|
          new_line = new_line.gsub("$#{i+1}", args[i])
        end
        new_line
      end
    end
  end

  module LabelCalculator

    def calc_or_delay_label(assembler, arg)
      return arg.to_i unless assembler.is_label?(arg)
      return assembler.resolve_label(arg) if assembler.label_exists?(arg)
      delayed_anon_label = assembler.current_anon_label - 1
      ->() do
        saved_anon_label = assembler.current_anon_label
        assembler.current_anon_label = delayed_anon_label
        result = assembler.resolve_label(arg)
        assembler.current_anon_label = saved_anon_label
        result
      end
    end

    def calc_or_delay_label_rel(assembler, arg, offset)
      return arg.to_i - offset - 1 unless assembler.is_label?(arg)
      return assembler.resolve_label(arg) - offset - 1 if assembler.label_exists?(arg)
      delayed_anon_label = assembler.current_anon_label - 1
      ->() do
        saved_anon_label = assembler.current_anon_label
        assembler.current_anon_label = delayed_anon_label
        result = assembler.resolve_label(arg) - offset - 1
        assembler.current_anon_label = saved_anon_label
        result
      end
    end
  end

  class StackVMBlock
    include LabelCalculator

    def initialize
    end

    def execute(assembler, args)
      raise "Unimplemented"
    end
  end

  ### ASSEMBLER DIRECTIVES ###

  class EquBlock < StackVMBlock
    def execute(assembler, args)
      raise "Incorrect number of arguments" unless args.length == 2
      assembler.add_label(args[0], args[1].to_i)
    end
  end

  class CellBlock < StackVMBlock
    def execute(assembler, args)
      raise "Incorrect number of arguments" unless args.length > 0
      args.each do |a|
        assembler.output.add_cell(a.to_i)
      end
    end
  end

  class OrgBlock < StackVMBlock
    def execute(assembler, args)
      raise "Incorrect number of arguments" unless args.length == 1
      assembler.output.current_cell = args[0].to_i
    end
  end

  class MacroBlock < StackVMBlock
    def execute(assembler, args)
      raise "Macros must be named" unless args.length > 0
      macro_name = args[0].downcase
      macro_lines = []
      assembler.current_line += 1
      until assembler.lines[assembler.current_line] == '.end_macro'
        macro_lines.append(assembler.lines[assembler.current_line])
        assembler.current_line += 1
      end
      assembler.macros[macro_name] =
        StackVMMacro.new(lines: macro_lines, params: args[1..-1].size)
    end
  end

  ### ASSEMBLER INSTRUCTIONS ###

  class PushLiteralBlock < StackVMBlock
    def execute(assembler, args)
      raise "PUSH_LIT requires 1 argument" unless args.size == 1
      assembler.output.add_instr(1,0)
      lit_val = calc_or_delay_label(assembler, args[0])
      assembler.output.add_cells(lit_val)
    end
  end

  class PushMemBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(3,0)
    end
  end

  class PushFrameValBlock < StackVMBlock
    def execute(assembler, args)
      raise "PUSH_FRAME_VAL requires 1 argument" unless args.size == 1
      assembler.output.add_instr(2, args[0].to_i)
    end
  end

  class SetFrameValBlock < StackVMBlock
    def execute(assembler, args)
      raise "SET_FRAME_VAL requires 1 argument" unless args.size == 1
      assembler.output.add_instr(25, args[0].to_i)
    end
  end

  class DropBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(4,0)
    end
  end

  class DupBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(5,0)
    end
  end

  class InitFrameBlock < StackVMBlock
    def execute(assembler, args)
      raise "INIT_FRAME requires 1 argument" unless args.size == 1
      assembler.output.add_instr(6, args[0].to_i)
    end
  end

  class DestroyFrameBlock < StackVMBlock
    def execute(assembler, args)
      raise "DESTROY_FRAME requires 1 argument" unless args.size == 1
      assembler.output.add_instr(23, TexelLisp.to_16_bit(args[0].to_i))
    end
  end

  class JumpRelBlock < StackVMBlock
    def execute(assembler, args)
      raise "JUMP_REL requires 1 argument" unless args.size == 1
      raw_dest = args[0]
      rel_result = calc_or_delay_label_rel(assembler, raw_dest, assembler.output.current_cell)
      if rel_result.is_a?(Proc)
        assembler.output.add_cell( ->() { ((rel_result.call) << 16) | 6 } )
      else
        assembler.output.add_instr(7, TexelLisp.to_16_bit(rel_result))
      end
    end
  end

  class JumpAbsBlock < StackVMBlock
    def execute(assembler, args)
      raise "JUMP_ABS requires 1 argument" unless args.size == 1
      assembler.output.add_instr(8,0)
      assembler.output.add_cell( calc_or_delay_label(assembler, args[0]) )
    end
  end

  class CallSubBlock < StackVMBlock
    def execute(assembler, args)
      raise "CALL_SUB requires 1 argument" unless args.size == 1
      assembler.output.add_instr(10,0)
      assembler.output.add_cell( calc_or_delay_label(assembler, args[0]) )
    end
  end

  class CallSubStackBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(22,0)
    end
  end

  class ReturnBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(11,0)
    end
  end

  class NopBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(0,0)
    end
  end

  class AddBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(12,0)
    end
  end

  class SubBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(12,1)
    end
  end

  class MulBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(12,2)
    end
  end

  class DivBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(12,3)
    end
  end

  class ModBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(12,4)
    end
  end

  class AndBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(12,5)
    end
  end

  class OrBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(12,6)
    end
  end

  class XorBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(12,7)
    end
  end

  class LShiftBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(12,8)
    end
  end

  class RShiftBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(12,9)
    end
  end

  class HaltBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(13,0)
    end
  end

  class SetMemBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(14,0)
    end
  end

  class AllocBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(15,0)
    end
  end

  class DictBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(16,0)
    end
  end

  class EqualsBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(17,0)
    end
  end

  class LessThanBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(17,1)
    end
  end

  class GreaterThanBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(17,2)
    end
  end

  class LessThanOrEqualsBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(17,3)
    end
  end

  class GreaterThanOrEqualsBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(17,4)
    end
  end

  class NotEqualsBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(17,5)
    end
  end

  class LogicalAndBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(17,6)
    end
  end

  class LogicalOrBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(17,7)
    end
  end

  class LogicalXorBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(17,8)
    end
  end

  class JumpCondBlock < StackVMBlock
    def execute(assembler, args)
      raise "JUMP_COND requires 1 argument" unless args.size == 1
      rel_dest = calc_or_delay_label_rel(assembler, args[0], assembler.output.current_cell)
      if rel_dest.is_a?(Numeric)
        assembler.output.add_instr(9, TexelLisp.to_16_bit(rel_dest))
      else
        assembler.output.add_cell( ->() { (TexelLisp.to_16_bit(rel_dest.call) << 16) | 9 } )
      end
    end
  end

  class PushReturnBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(18, 0)
    end
  end

  class PopReturnBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(19, 0)
    end
  end

  class SwapBlock < StackVMBlock
    def execute(assembler, args)
      raise "SWAP requires 1 argument" unless args.size == 1
      swap_n = calc_or_delay_label(assembler, args[0])
      if swap_n.is_a?(Numeric)
        assembler.output.add_instr(20, TexelLisp.to_16_bit(swap_n))
      else
        assembler.output.add_cell( ->() { TexelLisp.to_16_bit(swap_n.call) << 16 | 20 } )
      end
    end
  end

  class PickBlock < StackVMBlock
    def execute(assembler, args)
      raise "PICK requires 1 argument" unless args.size == 1
      pick_n = calc_or_delay_label(assembler, args[0])
      if pick_n.is_a?(Numeric)
        assembler.output.add_instr(5, pick_n)
      else
        assembler.output.add_cell( ->() { TexelLisp.to_16_bit(pick_n.call) << 16 | 5 } )
      end
    end
  end

  class NotConditionalJumpBlock < StackVMBlock
    def execute(assembler, args)
      raise "NOT_JUMP_COND requires 1 argument" unless args.size == 1
      rel_dest = calc_or_delay_label_rel(assembler, args[0], assembler.output.current_cell)
      if rel_dest.is_a?(Numeric)
        assembler.output.add_instr(21, TexelLisp.to_16_bit(rel_dest))
      else
        assembler.output.add_cell( ->() { (TexelLisp.to_16_bit(rel_dest.call) << 16) | 21 } )
      end
    end
  end

  class BreakpointBlock < StackVMBlock
    def execute(assembler, args)
      assembler.output.add_instr(24, 0)
    end
  end

end