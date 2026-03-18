# Test Struct

Point = Struct.new(:x, :y)

p1 = Point.new(3, 4)
puts p1.x       # 3
puts p1.y       # 4

p1.x = 10
puts p1.x       # 10

# Struct with methods
Color = Struct.new(:r, :g, :b)

c = Color.new(255, 128, 0)
puts c.r        # 255
puts c.g        # 128
puts c.b        # 0
