(declare-project
  :name "clerk-janet"
  :description "Live, browser-rendered notebooks for Janet — port of clerk-racket."
  :version "0.1.0"
  :url "https://github.com/alexalemi/clerk-janet"
  :author "Alex Alemi"
  :license "MIT"
  :dependencies ["https://github.com/janet-lang/spork.git"])

(declare-executable
  :name "clerk-janet"
  :entry "main.janet")
