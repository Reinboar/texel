module TexelLisp

  PAREN_CHARS = ['(',')','[',']','{','}']
  WHITESPACE_CHARS = [" ","\n","\r","\t"]

  class CodeToken
    attr_accessor :type, :value

    def initialize(type:,value:)
      @type, @value = type, value
    end
  end

  class Lexer
    attr_accessor :content, :position, :line

    def initialize(code:)
      @content, @position, @line = code.gsub(/\n+$/, ""), 0, 1
    end

    def end_of_stream
      @position >= @content.length
    end

    def next_token
      tokenify_term(next_term)
    end

    private

    def tokenify_term(term)
      return nil unless term
      return CodeToken.new(type: :NUMBER, value: term.to_i) if /^-?[0-9]+$/.match?(term)
      return CodeToken.new(type: :SYMBOL, value: term[1..-1]) if /^:\w+$/.match?(term)
      return CodeToken.new(type: :STRING, value: term[1..-2]) if /^".*"$/.match?(term)
      return CodeToken.new(type: :LEFT_PAREN, value: term) if ['(','[','{'].include?(term)
      return CodeToken.new(type: :RIGHT_PAREN, value: term) if [')',']','}'].include?(term)
      CodeToken.new(type: :IDENTIFIER, value: term)
    end

    def skip_until_end_of_line
      until cur_char == "\n" || end_of_stream
        @position += 1
      end
    end

    def next_char
      @line += 1 if cur_char == "\n"
      result = cur_char
      @position += 1
      result
    end

    def cur_char
      @content[@position]
    end

    def skip_until_next_term
      while !end_of_stream && WHITESPACE_CHARS.include?(cur_char)
        next_char
      end
      if cur_char == ';'
        skip_until_end_of_line
        skip_until_next_term
      end
    end

    def next_ident_term
      result_term = ""
      until WHITESPACE_CHARS.include?(cur_char) || PAREN_CHARS.include?(cur_char)
        nc = next_char
        result_term += nc if nc
        return result_term unless nc
      end
      result_term
    end

    def next_string_term
      result_str_term = next_char
      until cur_char == '"' || end_of_stream
        result_str_term += next_char
      end
      result_str_term + next_char
    end

    def next_term
      skip_until_next_term
      return nil if end_of_stream
      return next_char if PAREN_CHARS.include?(cur_char)
      return next_string_term if cur_char == '"'
      next_ident_term
    end
  end

  class SyntaxNode
    include Enumerable
    attr_accessor :value, :children

    def initialize(value: nil, children: [])
      @value, @children = value, children
    end

    def length
      return @children.length + 1 if @value
      0
    end

    def num_children
      @children.length
    end

    def each
      yield @value if @value
      @children.each { |c| yield c }
    end

    def each_depth
      @children.each { |c| yield c }
      yield @value
    end

    def evaluate(&block)
      yield(@value, @children)
    end

    def recursive_depth(&block)
      self.each_depth do |c|
        if c.is_a?(SyntaxNode)
          c.each_depth(&block)
          yield c
        else
          yield c
        end
      end
    end

    def add(c)
      if @value
        add_child(c)
      else
        @value = c
      end
      self
    end

    def add_child(c)
      @children.append(c)
      self
    end

    def add_child_node(c)
      add_child(SyntaxNode.new(value: c))
    end

  end

  class Parser
    attr_accessor :lexer

    def self.from_file(filename)
      Parser.new(code: File.read(filename))
    end

    def initialize(code:)
      @lexer = Lexer.new(code: code)
    end

    def parse
      root_node = SyntaxNode.new(value: nil)
      until @lexer.end_of_stream
        root_node.add(process_token(@lexer.next_token))
      end
      root_node
    end

    private

    def process_left_paren
      initial_tok = @lexer.next_token
      return SyntaxNode.new if initial_tok.type == :RIGHT_PAREN
      sn = SyntaxNode.new(value: process_token(initial_tok))
      while (t = @lexer.next_token) && t.type != :RIGHT_PAREN
        sn.add_child(process_token(t))
      end
      sn
    end

    def process_token(token)
      case token.type
      when :LEFT_PAREN
        process_left_paren
      when :RIGHT_PAREN
        raise "Unmatched right paren."
      else
        token
      end
    end

  end
end