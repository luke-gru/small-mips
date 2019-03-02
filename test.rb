require_relative 'main'
require 'tempfile'

l = Lexer.new("def okay() = 1\nokay()")
#res = l.tokenize
#pp res

p = Parser.new(l)
ast = p.parse()
pp ast
=begin
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
=end
