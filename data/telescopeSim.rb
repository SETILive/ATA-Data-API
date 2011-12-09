files = Dir.glob("example_data/*.bson")
no_files = files.count

observation_id= 0
source_id = 0 
activity_id = 0
delay = 1

server_address = ARGV.include?("production") ? "http://frank-seti.herokuapp.com/subjects/" : "http://0.0.0.0:5000/subjects/"
puts ARGV
puts "posting at #{server_address}"

while 
	file =files[rand(no_files)]
	puts file
	`curl -F "file=@/Users/stuartlynn/Sites/SETI/apps/Frank/#{file};type=data/bson" -F "subject[activity_id]=#{activity_id}" -F "subject[observation_id]=#{observation_id}" -F "subject[source_id]=#{source_id}" #{server_address}`
	sleep delay
	activity_id += 1 

	if activity_id ==50
		activity_id =0
		observation_id +=1
		source_id = observation_id
	end
end