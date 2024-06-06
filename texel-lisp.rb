require "./helpers.rb"
require "./parser.rb"
require "./stack_vm.rb"
require "./stack_vm_assembler.rb"
require "./compiler.rb"
require "./debugger.rb"

c = TexelLisp::Compiler.new

c.add_primitive("+","add\nreturn\n", 2)
  .add_primitive("-", "sub\nreturn\n", 2)
  .add_primitive("*", "mul\nreturn\n", 2)
  .add_primitive("/", "div\nreturn\n", 2)
  .add_primitive(">", "greater_than?\nreturn\n", 2)
  .add_primitive("<", "less_than?\nreturn\n", 2)
  .add_primitive("=", "equals?\nreturn\n", 2)
  .add_primitive("!=", "not_equals?\nreturn\n", 2)
  .add_primitive("and", "logical_and\nreturn\n", 2)
  .add_primitive("or", "logical_or\nreturn\n", 2)
  .add_primitive("xor", "logical_xor\nreturn\n", 2)
  .add_primitive("&", "bitwise_and\nreturn\n", 2)
  .add_primitive("|", "bitwise_or\nreturn\n", 2)
  .add_primitive("^", "bitwise_xor\nreturn\n", 2)
  .add_special("if") do |compiler, children|
    raise "Wrong number of arguments passed to IF." unless children.size == 3
    condition = children[0]
    true_block = children[1]
    false_block = children[2]
    true_label, end_label = compiler.label_gen.next, compiler.label_gen.next
    %Q{
      #{compiler.compile(condition)}
      jump_cond #{true_label}
      #{compiler.compile(false_block)}
      jump_abs #{end_label}
      #{true_label}:
      #{compiler.compile(true_block)}
      #{end_label}:
    }
  end
  .add_special("raw_vm") do |compiler, children|
    raise "Wrong number of arguments passed to RAW_VM." unless children.size > 0
    raise "Arguments to RAW_VM must be strings" unless children.all? { |c| c.type == :STRING }
    children.map { |c| c.value }.join("\n") + "\n"
end
  .add_special("defc") do |compiler, children|
  raise "Wrong number of arguments passed to DEFC." unless children.size == 2
  raise "Constant name must be an identifier" unless children[0].type == :IDENTIFIER
  is_cons = children[1].type == :NUMBER || children[1].type == :SYMBOL
  raise "Cannot assign non-constant value to constant" unless is_cons
  compiler.context.add_constant(children[0].value, children[1].value)
  "push_lit #{children[1].value}"
end
  .add_special("defg") do |compiler, children|
    raise "Wrong number of arguments passed to DEFINE." unless children.size == 2
    name, definition = children[0], children[1]
    raise "Cannot define the value of non-identifier." unless name.type == :IDENTIFIER
    case definition.type
    when :NUMBER
      compiler.add_global(name.value, definition.value)
      "push_lit #{definition.value}"
    when :SYMBOL
      sym_val = compiler.symbol_table.get_symbol(definition.value)
      compiler.add_global(name.value, sym_val)
      "push_lit #{sym_val}"
    else
      raise "Cannot define global with dynamic values at compile-time."
    end
  end
  .add_special("setv") do |compiler, children|
    raise "SETV requires 2 arguments." unless children.size == 2
    name, val = children[0], children[1]
    resolved_name = compiler.context.lookup(name.value)
    raise "Cannot set value of non-identifier." unless name.type == :IDENTIFIER
    raise "Variable '#{name.value}' is not defined." unless resolved_name
    result_code = %Q{
      #{compiler.compile(val)}
      pick 0
      push_lit #{resolved_name.label}
      set_mem ; #{name.value}
    } if resolved_name.is_a?(TexelLisp::GlobalVar)
    result_code = %Q{
      #{compiler.compile(val)}
      pick 0
      set_slot #{resolved_name.stack_pos} ; #{name.value}
    } if resolved_name.is_a?(TexelLisp::LocalVar)
    result_code
  end
  .add_special("while") do |compiler, children|
    raise "WHILE requires 2 arguments." unless children.size == 2
    cond, body = children[0], children[1]
    cond_label, end_label = compiler.label_gen.next, compiler.label_gen.next
    %Q{
      #{cond_label}:
      #{compiler.compile(cond)}
      not_jump_cond #{end_label}
      #{compiler.compile(body)}
      drop
      jump_abs #{cond_label}
      #{end_label}:
      push_lit 0
    }
  end
  .add_special("begin") do |compiler, children|
    raise "BEGIN requires at least 1 argument." unless children.size > 0
    if children.size == 1
      compiler.compile(children[0])
    else
      children[0..-2].map do |c|
        binding.irb unless compiler.compile(c)
        compiler.compile(c) + "\n" + "drop"
      end.append(compiler.compile(children[-1])).join("\n")
    end
