require_relative 'main'
require 'tempfile'

l = Lexer.new("def func() = 1\nfunc()")
#res = l.tokenize
#pp res

p = Parser.new(l)
ast = p.parse()
pp ast
c = MipsCompiler.new(ast)
c.compile
code = c.output
file = Tempfile.open("mips") do |f|
  code.each do |line|
    puts line
    f.puts line
  end
  f
end
system("spim -file #{file.path}")
