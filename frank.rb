require 'sinatra'
require 'redis'
require 'yaml'
require 'erb'
require 'json'


config = YAML.load_file('redis.yml')
config = config['production'].inject({}){|r,a| r[a[0].to_sym]=a[1]; r}
RedisConnection =Redis.new( config  )

get  '/' do 
  @keys  = RedisConnection.keys("subject_*").collect{|k| "#{k} : #{RedisConnection.ttl k} "}
  erb :index
end

post '/observations/' do
  if params[:observation_id] 
    RedisConnection.set "current_target", params[:observation_id]
    return [201,"updated observation id"]
  else
    return [406,"submit a current observation id"]
  end
end


get '/keys' do
  RedisConnection.keys("subject_*").inject({}){|r,k| r[k]={:ttl=>RedisConnection.ttl(k)}; r }.to_json
end

post '/subjects/' do 
  unless params[:file] &&
        (tmpfile = params[:file][:tempfile]) &&
        (name = params[:file][:filename]) &&
        (activity_id = params[:subject][:activity_id]) &&
        (source_id   = params[:subject][:source_id]) &&
        (observation_id = params[:subject][:observation_id])
        
   @error = "No file selected"
   return [406, "problem"]
 end
 STDERR.puts "Uploading file, original name #{name.inspect}"
 file=''
 
 while blk = tmpfile.read(65536)
   file << blk
 end
 RedisConnection.set "subject_#{source_id}_#{activity_id}_#{observation_id}", file
 RedisConnection.expire "subject_#{source_id}_#{activity_id}_#{observation_id}", 120000
 return [201, "created succesfully"]
end





