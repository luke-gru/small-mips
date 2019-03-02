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
      elsif @s.scan /\A\w+/ # whitespace
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
    attr_reader :lhs, :rhs
    def initialize(lhs, rhs, op)
      @lhs = lhs
      @rhs = rhs
      @op = op
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
    if @tokbuf.size == 1
      @curtok = @tokbuf.pop()
    else
      @curtok = @l.next_token
    end
  end

  def peek
    if @tokbuf.size == 0
      @tokbuf << advance()
    end
    @tokbuf[0]
  end

  def match?(kind)
    @curtok[0] == kind ? @curtok[1] : nil
  end

  def parse
    until eof?
      res = parse_expression
    end
    res
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
    else
      raise Error, "Unexpected token: #{@curtok}"
    end
  end

  def eof?
    @curtok[0] == :EOF
  end
end

class MipsCompiler
  include Nodes
  class Error < StandardError; end
  ACC = "$a0"
  TMP = "$t1"
  SP  = "$sp"
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
    when NumberNode
      @buf << "li #{ACC} #{expr.number}"
    when OpNode
      cgen(expr.lhs)
      push(ACC)
      cgen(expr.rhs)
      load_stack_top(TMP)
      add(ACC, TMP)
      pop()
    else
      raise Error, "unknown node"
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
