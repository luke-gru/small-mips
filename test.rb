require_relative 'main'
require 'tempfile'

l = Lexer.new("if 0 = 1 then 3 else 4")
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
