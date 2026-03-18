# Test catch/throw

result = catch(:done) do
  throw :done, 42
  999  # unreachable
end
puts result  # 42

# catch without throw returns block value
result2 = catch(:nope) do
  100
end
puts result2  # 100

# Nested catch (same type)
result3 = catch(:outer) do
  catch(:inner) do
    throw :outer, 77
  end
  0
end
puts result3  # 77

puts "done"
