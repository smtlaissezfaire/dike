require 'dike'

class Leak < ::String
end

Leaks = Array.new

Dike.filter Leak 

loop do
  Leaks << Leak.new('leak' * 1024)
  Dike.finger
  sleep 1
end