end
  .add_special("proc") do |compiler, children|
    raise "PROC requires an argument list and a body" unless children.size == 2
    lam_arg_names = children[0].to_a.map { |c| c.value }
    lam_body = children[1]
    lam_dyn_label = compiler.label_gen.next
    proc_ctx = compiler.context.extend(locals_size: lam_arg_names.size)
    compiler.context = proc_ctx
    lam_arg_names.each_with_index do |a, i|
      compiler.context.add_local(a, i)
    end
    lam_final_code = %Q{
    init_frame #{lam_arg_names.size}
    #{compiler.compile(lam_body)}
    destroy_frame #{lam_arg_names.size}
    return
    }
    compiler.context.add_func(lam_dyn_label, lam_final_code)
    user_func = compiler.context.lookup(lam_dyn_label)
    user_func.params = lam_arg_names.size
    compiler.global_table[user_func.label] = user_func
    compiler.context = compiler.context.parent
    %Q{
    push_lit #{user_func.label}
    }
  end
  .add_special("call") do |compiler, children|
    raise "CALL requires at least 1 argument" unless children.size > 0
    proc_val = children[0]
    proc_args = children.size > 1 ? children[1..-1] : []
    proc_args = proc_args.map { |a| compiler.compile(a) }
    %Q{
    #{proc_args.join("\n")}
    #{compiler.compile(proc_val)}
    call_sub_stack
    }
end
  .add_special("define") do |compiler, children|
  raise "DEFINE requires a name, an argument list, and a body" unless children.size == 3
  func_name = children[0]
  raise "First argument to DEFINE must be an identifier" unless func_name.type == :IDENTIFIER
  compiler.context.add_func(func_name.value, nil)
  binding.irb if children[1].to_a == 1
  func_arg_names = (children[1].to_a.size > 0 ? children[1].to_a.map { |c| c.value } : [])
  func_body = children[2]
  func_ctx = compiler.context.extend(locals_size: func_arg_names.size)
  compiler.context = func_ctx
  func_arg_names.each_with_index do |a, i|
    compiler.context.add_local(a, i)
  end
  func_header_code = (func_arg_names.size > 0 ? "init_frame #{func_arg_names.size}\n" : "")
  func_footer_code = (func_arg_names.size > 0 ? "destroy_frame #{func_arg_names.size}\n" : "")
  func_final_code = func_header_code +
    "#{compiler.compile(func_body)}\n" +
    func_footer_code + "return\n"
  user_func = compiler.context.lookup(func_name.value)
  user_func.params = func_arg_names.size
  user_func.code = func_final_code
  compiler.add_to_global_table(func_name.value)
  compiler.context = compiler.context.parent
  %Q{
    push_lit 0
    }
  end
  .add_special("let") do |compiler, children|
  raise "LET requires an argument list and a body" unless children.size == 2
  let_args = children[0].to_a.map { |c| c.to_a }
  let_body = children[1]
  let_compiled_args = let_args.map { |a| compiler.compile(a[1]) }.join("\n")
  compiler.context = compiler.context.extend(locals_size: let_args.size)
  let_args.each_with_index { |a,i| compiler.context.add_local(a[0].value, i) }
  let_final_code = %Q{
  #{let_compiled_args}
  init_frame #{let_args.size}
  #{compiler.compile(let_body)}
  destroy_frame #{let_args.size}
  }
  compiler.context = compiler.context.parent
  let_final_code
end

parser = TexelLisp::Parser.from_file("./test.tx")
node = parser.parse
node_output = node.to_a.map { |n| c.compile(n) }.join("\ndrop\n")
code = node_output + "\nhalt\n\n" + c.compile_defs
as = TexelLisp::StackVMAssembler.new(code: code)
vm = TexelLisp::StackVM.from_code(as.assemble)
debugger = TexelLisp::Debugger.new(vm, as)
debugger.debug
binding.irb