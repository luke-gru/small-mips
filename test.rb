require_relative 'main'
require 'tempfile'

l = Lexer.new("1+1+5")
#res = l.tokenize
#pp res

p = Parser.new(l)
ast = p.parse()
c = MipsCompiler.new(ast)
c.compile
code = c.output
file = Tempfile.open("mips") do |f|
  code.each do |line|
    f.puts line
  end
  f
end
system("spim -file #{file.path}")
