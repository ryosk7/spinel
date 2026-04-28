# Array#shuffle / Array#shuffle! used to skip ptr_array. The
# dispatcher silently fell through, the result temp ended up `0`,
# and the runtime had no PtrArray shuffle helper to call anyway.

class Bar
  def initialize(x); @x = x; end
  attr_accessor :x
end

arr = [Bar.new(1), Bar.new(2), Bar.new(3)]
puts arr.shuffle.length
