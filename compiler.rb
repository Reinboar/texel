module TexelLisp

  class FunctionDef
    attr_accessor :params

    def emit
      raise "Unimplemented"
    end
  end

  class PrimitiveFun < FunctionDef
    @@prim_fun_ind = 0
    attr_accessor :code, :name, :label

    def initialize(name, code, params)
      @name = name
      @label = TexelLisp.sanitize_label(name)+"_prim_#{@@prim_fun_ind}"
      @@prim_fun_ind += 1
      @params = params
      @code = code
    end

    def emit(args)
      raise "Wrong number of arguments given. Given: #{args.size} Expected: #{@params.size}" unless args.size == @params.size
      @code
    end

  end

  class UserFun < FunctionDef
    @@user_fun_ind = 0
    attr_accessor :name, :label, :code

    def initialize(name, node)
      @name = name
      @label = TexelLisp.sanitize_label(name)+"_func_#{@@user_fun_ind}"
      @@user_fun_ind += 1
      @code = node
    end
  end

  class SpecialForm
    attr_reader :name, :block

    def initialize(name:, &block)
      @name, @block = name, block
    end

    def execute(compiler, children)
      @block.call(compiler, children)
    end
  end

  class LocalVar
    attr_accessor :name, :stack_pos

    def initialize(name:,stack_pos:)
      @name, @stack_pos = name, stack_pos
    end
  end

  class UserConstant
    attr_reader :name, :value

    def initialize(name:, value:)
      @name, @value = name, value
    end
  end

  class GlobalVar
    @@global_var_ind = 0
    attr_reader :name, :label, :init_val

    def initialize(name:, init: 0)
      @name = name
      @init = init
      @label = TexelLisp.sanitize_label(name).downcase+"_var_#{@@global_var_ind}"
      @@global_var_ind += 1
    end

    def emit_def
      %Q{
      #{label}:
      .cell #{@init}
      }
    end
  end

  class SymbolTable
    attr_accessor :symbols, :symbol_index

    def initialize
      @symbols = {}
      @symbol_index = 1
    end

    def add_symbol(name)
      return @symbols[name] if symbol_exists?(name)
      @symbols[name] = @symbol_index
      @symbol_index += 1
      @symbols[name]
    end

    def get_symbol(name)
      return @symbols[name] if symbol_exists?(name)
      add_symbol(name)
    end

    def symbol_exists?(name)
      !@symbols[name].nil?
    end

  end

  class DynamicLabelGenerator
    attr_accessor :label_ind

    def initialize
      @label_ind = -1
    end

    def next
      @label_ind += 1
      "__label_#{@label_ind.to_s}"
    end
  end

  class Context
    attr_accessor :definitions, :parent, :locals_size

    def initialize(parent: nil, locals_size: 0)
      @definitions = {}
      @parent = parent
      @locals_size = locals_size
    end

    def extend(locals_size: 0)
      Context.new(parent: self, locals_size: locals_size)
    end

    def lookup(name)
      if @definitions[name] && @definitions[name].is_a?(LocalVar)
        orig_local = @definitions[name]
        return LocalVar.new(name: orig_local.name, stack_pos: orig_local.stack_pos)
      end
      return @definitions[name] if @definitions[name]
      return nil unless @parent
      p_lookup = @parent.lookup(name)
      p_lookup.stack_pos += @locals_size if p_lookup.is_a?(LocalVar)
      p_lookup
    end

    def add_ident(name, node)
      @definitions[name] = lookup(node.value) if node.type == :IDENTIFIER
      self
    end

    def add_func(name, node)
      @definitions[name] = UserFun.new(name, node)
      self
    end

    def add_primitive(name, code, params)
      @definitions[name] = PrimitiveFun.new(name, code, params)
      self
    end

    def add_special(name, &block)
      @definitions[name] = SpecialForm.new(name: name, &block)
      self
    end

    def add_global(name, val)
      @definitions[name] = GlobalVar.new(name: name, init: val)
      self
    end

    def add_constant(name, val)
      @definitions[name] = UserConstant.new(name: name, value: val)
      self
    end

    def add_local(name, stack_pos)
      @definitions[name] = LocalVar.new(name: name, stack_pos: stack_pos)
      self
    end

    def add_raw(name, val)
      @definitions[name] = val
      self
    end
  end

  class Compiler
    attr_accessor :context, :symbol_table, :label_gen, :global_table

    def initialize
      @context = Context.new
      @symbol_table = SymbolTable.new
      @label_gen = DynamicLabelGenerator.new
      @global_table = {} # hash used for compiling all functions and globals,
                         # even those that are defined in children contexts
    end

    def compile(val)
      if val.is_a?(SyntaxNode)
        fun_val = @context.lookup(val.value.value)
        return fun_val.execute(self, val.children) if fun_val.is_a?(SpecialForm)
        output = ""
        raise "Passed '#{val.value.value}' #{val.children.size} arguments but expected #{fun_val.params}." if fun_val.is_a?(FunctionDef) && fun_val.params != val.children.size
        #binding.irb if fun_val.is_a?(FunctionDef) && fun_val.params != val.children.size
        val.children.each { |c| output += compile(c) + "\n" }
        return output + "call_sub #{fun_val.label}" if fun_val && fun_val.is_a?(FunctionDef)
        raise "#{val.value.value} is not defined." unless fun_val
        raise "#{val.value.value} is not a function."
      elsif val.is_a?(CodeToken)
        case val.type
        when :NUMBER
          return "push_lit #{val.value}"
        when :IDENTIFIER
          id_val = @context.lookup(val.value)
          return "push_slot #{id_val.stack_pos} ; #{val.value}" if id_val.is_a?(LocalVar)
          return "push_lit #{id_val.label}\npush_mem" if id_val.is_a?(GlobalVar)
          return "push_lit #{id_val.value}" if id_val.is_a?(UserConstant)
          raise "Undefined identifier: #{val.value}"
        when :SYMBOL
          symbol_val = @symbol_table.get_symbol(val.value)
          return "push_lit #{symbol_val}"
        else
          raise "Unimplemented"
        end
      end
    end

    def compile_identifier(ident)
      id_val = @context.lookup(ident)
      return "push_slot #{id_val.stack_pos}" if id_val.is_a?(LocalVar)
      return "push_lit #{id_val.value}" if id_val.is_a?(UserConstant)
    end

    def compile_function(name, defn)
        code = defn.code
        "#{defn.label}:\n" +
          "#{code}\n\n"
    end

    def compile_global(name, defn)
      defn.emit_def
    end

    # searches current context for 'name' and adds it to the global table
    def add_to_global_table(name)
      def_lookup = @context.lookup(name)
      return false unless def_lookup
      return false if @global_table[name]
      @global_table[name] = def_lookup
      true
    end

    def compile_defs
      @global_table.to_a.map do |d|
        name, defn = d
        case defn
        when FunctionDef, PrimitiveFun, UserFun
          compile_function(name, defn)
        when GlobalVar
          compile_global(name, defn)
        end
      end.join("\n")
    end

    def add_primitive(name, code, param_num)
      @context.add_primitive(name, code, param_num)
      add_to_global_table(name)
      self
    end

    def add_func(name, code)
      @context.add_func(name, code)
      self
    end

    def add_special(name, &block)
      @context.add_special(name, &block)
      add_to_global_table(name)
      self
    end

    def add_def(name, node)
      @context.add_ident(name, node)
      self
    end

    def add_global(name, val)
      @context.add_global(name, val)
      add_to_global_table(name)
      self
    end

    def add_raw(name, val)
      @context.add_raw(name, val)
      self
    end

  end
end