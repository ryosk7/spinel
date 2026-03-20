# Test File.open with block

# Write with block
File.open("/tmp/spinel_fopen_test.txt", "w") do |f|
  f.puts "line 1"
  f.puts "line 2"
  f.puts "line 3"
end

# Read with block
File.open("/tmp/spinel_fopen_test.txt", "r") do |f|
  f.each_line do |line|
    puts line
  end
end

# File.open without block (returns file object)
# Skip — needs explicit close, less common

# Cleanup
File.delete("/tmp/spinel_fopen_test.txt")
puts "done"
