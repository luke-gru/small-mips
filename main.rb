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
      elsif (num = @s.scan /\A(\d+)/)
        return [:NUMBER, num.to_i]
      elsif @s.scan /\A\+/
        return [:PLUS, '+']
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
        raise Error, "Unrecognized character: #{@s.peek(0)}"
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

  def consume(kind, msg)
    if match?(kind)
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
      advance();
      fn_name = consume(:IDENT, "Expected identifier after def")
      consume(:LPAREN, "Expected '(' after function name")
      arg_exprs = []
      until match?(:RPAREN)
        arg_exprs << parse_expression()
      end
      consume(:RPAREN, "Expected ')' after function arguments")
      consume(:EQUAL, "Expected '=' before function body");
      body = parse_expression()
      FunDeclNode.new(fn_name, arg_exprs, body)
    else
      ExprDeclNode.new(parse_expression())
    end
  end

  def parse_expression
    if match?(:NUMBER)
      numtok = @curtok
      advance()
      if match?(:PLUS)
        lhs = NumberNode.new(numtok[1])
        advance()
        rhs = parse_expression()
        OpNode.new(lhs, rhs, :PLUS)
      else
        NumberNode.new(numtok[1])
      end
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
      consume(:EQUAL, "Expected '=' after if lhs")
      rhs = parse_expression()
      consume(:THEN, "Expected 'then' after if rhs")
      if_expr = parse_expression()
      consume(:ELSE, "Expected 'else' in if expr")
      else_expr = parse_expression()
      IfElseNode.new(lhs, rhs, if_expr, else_expr)
    else
      raise Error, "Unexpected token: #{@curtok}"
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

  class MipsFrame
  end

  attr_reader :buf
  def initialize(ast)
    @ast = ast
    @buf = []
  end

  def compile
    cgen(@ast)
    print()
    exitt()
  end

  def cgen(expr)
    case expr
    when ProgramNode
      expr.decls.each { |decl| cgen(decl) }
    when ExprDeclNode
      cgen(expr.expr)
    when NumberNode
      @buf << "li #{ACC} #{expr.number}"
    when OpNode
      cgen(expr.lhs)
      push(ACC)
      cgen(expr.rhs)
      load_stack_top(TMP)
      add(ACC, TMP)
      pop()
    when IfElseNode
      cgen(expr.lhs)
      push(ACC)
      cgen(expr.rhs)
      load_stack_top(TMP)
      pop()
      true_lbl = Label.new(:true)
      end_lbl = Label.new(:endif)
      @buf << "beq #{ACC} #{TMP} #{true_lbl}"
      cgen(expr.else_br)
      @buf << "b #{end_lbl}"
      @buf << "#{true_lbl}:"
      cgen(expr.if_br)
      @buf << "#{end_lbl}:"
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

  def add(reg1, reg2)
    @buf << "add #{ACC} #{reg1} #{reg2}"
  end

  def print
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
