# Test array literals as IntArray/StrArray

# Integer array literal
arr = [5, 3, 8, 1, 4]
puts arr.length    # 5
puts arr[0]        # 5
puts arr.sort[0]   # 1
puts arr.sum       # 21
puts arr.min       # 1
puts arr.max       # 8

# String array literal
words = ["hello", "world", "foo"]
puts words.length  # 3
puts words[0]      # hello
puts words.join(", ") # hello, world, foo

# Empty array
empty = []
empty.push(42)
puts empty.length  # 1
puts empty[0]      # 42

puts "done"
