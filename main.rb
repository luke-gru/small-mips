class Lexer
  require 'strscan'
  class Error < StandardError; end
  def initialize(source)
    @s = StringScanner.new(source)
    @tokens = []
    @emitted_eof = false
  end

  def tokenize
    while (tok = next_token)
      @tokens << tok
    end
    @tokens
  end

  def next_token
    while !@s.eos?
      if @s.scan /\A\(/
        return [:LPAREN, '(']
      elsif @s.scan /\A\)/
        return [:RPAREN, '(']
      elsif @s.scan /\A,/
        return [:COMMA, ',']
      elsif (num = @s.scan /\A(\d+)/)
        return [:NUMBER, num.to_i]
      elsif @s.scan /\A\+/
        return [:PLUS, '+']
      elsif @s.scan /\A\-/
        return [:MINUS, '-']
      elsif @s.scan /\Adef/
        return [:DEF, 'def']
      elsif @s.scan /\Aif/
        return [:IF, 'if']
      elsif @s.scan /\Athen/
        return [:THEN, 'then']
      elsif @s.scan /\Aelse/
        return [:ELSE, 'else']
      elsif @s.scan /\A=/
        return [:EQUAL, '=']
      elsif (ident = @s.scan /\A\w+/)
        return [:IDENT, ident]
      elsif @s.scan /\A\s+/ # whitespace
        next
      else
        raise Error, "Unrecognized character: #{@s.peek(1)}"
      end
    end
    if @emitted_eof
      nil
    else
      @emitted_eof = true
      [:EOF, '']
    end
  end
end

module Nodes
  class NumberNode
    attr_reader :number
    def initialize(number)
      @number = number
    end
  end

  class OpNode
    attr_reader :lhs, :rhs, :op
    def initialize(lhs, rhs, op)
      @lhs = lhs
      @rhs = rhs
      @op = op
    end
  end
  class FunDeclNode
    attr_reader :name, :args, :expr
    def initialize(name, args, expr)
      @name = name
      @args = args
      @expr = expr
    end
  end
  class ParamNode
  attr_reader :name
    def initialize(name)
      @name = name
    end
  end
  class ProgramNode
    attr_reader :decls
    def initialize(decls)
      @decls = decls
    end
  end
  class CallNode
    attr_reader :name, :args
    def initialize(name, args)
      @name = name
      @args = args
    end
  end
  class ExprDeclNode
    attr_reader :expr
    def initialize(expr)
      @expr = expr
    end
  end
  class IfElseNode
    attr_reader :lhs, :rhs, :if_br, :else_br
    def initialize(lhs, rhs, if_br, else_br)
      @lhs = lhs
      @rhs = rhs
      @if_br = if_br
      @else_br = else_br
    end
  end
  class VariableNode
    attr_reader :name
    def initialize(name)
      @name = name
    end
  end
end

