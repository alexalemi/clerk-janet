# # clerk-janet — quick tour
#
# A demo of every feature: prose cells (these very comments!),
# **hidden code** via `# @clerk:hide-code` directives, syntax
# highlighting, captured stdout, lists, links, and inline LaTeX math.

# ## Arithmetic
#
# Just to show plain expressions render as values.

(defn sq [x] (* x x))

(sq 7)

# ## Captured stdout
#
# Anything a cell `print`s shows up in-place, not in the terminal.

(do
  (printf "computing 6^2 + 8^2 = ")
  (+ (sq 6) (sq 8)))

# ## Markdown features
#
# - Unordered list item one
# - Item two with **bold**
# - Item three with `inline code`
#
# 1. First ordered
# 2. Second ordered
#
# Links: visit [the Janet docs](https://janet-lang.org/docs/) or
# explore https://github.com/janet-lang/spork for the standard
# library.

# ## Math
#
# Pythagoras' theorem: $a^2 + b^2 = c^2$.
#
# $$ c = \sqrt{a^2 + b^2} $$

(def a 3)
(def b 4)

(math/sqrt (+ (sq a) (sq b)))

# ## A table of squares

(seq [n :range [1 6]]
  {:n n :sq (sq n) :cube (* n n n)})
