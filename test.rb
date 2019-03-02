require_relative 'main'
require 'tempfile'

l = Lexer.new("def fib(n) = if n = 0 then 1 else n\nfib(2)")
#res = l.tokenize
#pp res

p = Parser.new(l)
ast = p.parse()
pp ast
#STDERR.puts ast.decls.size
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
