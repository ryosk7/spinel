# Symbol array
a = [:red, :green, :blue]
puts a.length
a.each { |s| puts s }

# [] access
puts a[0]
puts a[2]

# Also sym_int_hash each
h = {x: 10, y: 20}
h.each do |k, v|
  puts k.to_s + "=" + v.to_s
end
