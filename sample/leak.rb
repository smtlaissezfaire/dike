require 'rubygems'
require 'net/http'
require './lib/dike.rb'
Dike.logfactory './log/'

class Leak
 def http_call
    puts 'making http call'
    Net::HTTP.start('localhost') do |http|
      puts http.get('/').code
    end
    p ObjectSpace.each_object(Net::HTTPResponse){}
 end
end

5.times {
  leak = Leak.new
  leak.http_call
  GC.start
  Dike.finger
}
