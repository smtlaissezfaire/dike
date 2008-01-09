require 'dike'

Leaks = Array.new

class Leak
  def initialize
    @leak = 42.chr * (2 ** 20)
  end
end

Dike.logfactory './log/'

Dike.finger

3.times{ Leaks << Leak.new  }

Dike.finger

2.times{ Leaks << Leak.new  }

Dike.finger

