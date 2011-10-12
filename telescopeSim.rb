files = Dir.glob("example_data/*.bson")
no_files = files.count

observation_id= 0
source_id = 0 
activity_id =0
while 
	file =files[rand(no_files)]
	puts file
	`curl -F "file=@/Users/stuartlynn/Sites/SETI/apps/Frank/#{file};type=data/bson" -F "subject[activity_id]=#{activity_id}" -F "subject[observation_id]=#{observation_id}" -F "subject[source_id]=#{source_id}" http://0.0.0.0:5000/subjects/`
	sleep 2.0
	activity_id += 1 
end