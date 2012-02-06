Ohm.connect if ENV['RACK_ENV']=='development'
Ohm.connect(:url => ENV['REDIS_URL'] ) if ENV['RACK_ENV']=='production'