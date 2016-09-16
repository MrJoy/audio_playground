# rubocop:disable Style/LeadingCommentSpace
#ruby-gemset=audio_playground
# rubocop:enable Style/LeadingCommentSpace
source "https://rubygems.org"
ruby "2.3.1"

# http://masa16.github.io/ruby-pgplot/
# http://masa16.github.io/narray/mdary.html
# http://hans.fugal.net/src/ruby-audio/doc/
# http://gridflow.ca/
# http://rb-gsl.rubyforge.org/
# http://ruby.gfd-dennou.org/
gem "ruby-fftw3", "~> 1.0.2",   require: false
gem "coreaudio",  "~> 0.0.11",  require: false
gem "logger-better",            require: false
# See:
#   https://github.com/karlstav/cava
#   http://www.fftw.org/fftw3_doc/Wisdom.html#Wisdom
#     https://rubygems.org/gems/fftw3
#     https://rubygems.org/gems/hornetseye-fftw3
#     https://rubygems.org/gems/ruby-fftw3
#     http://www.fftw.org/fftw3_doc/Words-of-Wisdom_002dSaving-Plans.html#Words-of-Wisdom_002dSaving-Plans
#     http://www.fftw.org/links.html
#     http://www.fftw.org/pruned.html

group :development do
  gem "rake",             require: false
  gem "rubocop",          require: false
  gem "bundler-audit",    require: false
  gem "todo_lint",        require: false

  gem "ruby-prof",        require: false # https://github.com/ruby-prof/ruby-prof
  gem "memory_profiler",  require: false

  # gem "chunky_png",       require: false
  # gem "oily_png",         require: false
end

# gem "ncursesw-ruby" # https://github.com/sup-heliotrope/ncursesw-ruby
# gem "curses" # https://github.com/ruby/curses/blob/master/sample/hello.rb
# gem "ncurses-ruby" # https://github.com/eclubb/ncurses-ruby

group :development, :test do
  gem "pry"
end

# group :test do
#   gem "rspec", "~> 3.3.0"
#   gem "webmock"
# end
