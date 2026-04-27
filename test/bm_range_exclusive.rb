# `..` (inclusive) vs `...` (exclusive) Range distinguished correctly
# across slicing, iteration, case/when, and Range#to_a. Previously the
# AST dropped the exclude_end flag, so `1...3` behaved like `1..3`.

# IntArray slicing
ia = [10, 20, 30, 40, 50]
puts ia[1..3].length     # 3 (inclusive)
puts ia[1...3].length    # 2 (exclusive)
puts ia[1...3][0]        # 20
puts ia[1...3][1]        # 30

# StrArray slicing
sa = "a,b,c,d,e".split(",")
puts sa[0..2].join(":")   # a:b:c
puts sa[0...2].join(":")  # a:b

# FloatArray slicing
fa = [1.5, 2.5, 3.5, 4.5]
puts fa[0..2].length     # 3
puts fa[0...2].length    # 2
puts fa[0...3].sum       # 7.5 (non-integer-valued so spinel doesn't strip ".0")

# String slicing (existing path; was a latent bug for `...`)
s = "abcdef"
puts s[1..3]             # bcd
puts s[1...3]            # bc

# for-in iteration
sum_inc = 0
for i in 1..3
  sum_inc = sum_inc + i
end
puts sum_inc             # 6 (1+2+3)

sum_exc = 0
for i in 1...3
  sum_exc = sum_exc + i
end
puts sum_exc             # 3 (1+2)

# Range#to_a
puts (1..3).to_a.length  # 3
puts (1...3).to_a.length # 2

# case / when
def classify(n)
  case n
  when 0...10 then "small"
  when 10..99 then "medium"
  else "large"
  end
end
puts classify(5)         # small
puts classify(9)         # small
puts classify(10)        # medium (inclusive 10..99)
puts classify(99)        # medium
puts classify(100)       # large
