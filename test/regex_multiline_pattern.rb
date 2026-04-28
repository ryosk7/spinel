# A regex whose source contains literal newlines, tabs, or CRs must be
# emitted as a properly escaped C string literal. Otherwise the embedded
# raw character closes the C string mid-token and the generated
# `re_compile` call doesn't parse at all (a C compile error, not a
# runtime mismatch).

# Multi-line /x pattern. The match itself is regex-engine business; the
# point of the test is that the binary builds and the matcher runs at
# all.
re = /
  bar
/x
if re =~ "barbar"
  puts "ok1"
else
  puts "no1"
end

# Tab / CR / newline escapes anywhere in the source.
re_t = /a\tb/
if re_t =~ "a\tb"
  puts "ok2"
else
  puts "no2"
end

re_n = /a\nb/
if re_n =~ "a\nb"
  puts "ok3"
else
  puts "no3"
end

re_r = /a\rb/
if re_r =~ "a\rb"
  puts "ok4"
else
  puts "no4"
end
