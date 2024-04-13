module TexelLisp
  def self.to_16_bit(val)
    val & 0xFFFF
  end

  def self.to_32_bit(val)
    val & 0xFFFFFFFF
  end

  def self.from_16_bit(val)
    return -(0x10000 - (0xFFFF & val)) if val > 0x7FFF
    0xFFFF & val
  end

  def self.from_32_bit(val)
    return -(0x100000000 - (0xFFFFFFFF & val)) if val > 0x7FFFFFFF
    0xFFFFFFFF & val
  end

  def self.sanitize_label(name)
    name.gsub(/[:$.;]/, '_')
  end

  def self.run_vm_file(filename)
    as = StackVMAssembler.from_file(filename)
    vm = StackVM.from_code(as.assemble)
    vm.run
    return vm, as
  end

  def self.run_vm_code(code)
    as = StackVMAssembler.new(code: code)
    vm = StackVM.from_code(as.assemble)
    vm.run
    return vm, as
  end

  def self.run_texel_file(filename, compiler = Compiler.new)
    parser = Parser.from_file(filename)
    node = parser.parse
    node_output = node.to_a.map { |n| compiler.compile(n) }.join("\ndrop\n")
    code = node_output + "\nhalt\n\n" + compiler.compile_defs
    run_vm_code(code)
  end

  def self.run_texel_code(code, compiler = Compiler.new)
    parser = Parser.new(code: code)
    node = parser.parse.value
    code = compiler.compile(node) + "\nhalt\n\n" + compiler.compile_defs
    run_vm_code(code)
  end

end