class Parser
  include Nodes # for namespace
  class Error < StandardError; end
  def initialize(lexer)
    @l = lexer
    @tokbuf = []
    advance()
  end

  def advance
    raise "tokbuf size" if @tokbuf.size > 1
    if @tokbuf.size == 1
      @curtok = @tokbuf.pop()
    else
      @curtok = @l.next_token
    end
  end

  def peek
    raise "tokbuf > 1" if @tokbuf.size > 1
    if @tokbuf.size == 0
      prev = @curtok
      @tokbuf << advance()
      @curtok = prev
    end
    @tokbuf[0]
  end

  def match?(kind)
    @curtok[0] == kind ? @curtok[1] : nil
  end

  def consume(*kinds, msg: "Error")
    if kinds.any? { |k| match?(k) }
      ret = @curtok[1]
      advance()
      ret
    else
      raise Error, msg
    end
  end

  def parse
    decls = []
    until eof?
      decls << parse_decl()
    end
    ProgramNode.new(decls)
  end

  def parse_decl
    if match?(:DEF)
      advance()
      fn_name = consume(:IDENT, msg: "Expected identifier after def")
      consume(:LPAREN, msg: "Expected '(' after function name")
      arg_exprs = []
      while match?(:IDENT)
        arg_exprs << ParamNode.new(@curtok[1])
        advance()
        if match?(:COMMA)
          advance()
        end
      end
      consume(:RPAREN, msg: "Expected ')' after function arguments")
      consume(:EQUAL, msg: "Expected '=' before function body")
      body = parse_expression()
      FunDeclNode.new(fn_name, arg_exprs, body)
    else
      ExprDeclNode.new(parse_expression())
    end
  end

  def parse_expression
    ret = if match?(:NUMBER)
      numtok = @curtok
      advance()
      NumberNode.new(numtok[1])
    elsif match?(:IDENT) && peek()[0] == :LPAREN
      fn_name = @curtok[1]
      advance()
      advance() # '('
      args = []
      until match?(:RPAREN)
        args << parse_expression()
      end
      advance()
      CallNode.new(fn_name, args)
    elsif match?(:IF)
      advance()
      lhs = parse_expression()
      consume(:EQUAL, msg: "Expected '=' after if lhs")
      rhs = parse_expression()
      consume(:THEN, msg: "Expected 'then' after if rhs")
      if_expr = parse_expression()
      consume(:ELSE, msg: "Expected 'else' in if expr")
      else_expr = parse_expression()
      IfElseNode.new(lhs, rhs, if_expr, else_expr)
    elsif match?(:IDENT)
      ident = consume(:IDENT, msg: "expected identifier")
      VariableNode.new(ident)
    else
      raise Error, "Unexpected token: #{@curtok}"
    end
    if match?(:PLUS) || match?(:MINUS)
      op = @curtok[0]
      consume(:PLUS, :MINUS, msg: "Expected '+' or '-'")
      rhs = parse_expression()
      OpNode.new(ret, rhs, op)
    else
      ret
    end
  end

  def eof?
    @curtok[0] == :EOF
  end
end

class Label
  $label_num = 0
  def initialize(type)
    @type = type
    @num = $label_num
    $label_num+=1
  end

  def to_s
    "#{@type}_label#{@num}"
  end
end

class MipsCompiler
  include Nodes
  class Error < StandardError; end
  ACC = "$a0"
  TMP = "$t1"
  SP  = "$sp"
  FP  = "$fp"
  RA  = "$ra"

=begin
MIPS Frame (Activation Record) layout (stack grows down):

old fp
---
arg n
---
...
---
arg 0
---
return addr     $FP
---
Temp N
---
...
---
Temp 0
                $SP
