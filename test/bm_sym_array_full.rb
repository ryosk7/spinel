# Full sym_array test
a = [:red, :green, :blue, :yellow]

# Basic access
puts a.length       # 4
puts a[0]           # red
puts a[3]           # yellow
puts a[-1]          # yellow

# each
a.each { |s| puts s }
# red green blue yellow

# push
a.push(:purple)
puts a.length       # 5

# pop
v = a.pop
puts v              # purple

# include?
puts a.include?(:red)   # true
puts a.include?(:pink)  # false

# map
b = a.map { |s| s.to_s }
puts b.length       # 4
puts b[0]           # red

# select
c = a.select { |s| s.to_s.length > 4 }
puts c.length       # 2

# each_with_index
a.each_with_index do |s, i|
  if i == 0
    puts s          # red
  end
end

# sort (by symbol name, lexical)
d = [:cherry, :apple, :banana]
d_sorted = d.sort
puts d_sorted[0]    # apple
puts d_sorted[1]    # banana
puts d_sorted[2]    # cherry

# puts of sym_array
puts a              # should print each element on its own line
