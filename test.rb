require_relative 'main'
require 'tempfile'

l = Lexer.new("def sumto(n) = if n = 0 then 0 else n+sumto(n-1)\n" +
              "print(sumto(5))")
#l = Lexer.new("def sumto(n) = n+n\nsumto(4)")
#l = Lexer.new("def sumto(n) = if n = 0 then 1 else 2\nsumto(4)")
#res = l.tokenize
#pp res

p = Parser.new(l)
ast = p.parse()
pp ast

STDERR.puts ast.decls.size
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