=end

  class MipsFrame
    attr_reader :name
    attr_accessor :num_temps
    def initialize(name)
      @name = name
      @num_temps = 0
    end
  end

  # Temps are saved in frame instead of constantly pushing/loading from stack,
  # so number of needed temps is computed for each frame, including main.
  class Temporaries
    include Nodes
    attr_reader :main, :frames
    def initialize(ast)
      @ast = ast
      @main = MipsFrame.new("main")
      @frames = [@main]
      @frame = @main
    end

    def find_temps
      temps = []
      @ast.decls.each do |decl|
        temps << n_temps(decl)
      end
      @frame.num_temps = temps.max
    end

    def num_temps_for(fn_name)
      frame = @frames.find { |f| f.name == fn_name }
      raise "Frame for #{fn_name} not found" unless frame
      frame.num_temps
    end

    private
    def n_temps(expr)
      case expr
      when NumberNode, VariableNode
        0
      when OpNode
        max(n_temps(expr.lhs), n_temps(expr.rhs) + 1)
      when IfElseNode
        max(n_temps(expr.lhs), n_temps(expr.rhs) + 1, n_temps(expr.if_br), n_temps(expr.else_br))
      when CallNode
        max(*(expr.args.map { |expr| n_temps(expr) }))
      when ExprDeclNode
        n_temps(expr.expr, )
      when FunDeclNode
        old_frame = @frame
        @frame = MipsFrame.new(expr.name)
        temps = n_temps(expr.expr)
        @frame.num_temps = temps
        @frames << @frame
        @frame = old_frame
        temps
      else
        raise "Unknown node: #{expr.class}"
      end
    end

    def max(*n)
      n.max
    end
  end

  attr_reader :buf
  def initialize(ast)
    @ast = ast
    @buf = []
    @fun_nodes = []
    @output_functions = false
    @cur_func = nil
    @temps = nil
  end

  def compile
    @temps = Temporaries.new(@ast)
    @temps.find_temps
    cgen(@ast, 4)
    exitt()
    @output_functions = true
    @fun_nodes.each { |fnode| cgen(fnode, 4) }
  end

  def cgen(expr, nt)
    case expr
    when ProgramNode
      expr.decls.each { |decl| cgen(decl, nt) }
    when ExprDeclNode
      cgen(expr.expr, nt)
    when NumberNode
      @buf << "li #{ACC} #{expr.number}"
    when OpNode
      cgen(expr.lhs, nt)
      @buf << "sw #{ACC} #{-nt}(#{FP})" # store into temp spot in frame
      cgen(expr.rhs, nt+4)
      @buf << "lw #{TMP} #{-nt}(#{FP})"
      if expr.op == :PLUS
        add(ACC, TMP)
      else
        sub(ACC, TMP)
      end
    when IfElseNode
      cgen(expr.lhs, nt)
      @buf << "sw #{ACC} #{-nt}(#{FP})" # store into temp spot in frame
      cgen(expr.rhs, nt+4)
      @buf << "lw #{TMP} #{-nt}(#{FP})"
      true_lbl = Label.new(:true)
      end_lbl = Label.new(:endif)
      @buf << "beq #{ACC} #{TMP} #{true_lbl}"
      cgen(expr.else_br, nt)
      @buf << "b #{end_lbl}"
      @buf << "#{true_lbl}:"
      cgen(expr.if_br, nt)
      @buf << "#{end_lbl}:"
    when CallNode
      if expr.name == 'print' # syscall
        cgen(expr.args[0], nt)
        printt()
      else
        push(FP) # caller
        expr.args.reverse_each do |arg|
          cgen(arg, nt)
          push(ACC)
        end
        @buf << "jal #{expr.name}_entry"
      end
    when FunDeclNode
      if @output_functions
        @buf << "#{expr.name}_entry:" # callee
        @buf << "move #{FP} #{SP}"
        push(RA)
        push_frame_temps(expr.name)
        old = @cur_func
        @cur_func = expr
        cgen(expr.expr, 4)
        @cur_func = old
        @buf << "lw #{RA} 0(#{FP})"
        pop_frame(expr.name, expr.args.size)
        @buf << "lw #{FP} 0(#{SP})"
        @buf << "jr #{RA}"
      else
        @fun_nodes << expr
      end
    when VariableNode
      if @cur_func.nil?
        raise Error, "variable #{expr.name} needs to be inside function"
      end
      unless @output_functions
        raise Error, "need to be outputting functions"
      end
      param_index = @cur_func.args.find_index { |arg| arg.name == expr.name }
      if param_index == nil
        raise Error, "variable name #{expr.name} not found"
      end
      @buf << "lw #{ACC} #{4*param_index+4}(#{FP})"
    else
      raise Error, "unknown node #{expr.class}"
    end
  end

  def push(reg)
    @buf << "sw #{reg} 0(#{SP})"
    @buf << "addiu #{SP} #{SP} -4"
  end

  def pop
    @buf << "addiu #{SP} #{SP} 4"
  end

  def load_stack_top(reg)
    @buf << "lw #{reg} 4(#{SP})"
  end

  def push_frame_temps(fn_name)
    num_temps = @temps.num_temps_for(fn_name)
    @buf << "addiu #{SP} #{SP} #{-4*num_temps}"
  end

  def pop_frame_temps(fn_name)
    num_temps = @temps.num_temps_for(fn_name)
    @buf << "addiu #{SP} #{SP} #{4*num_temps}"
  end

  def pop_frame(fn_name, nargs)
    num_temps = @temps.num_temps_for(fn_name)
    @buf << "addiu #{SP} #{SP} #{(4*nargs)+8+(4*num_temps)}"
  end

  def add(reg1, reg2)
    @buf << "add #{ACC} #{reg1} #{reg2}"
  end

  def sub(reg1, reg2)
    @buf << "sub #{ACC} #{reg2} #{reg1}"
  end

  def printt
    @buf << "li $v0 1"
    @buf << "syscall"
  end

  def exitt
    @buf << "li $v0 10"
    @buf << "syscall"
  end

  def output
    @buf = preamble + @buf
    @buf
  end

  def preamble
    [".text", ".globl main", "main:"]
  end
end
