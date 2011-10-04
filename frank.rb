require 'sinatra'
require 'redis'
require 'yaml'

config = YAML.load_file( 'redis.yml')
puts config["development"]
config = config["production"].inject({}){|r,a| r[a[0].to_sym]=a[1]; r}
RedisConnection =Redis.new( config  )

get  '/' do 
  keys_and_time  = RedisConnection.keys("subject_*").inject(""){|r,k| r<<"#{k} : #{RedisConnection.ttl k} s <br/>"; r}
  "Frank has the following keys: <br/> #{keys_and_time}"
end

post '/subjects/' do 
  unless params[:file] &&
        (tmpfile = params[:file][:tempfile]) &&
        (name = params[:file][:filename]) &&
        (activity_id = params[:subject][:activity_id]) &&
        (source_id   = params[:subject][:source_id]) &&
        (observation_id = params[:subject][:observation_id])
        
   @error = "No file selected"
   return "problem"
 end
 STDERR.puts "Uploading file, original name #{name.inspect}"
 file=''
 
 while blk = tmpfile.read(65536)
   file << blk
 end
 RedisConnection.set "subject_#{source_id}_#{activity_id}_#{observation_id}", file
 RedisConnection.expire "subject_#{source_id}_#{activity_id}_#{observation_id}", 120
end


